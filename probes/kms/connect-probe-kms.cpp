#include <cerrno>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <set>
#include <string>
#include <unistd.h>

#include <xf86drm.h>
#include <xf86drmMode.h>
#include <drm_fourcc.h>

namespace {

std::string fourcc_name(std::uint32_t format) {
  std::string name(4, ' ');
  name[0] = static_cast<char>(format & 0xffU);
  name[1] = static_cast<char>((format >> 8U) & 0xffU);
  name[2] = static_cast<char>((format >> 16U) & 0xffU);
  name[3] = static_cast<char>((format >> 24U) & 0xffU);
  return name;
}

bool is_native_10_bit_rgb(std::uint32_t format) {
  return format == DRM_FORMAT_XRGB2101010 || format == DRM_FORMAT_ARGB2101010 ||
         format == DRM_FORMAT_XBGR2101010 || format == DRM_FORMAT_ABGR2101010;
}

const char* connection_name(drmModeConnection connection) {
  switch (connection) {
    case DRM_MODE_CONNECTED:
      return "connected";
    case DRM_MODE_DISCONNECTED:
      return "disconnected";
    default:
      return "unknown";
  }
}

std::string object_property_name(int fd, std::uint32_t object_id,
                                 std::uint32_t object_type,
                                 const char* wanted) {
  drmModeObjectProperties* properties =
      drmModeObjectGetProperties(fd, object_id, object_type);
  if (properties == nullptr) {
    return "unknown";
  }

  std::string value = "unknown";
  for (std::uint32_t i = 0; i < properties->count_props; ++i) {
    drmModePropertyRes* property = drmModeGetProperty(fd, properties->props[i]);
    if (property != nullptr && std::strcmp(property->name, wanted) == 0) {
      const std::uint64_t selected = properties->prop_values[i];
      for (int j = 0; j < property->count_enums; ++j) {
        if (property->enums[j].value == selected) {
          value = property->enums[j].name;
          break;
        }
      }
    }
    drmModeFreeProperty(property);
  }
  drmModeFreeObjectProperties(properties);
  return value;
}

void print_framebuffer(int fd, std::uint32_t framebuffer_id,
                       const std::string& indent) {
  drmModeFB2* framebuffer = drmModeGetFB2(fd, framebuffer_id);
  if (framebuffer == nullptr) {
    std::cout << indent << "framebuffer " << framebuffer_id
              << ": unavailable (" << std::strerror(errno) << ")\n";
    return;
  }

  const std::string format = fourcc_name(framebuffer->pixel_format);
  std::cout << indent << "framebuffer " << framebuffer->fb_id << ": "
            << framebuffer->width << 'x' << framebuffer->height
            << " format=" << format
            << " native_10_bit_rgb="
            << (is_native_10_bit_rgb(framebuffer->pixel_format) ? "yes" : "no")
            << " modifier=0x" << std::hex << framebuffer->modifier << std::dec
            << '\n';

  std::set<std::uint32_t> exported_handles;
  for (std::size_t plane = 0; plane < 4; ++plane) {
    const std::uint32_t handle = framebuffer->handles[plane];
    if (handle == 0 || !exported_handles.insert(handle).second) {
      continue;
    }
    int dma_buf_fd = -1;
    errno = 0;
    const int result =
        drmPrimeHandleToFD(fd, handle, DRM_CLOEXEC | DRM_RDWR, &dma_buf_fd);
    std::cout << indent << "  dma_buf_export plane=" << plane
              << " result=" << (result == 0 ? "pass" : "fail");
    if (result != 0) {
      std::cout << " error=\"" << std::strerror(errno) << '\"';
    }
    std::cout << '\n';
    if (dma_buf_fd >= 0) {
      close(dma_buf_fd);
    }
  }
  drmModeFreeFB2(framebuffer);
}

int self_test() {
  bool passed = true;
  passed = passed && fourcc_name(DRM_FORMAT_XRGB2101010) == "XR30";
  passed = passed && fourcc_name(DRM_FORMAT_ARGB2101010) == "AR30";
  passed = passed && is_native_10_bit_rgb(DRM_FORMAT_XRGB2101010);
  passed = passed && !is_native_10_bit_rgb(DRM_FORMAT_XRGB8888);
  std::cout << "kms-probe-self-test: " << (passed ? "pass" : "fail") << '\n';
  return passed ? 0 : 1;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc == 2 && std::string(argv[1]) == "--self-test") {
    return self_test();
  }
  bool inventory_only = false;
  const char* device = "/dev/dri/card0";
  for (int index = 1; index < argc; ++index) {
    if (std::string(argv[index]) == "--inventory-only") {
      inventory_only = true;
    } else if (device == std::string("/dev/dri/card0")) {
      device = argv[index];
    } else {
      std::cerr << "usage: " << argv[0]
                << " [DRM_DEVICE] [--inventory-only|--self-test]\n";
      return 2;
    }
  }
  if (argc > 3) {
    std::cerr << "usage: " << argv[0]
              << " [DRM_DEVICE] [--inventory-only|--self-test]\n";
    return 2;
  }
  const int fd = open(device, O_RDWR | O_CLOEXEC);
  if (fd < 0) {
    std::cerr << "KMS probe failed to open " << device << ": "
              << std::strerror(errno)
              << ". The probe needs access to the DRM primary node.\n";
    return 3;
  }

  drmVersion* version = drmGetVersion(fd);
  std::cout << "device: " << device << '\n';
  if (version != nullptr) {
    std::cout << "driver: " << std::string(version->name, version->name_len)
              << " version=" << version->version_major << '.'
              << version->version_minor << '.' << version->version_patchlevel
              << '\n';
    drmFreeVersion(version);
  }

  errno = 0;
  const int universal = drmSetClientCap(fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1);
  std::cout << "universal_planes: " << (universal == 0 ? "enabled" : "failed")
            << (universal == 0 ? "" : std::string(" (") + std::strerror(errno) + ")")
            << '\n';
  errno = 0;
  const int atomic = drmSetClientCap(fd, DRM_CLIENT_CAP_ATOMIC, 1);
  std::cout << "atomic_modesetting: " << (atomic == 0 ? "enabled" : "failed")
            << (atomic == 0 ? "" : std::string(" (") + std::strerror(errno) + ")")
            << '\n';

  drmModeRes* resources = drmModeGetResources(fd);
  if (resources == nullptr) {
    std::cerr << "drmModeGetResources failed: " << std::strerror(errno) << '\n';
    close(fd);
    return 4;
  }

  std::cout << "connectors: " << resources->count_connectors << '\n';
  for (int i = 0; i < resources->count_connectors; ++i) {
    drmModeConnector* connector =
        drmModeGetConnector(fd, resources->connectors[i]);
    if (connector == nullptr) {
      continue;
    }
    std::cout << "  connector " << connector->connector_id
              << ": status=" << connection_name(connector->connection)
              << " modes=" << connector->count_modes
              << " encoder=" << connector->encoder_id << '\n';
    drmModeFreeConnector(connector);
  }

  std::set<std::uint32_t> active_framebuffers;
  std::cout << "crtcs: " << resources->count_crtcs << '\n';
  for (int i = 0; i < resources->count_crtcs; ++i) {
    drmModeCrtc* crtc = drmModeGetCrtc(fd, resources->crtcs[i]);
    if (crtc == nullptr) {
      continue;
    }
    std::cout << "  crtc " << crtc->crtc_id << ": active="
              << (crtc->mode_valid ? "yes" : "no")
              << " framebuffer=" << crtc->buffer_id;
    if (crtc->mode_valid) {
      std::cout << " mode=" << crtc->mode.hdisplay << 'x' << crtc->mode.vdisplay
                << "@" << crtc->mode.vrefresh;
    }
    std::cout << '\n';
    if (crtc->buffer_id != 0) {
      active_framebuffers.insert(crtc->buffer_id);
      print_framebuffer(fd, crtc->buffer_id, "    ");
    }
    drmModeFreeCrtc(crtc);
  }

  drmModePlaneRes* planes = drmModeGetPlaneResources(fd);
  if (planes == nullptr) {
    std::cout << "planes: unavailable (" << std::strerror(errno) << ")\n";
  } else {
    std::cout << "planes: " << planes->count_planes << '\n';
    for (std::uint32_t i = 0; i < planes->count_planes; ++i) {
      drmModePlane* plane = drmModeGetPlane(fd, planes->planes[i]);
      if (plane == nullptr) {
        continue;
      }
      std::cout << "  plane " << plane->plane_id
                << ": type="
                << object_property_name(fd, plane->plane_id,
                                        DRM_MODE_OBJECT_PLANE, "type")
                << " crtc=" << plane->crtc_id
                << " framebuffer=" << plane->fb_id
                << " formats=" << plane->count_formats << '\n';
      std::cout << "    native_10_bit_formats=";
      bool has_native_10_bit_format = false;
      for (std::uint32_t format = 0; format < plane->count_formats; ++format) {
        if (!is_native_10_bit_rgb(plane->formats[format])) {
          continue;
        }
        std::cout << (has_native_10_bit_format ? "," : "")
                  << fourcc_name(plane->formats[format]);
        has_native_10_bit_format = true;
      }
      if (!has_native_10_bit_format) {
        std::cout << "none";
      }
      std::cout << '\n';
      if (plane->fb_id != 0) {
        active_framebuffers.insert(plane->fb_id);
        print_framebuffer(fd, plane->fb_id, "    ");
      }
      drmModeFreePlane(plane);
    }
    drmModeFreePlaneResources(planes);
  }

  std::cout << "active_scanout_framebuffers: " << active_framebuffers.size()
            << '\n';
  drmModeFreeResources(resources);
  close(fd);
  if (active_framebuffers.empty()) {
    std::cout << "public_kms_scanout=unavailable\n";
    if (!inventory_only) {
      std::cerr << "KMS capture gate failed: the DRM API exposes no active "
                   "scanout framebuffer.\n";
      return 5;
    }
  }
  return 0;
}
