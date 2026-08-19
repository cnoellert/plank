#include <fcntl.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <string>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <drm_fourcc.h>
#include <gbm.h>
#include <gst/allocators/gstdmabuf.h>
#include <gst/app/gstappsink.h>
#include <gst/gst.h>
#include <gst/video/gstvideometa.h>

namespace {

struct ProbeState {
  std::uint64_t expected_frames = 1;
  std::atomic<std::uint64_t> frames{0};
  std::atomic<bool> failed{false};
  std::string drm_format;
  guint width = 0;
  guint height = 0;
  guint planes = 0;
  gint stride = 0;
  gsize offset = 0;
  guint memories = 0;
  bool egl_imported = false;
  int drm_fd = -1;
  gbm_device* gbm = nullptr;
  EGLDisplay egl_display = EGL_NO_DISPLAY;
  PFNEGLCREATEIMAGEKHRPROC create_image = nullptr;
  PFNEGLDESTROYIMAGEKHRPROC destroy_image = nullptr;
};

bool initialize_egl(const char* render_node, ProbeState* state) {
  state->drm_fd = open(render_node, O_RDWR | O_CLOEXEC);
  if (state->drm_fd < 0) {
    std::cerr << "failed to open render node: " << render_node << '\n';
    return false;
  }
  state->gbm = gbm_create_device(state->drm_fd);
  if (state->gbm == nullptr) {
    std::cerr << "failed to create GBM device\n";
    return false;
  }
  state->egl_display =
      eglGetPlatformDisplay(EGL_PLATFORM_GBM_KHR, state->gbm, nullptr);
  EGLint major = 0;
  EGLint minor = 0;
  if (state->egl_display == EGL_NO_DISPLAY ||
      eglInitialize(state->egl_display, &major, &minor) != EGL_TRUE) {
    std::cerr << "failed to initialize EGL on GBM\n";
    return false;
  }
  const char* extensions = eglQueryString(state->egl_display, EGL_EXTENSIONS);
  if (extensions == nullptr ||
      std::strstr(extensions, "EGL_EXT_image_dma_buf_import") == nullptr ||
      std::strstr(extensions,
                  "EGL_EXT_image_dma_buf_import_modifiers") == nullptr) {
    std::cerr << "required EGL DMA-BUF import extensions are unavailable\n";
    return false;
  }
  state->create_image = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(
      eglGetProcAddress("eglCreateImageKHR"));
  state->destroy_image = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(
      eglGetProcAddress("eglDestroyImageKHR"));
  return state->create_image != nullptr && state->destroy_image != nullptr;
}

void shutdown_egl(ProbeState* state) {
  if (state->egl_display != EGL_NO_DISPLAY) {
    eglTerminate(state->egl_display);
    state->egl_display = EGL_NO_DISPLAY;
  }
  if (state->gbm != nullptr) {
    gbm_device_destroy(state->gbm);
    state->gbm = nullptr;
  }
  if (state->drm_fd >= 0) {
    close(state->drm_fd);
    state->drm_fd = -1;
  }
}

bool import_egl_image(ProbeState* state, int dma_buf_fd,
                      const GstVideoMeta* video_meta,
                      const char* drm_format) {
  const char* separator = std::strchr(drm_format, ':');
  if (separator == nullptr) {
    return false;
  }
  char* end = nullptr;
  const std::uint64_t modifier = std::strtoull(separator + 1, &end, 0);
  if (end == separator + 1 || *end != '\0') {
    return false;
  }
  const EGLint attributes[] = {
      EGL_WIDTH,
      static_cast<EGLint>(video_meta->width),
      EGL_HEIGHT,
      static_cast<EGLint>(video_meta->height),
      EGL_LINUX_DRM_FOURCC_EXT,
      static_cast<EGLint>(DRM_FORMAT_Y410),
      EGL_DMA_BUF_PLANE0_FD_EXT,
      dma_buf_fd,
      EGL_DMA_BUF_PLANE0_OFFSET_EXT,
      static_cast<EGLint>(video_meta->offset[0]),
      EGL_DMA_BUF_PLANE0_PITCH_EXT,
      video_meta->stride[0],
      EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
      static_cast<EGLint>(modifier & 0xffffffffU),
      EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT,
      static_cast<EGLint>(modifier >> 32U),
      EGL_NONE,
  };
  EGLImageKHR image = state->create_image(
      state->egl_display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr,
      attributes);
  if (image == EGL_NO_IMAGE_KHR) {
    std::cerr << "EGL DMA-BUF image import failed, error=0x" << std::hex
              << eglGetError() << std::dec << '\n';
    return false;
  }
  const bool destroyed =
      state->destroy_image(state->egl_display, image) == EGL_TRUE;
  return destroyed;
}

gboolean on_propose_allocation(GstAppSink*, GstQuery* query, gpointer) {
  gst_query_add_allocation_meta(query, GST_VIDEO_META_API_TYPE, nullptr);
  return TRUE;
}

GstFlowReturn on_new_sample(GstAppSink* sink, gpointer user_data) {
  auto* state = static_cast<ProbeState*>(user_data);
  GstSample* sample = gst_app_sink_pull_sample(sink);
  if (sample == nullptr) {
    state->failed = true;
    return GST_FLOW_ERROR;
  }

  GstBuffer* buffer = gst_sample_get_buffer(sample);
  GstCaps* caps = gst_sample_get_caps(sample);
  GstVideoMeta* video_meta =
      buffer == nullptr ? nullptr : gst_buffer_get_video_meta(buffer);
  const GstStructure* structure =
      caps == nullptr ? nullptr : gst_caps_get_structure(caps, 0);
  const gchar* drm_format =
      structure == nullptr ? nullptr
                           : gst_structure_get_string(structure, "drm-format");

  bool valid = buffer != nullptr && video_meta != nullptr &&
               drm_format != nullptr &&
               std::string(drm_format).rfind("Y410", 0) == 0;
  const guint memory_count =
      buffer == nullptr ? 0U : gst_buffer_n_memory(buffer);
  valid = valid && memory_count > 0;
  int first_fd = -1;
  for (guint index = 0; valid && index < memory_count; ++index) {
    GstMemory* memory = gst_buffer_peek_memory(buffer, index);
    if (!gst_is_dmabuf_memory(memory)) {
      valid = false;
      break;
    }
    const int fd = gst_dmabuf_memory_get_fd(memory);
    if (index == 0) {
      first_fd = fd;
    }
    if (fd < 0 || fcntl(fd, F_GETFD) == -1) {
      valid = false;
    }
  }

  if (state->frames.load() == 0 && valid) {
    state->egl_imported =
        import_egl_image(state, first_fd, video_meta, drm_format);
    valid = state->egl_imported;
    state->drm_format = drm_format;
    state->width = video_meta->width;
    state->height = video_meta->height;
    state->planes = video_meta->n_planes;
    state->stride = video_meta->stride[0];
    state->offset = video_meta->offset[0];
    state->memories = memory_count;
  }
  if (!valid) {
    state->failed = true;
  }
  const std::uint64_t frames = ++state->frames;
  gst_sample_unref(sample);
  if (!valid) {
    return GST_FLOW_ERROR;
  }
  return frames >= state->expected_frames ? GST_FLOW_EOS : GST_FLOW_OK;
}

bool parse_positive(const char* text, std::uint64_t* value) {
  char* end = nullptr;
  const unsigned long long parsed = std::strtoull(text, &end, 10);
  if (end == text || *end != '\0' || parsed == 0) {
    return false;
  }
  *value = parsed;
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2 || argc > 4) {
    std::cerr << "usage: " << argv[0]
              << " BITSTREAM [FRAME_COUNT] [RENDER_NODE]\n";
    return 2;
  }
  std::uint64_t expected_frames = 1;
  if (argc >= 3 && !parse_positive(argv[2], &expected_frames)) {
    std::cerr << "invalid frame count: " << argv[2] << '\n';
    return 2;
  }
  const char* render_node = argc == 4 ? argv[3] : "/dev/dri/renderD128";

  gst_init(&argc, &argv);
  const gchar* description =
      "filesrc name=input ! h265parse ! vah265dec ! "
      "video/x-raw(memory:DMABuf) ! appsink name=dmabuf_sink";

  GError* parse_error = nullptr;
  GstElement* pipeline = gst_parse_launch(description, &parse_error);
  if (pipeline == nullptr || parse_error != nullptr) {
    std::cerr << "pipeline creation failed: "
              << (parse_error == nullptr ? "unknown error"
                                         : parse_error->message)
              << '\n';
    g_clear_error(&parse_error);
    if (pipeline != nullptr) {
      gst_object_unref(pipeline);
    }
    return 3;
  }

  GstElement* source = gst_bin_get_by_name(GST_BIN(pipeline), "input");
  GstElement* sink = gst_bin_get_by_name(GST_BIN(pipeline), "dmabuf_sink");
  if (source == nullptr || sink == nullptr) {
    std::cerr << "source or appsink was not created\n";
    if (source != nullptr) {
      gst_object_unref(source);
    }
    if (sink != nullptr) {
      gst_object_unref(sink);
    }
    gst_object_unref(pipeline);
    return 3;
  }

  ProbeState state;
  state.expected_frames = expected_frames;
  if (!initialize_egl(render_node, &state)) {
    shutdown_egl(&state);
    gst_object_unref(source);
    gst_object_unref(sink);
    gst_object_unref(pipeline);
    return 4;
  }
  g_object_set(source, "location", argv[1], nullptr);
  g_object_set(sink, "emit-signals", TRUE, "sync", FALSE, "max-buffers", 4U,
               nullptr);
  gst_object_unref(source);
  g_signal_connect(sink, "propose-allocation",
                   G_CALLBACK(on_propose_allocation), &state);
  g_signal_connect(sink, "new-sample", G_CALLBACK(on_new_sample), &state);

  const auto started = std::chrono::steady_clock::now();
  const GstStateChangeReturn start_status =
      gst_element_set_state(pipeline, GST_STATE_PLAYING);
  bool reached_eos = start_status != GST_STATE_CHANGE_FAILURE;
  GstBus* bus = gst_element_get_bus(pipeline);
  GstMessage* message = gst_bus_timed_pop_filtered(
      bus, GST_CLOCK_TIME_NONE,
      static_cast<GstMessageType>(GST_MESSAGE_ERROR | GST_MESSAGE_EOS));
  if (message == nullptr || GST_MESSAGE_TYPE(message) == GST_MESSAGE_ERROR) {
    reached_eos = false;
    if (message != nullptr) {
      GError* error = nullptr;
      gchar* debug = nullptr;
      gst_message_parse_error(message, &error, &debug);
      std::cerr << "pipeline failed: " << error->message << '\n';
      if (debug != nullptr) {
        std::cerr << debug << '\n';
      }
      g_clear_error(&error);
      g_free(debug);
    }
  }

  if (message != nullptr) {
    gst_message_unref(message);
  }
  const auto finished = std::chrono::steady_clock::now();
  gst_element_set_state(pipeline, GST_STATE_NULL);
  gst_object_unref(bus);
  gst_object_unref(sink);
  gst_object_unref(pipeline);
  shutdown_egl(&state);

  const std::uint64_t frames = state.frames.load();
  const auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                              finished - started)
                              .count();
  const double frames_per_second =
      elapsed_ms == 0 ? 0.0
                      : static_cast<double>(frames) * 1000.0 /
                            static_cast<double>(elapsed_ms);
  const bool passed = reached_eos && !state.failed.load() &&
                      frames == expected_frames;
  std::cout << "dmabuf_frames=" << frames << '\n'
            << "elapsed_ms=" << elapsed_ms << '\n'
            << "dmabuf_fps=" << std::fixed << std::setprecision(2)
            << frames_per_second << '\n'
            << "drm_format=" << state.drm_format << '\n'
            << "width=" << state.width << '\n'
            << "height=" << state.height << '\n'
            << "planes=" << state.planes << '\n'
            << "stride0=" << state.stride << '\n'
            << "offset0=" << state.offset << '\n'
            << "dmabuf_memories=" << state.memories << '\n'
            << "egl_image_import="
            << (state.egl_imported ? "pass" : "fail") << '\n'
            << "cpu_map_attempted=no\n"
            << "vaapi_y410_dmabuf_gate=" << (passed ? "pass" : "fail")
            << '\n';
  return passed ? 0 : 1;
}
