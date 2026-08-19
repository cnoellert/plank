#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <limits>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <thread>
#include <unistd.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <drm.h>
#include <drm_fourcc.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

namespace {

struct Selection {
  std::uint32_t connector_id = 0;
  std::uint32_t crtc_id = 0;
  drmModeModeInfo mode{};
};

bool better_mode(const drmModeModeInfo& candidate, const drmModeModeInfo& best) {
  const std::uint64_t candidate_area =
      static_cast<std::uint64_t>(candidate.hdisplay) * candidate.vdisplay;
  const std::uint64_t best_area =
      static_cast<std::uint64_t>(best.hdisplay) * best.vdisplay;
  if (candidate_area != best_area) {
    return candidate_area > best_area;
  }
  const bool candidate_preferred = (candidate.type & DRM_MODE_TYPE_PREFERRED) != 0;
  const bool best_preferred = (best.type & DRM_MODE_TYPE_PREFERRED) != 0;
  if (candidate_preferred != best_preferred) {
    return candidate_preferred;
  }
  return candidate.vrefresh > best.vrefresh;
}

std::uint32_t choose_crtc(int fd, const drmModeRes& resources,
                          const drmModeConnector& connector) {
  for (int encoder_index = -1; encoder_index < connector.count_encoders;
       ++encoder_index) {
    const std::uint32_t encoder_id =
        encoder_index < 0 ? connector.encoder_id
                          : connector.encoders[encoder_index];
    if (encoder_id == 0) {
      continue;
    }
    drmModeEncoder* encoder = drmModeGetEncoder(fd, encoder_id);
    if (encoder == nullptr) {
      continue;
    }
    if (encoder->crtc_id != 0) {
      const std::uint32_t crtc_id = encoder->crtc_id;
      drmModeFreeEncoder(encoder);
      return crtc_id;
    }
    for (int crtc = 0; crtc < resources.count_crtcs; ++crtc) {
      if ((encoder->possible_crtcs & (1U << crtc)) != 0U) {
        const std::uint32_t crtc_id = resources.crtcs[crtc];
        drmModeFreeEncoder(encoder);
        return crtc_id;
      }
    }
    drmModeFreeEncoder(encoder);
  }
  return 0;
}

bool choose_output(int fd, const drmModeRes& resources, Selection& selection) {
  bool found = false;
  for (int index = 0; index < resources.count_connectors; ++index) {
    drmModeConnector* connector =
        drmModeGetConnector(fd, resources.connectors[index]);
    if (connector == nullptr || connector->connection != DRM_MODE_CONNECTED ||
        connector->count_modes == 0) {
      drmModeFreeConnector(connector);
      continue;
    }

    drmModeModeInfo best = connector->modes[0];
    for (int mode = 1; mode < connector->count_modes; ++mode) {
      if (better_mode(connector->modes[mode], best)) {
        best = connector->modes[mode];
      }
    }
    const std::uint32_t crtc_id = choose_crtc(fd, resources, *connector);
    if (crtc_id != 0 && (!found || better_mode(best, selection.mode))) {
      selection.connector_id = connector->connector_id;
      selection.crtc_id = crtc_id;
      selection.mode = best;
      found = true;
    }
    drmModeFreeConnector(connector);
  }
  return found;
}

void destroy_dumb(int fd, std::uint32_t handle) {
  drm_mode_destroy_dumb destroy{};
  destroy.handle = handle;
  ioctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy);
}

bool import_dma_buf_to_egl(int dma_buf_fd, std::uint32_t width,
                           std::uint32_t height, std::uint32_t pitch) {
  const auto query_devices = reinterpret_cast<PFNEGLQUERYDEVICESEXTPROC>(
      eglGetProcAddress("eglQueryDevicesEXT"));
  const auto get_platform_display =
      reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(
          eglGetProcAddress("eglGetPlatformDisplayEXT"));
  const auto create_image = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(
      eglGetProcAddress("eglCreateImageKHR"));
  const auto destroy_image = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(
      eglGetProcAddress("eglDestroyImageKHR"));
  if (query_devices == nullptr || get_platform_display == nullptr ||
      create_image == nullptr || destroy_image == nullptr) {
    std::cerr << "required EGL device/DMA-BUF entry points are unavailable\n";
    return false;
  }

  EGLDeviceEXT devices[8]{};
  EGLint device_count = 0;
  if (query_devices(8, devices, &device_count) != EGL_TRUE) {
    std::cerr << "eglQueryDevicesEXT failed, error=0x" << std::hex
              << eglGetError() << std::dec << '\n';
    return false;
  }

  for (EGLint device_index = 0; device_index < device_count; ++device_index) {
    EGLDisplay display = get_platform_display(EGL_PLATFORM_DEVICE_EXT,
                                               devices[device_index], nullptr);
    EGLint major = 0;
    EGLint minor = 0;
    if (display == EGL_NO_DISPLAY || eglInitialize(display, &major, &minor) != EGL_TRUE) {
      continue;
    }
    const char* extensions = eglQueryString(display, EGL_EXTENSIONS);
    if (extensions == nullptr ||
        std::strstr(extensions, "EGL_EXT_image_dma_buf_import") == nullptr) {
      eglTerminate(display);
      continue;
    }

    const EGLint attributes[] = {
        EGL_WIDTH,
        static_cast<EGLint>(width),
        EGL_HEIGHT,
        static_cast<EGLint>(height),
        EGL_LINUX_DRM_FOURCC_EXT,
        static_cast<EGLint>(DRM_FORMAT_XBGR2101010),
        EGL_DMA_BUF_PLANE0_FD_EXT,
        dma_buf_fd,
        EGL_DMA_BUF_PLANE0_OFFSET_EXT,
        0,
        EGL_DMA_BUF_PLANE0_PITCH_EXT,
        static_cast<EGLint>(pitch),
        EGL_NONE,
    };
    EGLImageKHR image = create_image(display, EGL_NO_CONTEXT,
                                     EGL_LINUX_DMA_BUF_EXT, nullptr, attributes);
    if (image != EGL_NO_IMAGE_KHR) {
      std::cout << "egl_dma_buf_import=pass device=" << device_index
                << " egl_version=" << major << '.' << minor << '\n';
      destroy_image(display, image);
      eglTerminate(display);
      return true;
    }
    std::cerr << "EGL device " << device_index
              << " rejected XB30 DMA-BUF, error=0x" << std::hex
              << eglGetError() << std::dec << '\n';
    eglTerminate(display);
  }

  std::cerr << "no EGL device imported the XB30 DMA-BUF\n";
  return false;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc > 2) {
    std::cerr << "usage: " << argv[0] << " [DRM_DEVICE]\n";
    return 2;
  }
  const char* device = argc == 2 ? argv[1] : "/dev/dri/card0";
  const int fd = open(device, O_RDWR | O_CLOEXEC);
  if (fd < 0) {
    std::cerr << "open failed: " << std::strerror(errno) << '\n';
    return 3;
  }
  if (drmSetMaster(fd) != 0) {
    std::cerr << "DRM master acquisition failed: " << std::strerror(errno)
              << '\n';
    close(fd);
    return 4;
  }

  drmModeRes* resources = drmModeGetResources(fd);
  Selection selection;
  if (resources == nullptr || !choose_output(fd, *resources, selection)) {
    std::cerr << "no connected output with a usable CRTC\n";
    drmModeFreeResources(resources);
    drmDropMaster(fd);
    close(fd);
    return 5;
  }

  drmModeCrtc* previous = drmModeGetCrtc(fd, selection.crtc_id);
  drm_mode_create_dumb create{};
  create.width = selection.mode.hdisplay;
  create.height = selection.mode.vdisplay;
  create.bpp = 32;
  if (ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) != 0) {
    std::cerr << "dumb-buffer creation failed: " << std::strerror(errno) << '\n';
    drmModeFreeCrtc(previous);
    drmModeFreeResources(resources);
    drmDropMaster(fd);
    close(fd);
    return 6;
  }

  drm_mode_map_dumb map_request{};
  map_request.handle = create.handle;
  if (ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &map_request) != 0) {
    std::cerr << "dumb-buffer map request failed: " << std::strerror(errno)
              << '\n';
    destroy_dumb(fd, create.handle);
    drmModeFreeCrtc(previous);
    drmModeFreeResources(resources);
    drmDropMaster(fd);
    close(fd);
    return 7;
  }

  void* mapping = mmap(nullptr, create.size, PROT_READ | PROT_WRITE, MAP_SHARED,
                       fd, map_request.offset);
  if (mapping == MAP_FAILED) {
    std::cerr << "dumb-buffer mmap failed: " << std::strerror(errno) << '\n';
    destroy_dumb(fd, create.handle);
    drmModeFreeCrtc(previous);
    drmModeFreeResources(resources);
    drmDropMaster(fd);
    close(fd);
    return 8;
  }

  for (std::uint32_t y = 0; y < create.height; ++y) {
    auto* row = reinterpret_cast<std::uint32_t*>(
        static_cast<std::uint8_t*>(mapping) + y * create.pitch);
    for (std::uint32_t x = 0; x < create.width; ++x) {
      const std::uint32_t red = x * 1023U / (create.width - 1U);
      const std::uint32_t green = y * 1023U / (create.height - 1U);
      const std::uint32_t blue = 1023U - red;
      row[x] = red | (green << 10U) | (blue << 20U);
    }
  }

  const std::uint32_t handles[4] = {create.handle, 0, 0, 0};
  const std::uint32_t pitches[4] = {create.pitch, 0, 0, 0};
  const std::uint32_t offsets[4] = {0, 0, 0, 0};
  std::uint32_t framebuffer_id = 0;
  const int add_result = drmModeAddFB2(
      fd, create.width, create.height, DRM_FORMAT_XBGR2101010, handles, pitches,
      offsets, &framebuffer_id, 0);
  if (add_result != 0) {
    std::cerr << "XB30 framebuffer creation failed: " << std::strerror(errno)
              << '\n';
    munmap(mapping, create.size);
    destroy_dumb(fd, create.handle);
    drmModeFreeCrtc(previous);
    drmModeFreeResources(resources);
    drmDropMaster(fd);
    close(fd);
    return 9;
  }

  const int modeset_result = drmModeSetCrtc(
      fd, selection.crtc_id, framebuffer_id, 0, 0, &selection.connector_id, 1,
      &selection.mode);
  int result = 0;
  if (modeset_result != 0) {
    std::cerr << "XB30 modeset failed: " << std::strerror(errno) << '\n';
    result = 10;
  } else {
    int dma_buf_fd = -1;
    const int export_result = drmPrimeHandleToFD(
        fd, create.handle, DRM_CLOEXEC | DRM_RDWR, &dma_buf_fd);
    std::cout << "connector=" << selection.connector_id
              << " crtc=" << selection.crtc_id << " mode="
              << selection.mode.hdisplay << 'x' << selection.mode.vdisplay
              << '@' << selection.mode.vrefresh << '\n';
    std::cout << "framebuffer=" << framebuffer_id << " format=XB30 pitch="
              << create.pitch << " bytes=" << create.size << '\n';
    std::cout << "dma_buf_export="
              << (export_result == 0 ? "pass" : "fail") << '\n';
    if (export_result != 0) {
      std::cerr << "DMA-BUF export failed: " << std::strerror(errno) << '\n';
      result = 11;
    } else if (!import_dma_buf_to_egl(dma_buf_fd, create.width, create.height,
                                      create.pitch)) {
      result = 12;
    }
    if (dma_buf_fd >= 0) {
      close(dma_buf_fd);
    }
    std::this_thread::sleep_for(std::chrono::seconds(2));
  }

  if (previous != nullptr && previous->mode_valid != 0) {
    drmModeSetCrtc(fd, previous->crtc_id, previous->buffer_id, previous->x,
                   previous->y, &selection.connector_id, 1, &previous->mode);
  } else {
    drmModeSetCrtc(fd, selection.crtc_id, 0, 0, 0, nullptr, 0, nullptr);
  }
  drmModeRmFB(fd, framebuffer_id);
  munmap(mapping, create.size);
  destroy_dumb(fd, create.handle);
  drmModeFreeCrtc(previous);
  drmModeFreeResources(resources);
  drmDropMaster(fd);
  close(fd);
  return result;
}
