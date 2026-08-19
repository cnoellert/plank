#include <algorithm>
#include <atomic>
#include <chrono>
#include <cerrno>
#include <condition_variable>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <string>
#include <time.h>
#include <thread>
#include <vector>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#define GL_GLEXT_PROTOTYPES
#include <GLES3/gl32.h>
#include <GLES2/gl2ext.h>
#include <drm_fourcc.h>
#include <gst/allocators/gstdmabuf.h>
#include <gst/app/gstappsink.h>
#include <gst/gst.h>
#include <gst/video/gstvideometa.h>
#include <wayland-client.h>
#include <wayland-egl.h>

#include "presentation-time-client-protocol.h"
#include "xdg-shell-client-protocol.h"
#ifdef CONNECT_HAVE_COMMIT_TIMING
#include "commit-timing-v1-client-protocol.h"
#endif
#ifdef CONNECT_HAVE_FIFO
#include "fifo-v1-client-protocol.h"
#endif

namespace {

struct SubmitStamp {
  std::uint64_t frame = 0;
  std::uint64_t time_ns = 0;
  std::uint64_t target_present_ns = 0;
};

struct Feedback {
  bool done = false;
  bool presented = false;
  std::uint64_t time_ns = 0;
  std::uint32_t refresh_ns = 0;
  std::uint32_t flags = 0;
};

struct State {
  std::uint64_t expected_frames = 0;
  std::atomic<std::uint64_t> submitted{0};
  std::atomic<std::uint64_t> queued{0};
  std::atomic<std::uint64_t> presented{0};
  std::atomic<bool> failed{false};
  std::mutex submit_mutex;
  std::deque<SubmitStamp> submit_queue;
  std::size_t max_submit_depth = 0;
  bool threaded = false;
  bool async_feedback = false;
  bool fifo_enabled = false;
  std::mutex ready_mutex;
  std::condition_variable ready_available;
  std::condition_variable ready_consumed;
  GstSample* ready_sample = nullptr;
  SubmitStamp ready_submit;
  std::uint64_t ready_surface_ns = 0;
  bool producer_done = false;
  bool worker_stop = false;
  std::size_t max_ready_depth = 0;
  std::uint64_t async_inflight = 0;
  std::uint64_t max_async_inflight = 0;
  std::uint64_t async_inflight_limit = 1;
  std::uint64_t stale_frames_dropped = 0;
  std::vector<double> decode_ms;
  std::vector<double> surface_to_swap_ms;
  std::vector<double> swap_submit_ms;
  std::vector<double> surface_to_present_ms;
  std::vector<double> submit_to_present_ms;
  std::vector<double> presentation_interval_ms;
  std::vector<double> input_schedule_late_ms;
  std::vector<double> surface_vs_target_ms;
  std::vector<double> swap_vs_target_ms;
  std::vector<double> presentation_vs_target_ms;
  std::vector<double> stale_drop_late_ms;
  std::uint64_t vsync_frames = 0;
  std::uint64_t hw_clock_frames = 0;
  std::uint64_t hw_completion_frames = 0;
  std::uint64_t zero_copy_frames = 0;
  std::uint64_t first_presentation_ns = 0;
  std::uint64_t last_presentation_ns = 0;
  std::string drm_format;
  guint width = 0;
  guint height = 0;
  wl_display* wl_display_handle = nullptr;
  wl_compositor* compositor = nullptr;
  xdg_wm_base* wm_base = nullptr;
  wp_presentation* presentation = nullptr;
#ifdef CONNECT_HAVE_COMMIT_TIMING
  wp_commit_timing_manager_v1* commit_timing_manager = nullptr;
  wp_commit_timer_v1* commit_timer = nullptr;
#endif
#ifdef CONNECT_HAVE_FIFO
  wp_fifo_manager_v1* fifo_manager = nullptr;
  wp_fifo_v1* fifo = nullptr;
#endif
  std::uint64_t commit_timing_frames = 0;
  bool commit_timing_available = false;
  std::uint64_t fifo_frames = 0;
  bool fifo_available = false;
  wl_surface* wl_surface_handle = nullptr;
  xdg_surface* xdg_surface_handle = nullptr;
  xdg_toplevel* toplevel = nullptr;
  wl_egl_window* window = nullptr;
  bool configured = false;
  int surface_width = 3840;
  int surface_height = 2160;
  clockid_t presentation_clock = CLOCK_MONOTONIC;
  bool clock_received = false;
  std::uint64_t first_target_present_ns = 0;
  std::uint64_t refresh_ns = 16666667;
  std::uint64_t submit_lead_ns = 0;
  EGLDisplay egl_display = EGL_NO_DISPLAY;
  EGLSurface egl_surface = EGL_NO_SURFACE;
  EGLContext egl_context = EGL_NO_CONTEXT;
  EGLConfig egl_config = nullptr;
  EGLint native_visual = 0;
  GLuint program = 0;
  GLuint vertex_array = 0;
  PFNEGLCREATEIMAGEKHRPROC create_image = nullptr;
  PFNEGLDESTROYIMAGEKHRPROC destroy_image = nullptr;
  PFNGLEGLIMAGETARGETTEXTURE2DOESPROC image_target_texture = nullptr;
};

struct AsyncFeedback {
  State* state = nullptr;
  SubmitStamp submit;
  std::uint64_t surface_ready_ns = 0;
  std::uint64_t render_started_ns = 0;
  std::uint64_t swap_submitted_ns = 0;
};

std::uint64_t clock_ns(clockid_t id) {
  timespec now{};
  if (clock_gettime(id, &now) != 0) return 0;
  return static_cast<std::uint64_t>(now.tv_sec) * 1000000000ULL +
         static_cast<std::uint64_t>(now.tv_nsec);
}

bool has_extension(const char* extensions, const char* name) {
  if (extensions == nullptr || name == nullptr || *name == '\0' ||
      std::strchr(name, ' ') != nullptr) {
    return false;
  }
  const std::size_t length = std::strlen(name);
  for (const char* match = std::strstr(extensions, name); match != nullptr;
       match = std::strstr(match + length, name)) {
    if ((match == extensions || match[-1] == ' ') &&
        (match[length] == '\0' || match[length] == ' ')) {
      return true;
    }
  }
  return false;
}

void on_registry_global(void* data, wl_registry* registry, std::uint32_t name,
                        const char* interface, std::uint32_t version) {
  auto* state = static_cast<State*>(data);
  if (std::strcmp(interface, wl_compositor_interface.name) == 0) {
    state->compositor = static_cast<wl_compositor*>(wl_registry_bind(
        registry, name, &wl_compositor_interface, std::min(version, 4U)));
  } else if (std::strcmp(interface, xdg_wm_base_interface.name) == 0) {
    state->wm_base = static_cast<xdg_wm_base*>(
        wl_registry_bind(registry, name, &xdg_wm_base_interface, 1));
  } else if (std::strcmp(interface, wp_presentation_interface.name) == 0) {
    state->presentation = static_cast<wp_presentation*>(wl_registry_bind(
        registry, name, &wp_presentation_interface, std::min(version, 2U)));
#ifdef CONNECT_HAVE_COMMIT_TIMING
  } else if (std::strcmp(interface,
                         wp_commit_timing_manager_v1_interface.name) == 0) {
    state->commit_timing_available = true;
    state->commit_timing_manager =
        static_cast<wp_commit_timing_manager_v1*>(wl_registry_bind(
            registry, name, &wp_commit_timing_manager_v1_interface, 1));
#endif
#ifdef CONNECT_HAVE_FIFO
  } else if (std::strcmp(interface, wp_fifo_manager_v1_interface.name) == 0) {
    state->fifo_available = true;
    state->fifo_manager = static_cast<wp_fifo_manager_v1*>(wl_registry_bind(
        registry, name, &wp_fifo_manager_v1_interface, 1));
#endif
  }
}

void on_registry_remove(void*, wl_registry*, std::uint32_t) {}
const wl_registry_listener kRegistryListener = {on_registry_global,
                                                 on_registry_remove};

void on_ping(void*, xdg_wm_base* wm_base, std::uint32_t serial) {
  xdg_wm_base_pong(wm_base, serial);
}
const xdg_wm_base_listener kWmBaseListener = {on_ping};

void on_surface_configure(void* data, xdg_surface* surface,
                          std::uint32_t serial) {
  auto* state = static_cast<State*>(data);
  xdg_surface_ack_configure(surface, serial);
  state->configured = true;
}
const xdg_surface_listener kSurfaceListener = {on_surface_configure};

void on_toplevel_configure(void* data, xdg_toplevel*, std::int32_t width,
                           std::int32_t height, wl_array*) {
  auto* state = static_cast<State*>(data);
  if (width > 0 && height > 0) {
    state->surface_width = width;
    state->surface_height = height;
    if (state->window != nullptr) {
      wl_egl_window_resize(state->window, width, height, 0, 0);
    }
  }
}
void on_toplevel_close(void*, xdg_toplevel*) {}
void on_toplevel_bounds(void*, xdg_toplevel*, std::int32_t, std::int32_t) {}
void on_toplevel_capabilities(void*, xdg_toplevel*, wl_array*) {}
const xdg_toplevel_listener kToplevelListener = {
    on_toplevel_configure, on_toplevel_close, on_toplevel_bounds,
    on_toplevel_capabilities};

void on_clock_id(void* data, wp_presentation*, std::uint32_t clock_id) {
  auto* state = static_cast<State*>(data);
  state->presentation_clock = static_cast<clockid_t>(clock_id);
  state->clock_received = true;
}
const wp_presentation_listener kPresentationListener = {on_clock_id};

bool record_presentation(State* state, const SubmitStamp& submit,
                         std::uint64_t surface_ready_ns,
                         std::uint64_t render_started_ns,
                         std::uint64_t swap_submitted_ns,
                         std::uint64_t presented_ns, std::uint32_t flags) {
  if (presented_ns < submit.time_ns || presented_ns < surface_ready_ns) {
    return false;
  }
  state->decode_ms.push_back(
      static_cast<double>(surface_ready_ns - submit.time_ns) / 1000000.0);
  state->surface_to_swap_ms.push_back(
      static_cast<double>(swap_submitted_ns - surface_ready_ns) / 1000000.0);
  state->swap_submit_ms.push_back(
      static_cast<double>(swap_submitted_ns - render_started_ns) / 1000000.0);
  state->surface_to_present_ms.push_back(
      static_cast<double>(presented_ns - surface_ready_ns) / 1000000.0);
  state->submit_to_present_ms.push_back(
      static_cast<double>(presented_ns - submit.time_ns) / 1000000.0);
  if (submit.target_present_ns != 0) {
    state->surface_vs_target_ms.push_back(
        static_cast<double>(static_cast<std::int64_t>(surface_ready_ns) -
                            static_cast<std::int64_t>(
                                submit.target_present_ns)) /
        1000000.0);
    state->swap_vs_target_ms.push_back(
        static_cast<double>(static_cast<std::int64_t>(swap_submitted_ns) -
                            static_cast<std::int64_t>(
                                submit.target_present_ns)) /
        1000000.0);
    state->presentation_vs_target_ms.push_back(
        static_cast<double>(static_cast<std::int64_t>(presented_ns) -
                            static_cast<std::int64_t>(
                                submit.target_present_ns)) /
        1000000.0);
  }
  if (state->last_presentation_ns != 0) {
    state->presentation_interval_ms.push_back(
        static_cast<double>(presented_ns - state->last_presentation_ns) /
        1000000.0);
  } else {
    state->first_presentation_ns = presented_ns;
  }
  state->last_presentation_ns = presented_ns;
  state->vsync_frames +=
      (flags & WP_PRESENTATION_FEEDBACK_KIND_VSYNC) != 0U;
  state->hw_clock_frames +=
      (flags & WP_PRESENTATION_FEEDBACK_KIND_HW_CLOCK) != 0U;
  state->hw_completion_frames +=
      (flags & WP_PRESENTATION_FEEDBACK_KIND_HW_COMPLETION) != 0U;
  state->zero_copy_frames +=
      (flags & WP_PRESENTATION_FEEDBACK_KIND_ZERO_COPY) != 0U;
  return true;
}

void on_sync_output(void*, struct wp_presentation_feedback*, wl_output*) {}
void on_presented(void* data, struct wp_presentation_feedback*,
                  std::uint32_t sec_hi,
                  std::uint32_t sec_lo, std::uint32_t nsec,
                  std::uint32_t refresh, std::uint32_t, std::uint32_t,
                  std::uint32_t flags) {
  auto* feedback = static_cast<Feedback*>(data);
  feedback->time_ns =
      ((static_cast<std::uint64_t>(sec_hi) << 32U) | sec_lo) *
          1000000000ULL +
      nsec;
  feedback->refresh_ns = refresh;
  feedback->flags = flags;
  feedback->presented = true;
  feedback->done = true;
}
void on_discarded(void* data, struct wp_presentation_feedback*) {
  static_cast<Feedback*>(data)->done = true;
}
const wp_presentation_feedback_listener kFeedbackListener = {
    on_sync_output, on_presented, on_discarded};

void on_async_sync_output(void*, struct wp_presentation_feedback*, wl_output*) {}
void on_async_presented(void* data, struct wp_presentation_feedback*,
                        std::uint32_t sec_hi, std::uint32_t sec_lo,
                        std::uint32_t nsec, std::uint32_t, std::uint32_t,
                        std::uint32_t, std::uint32_t flags) {
  auto* feedback = static_cast<AsyncFeedback*>(data);
  const std::uint64_t presented_ns =
      ((static_cast<std::uint64_t>(sec_hi) << 32U) | sec_lo) *
          1000000000ULL +
      nsec;
  if (!record_presentation(
          feedback->state, feedback->submit, feedback->surface_ready_ns,
          feedback->render_started_ns, feedback->swap_submitted_ns,
          presented_ns, flags)) {
    feedback->state->failed = true;
  }
  ++feedback->state->presented;
  --feedback->state->async_inflight;
  delete feedback;
}
void on_async_discarded(void* data, struct wp_presentation_feedback*) {
  auto* feedback = static_cast<AsyncFeedback*>(data);
  feedback->state->failed = true;
  --feedback->state->async_inflight;
  delete feedback;
}
const wp_presentation_feedback_listener kAsyncFeedbackListener = {
    on_async_sync_output, on_async_presented, on_async_discarded};

GLuint compile_shader(GLenum type, const char* source) {
  const GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, nullptr);
  glCompileShader(shader);
  GLint compiled = GL_FALSE;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
  if (compiled != GL_TRUE) {
    char log[2048]{};
    glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
    std::cerr << "shader compilation failed: " << log << '\n';
    glDeleteShader(shader);
    return 0;
  }
  return shader;
}

bool establish_presentation_phase(State* state) {
  Feedback feedback;
  for (unsigned int frame = 0; frame < 8; ++frame) {
    feedback = {};
    const float value = static_cast<float>(frame) / 7.0F;
    glViewport(0, 0, state->surface_width, state->surface_height);
    glClearColor(value, 0.0F, 1.0F - value, 1.0F);
    glClear(GL_COLOR_BUFFER_BIT);
    struct wp_presentation_feedback* feedback_handle =
        wp_presentation_feedback(state->presentation,
                                 state->wl_surface_handle);
    wp_presentation_feedback_add_listener(feedback_handle, &kFeedbackListener,
                                          &feedback);
    if (eglSwapBuffers(state->egl_display, state->egl_surface) != EGL_TRUE) {
      return false;
    }
    while (!feedback.done &&
           wl_display_dispatch(state->wl_display_handle) >= 0) {}
    if (!feedback.presented || feedback.refresh_ns == 0) return false;
  }
  state->refresh_ns = feedback.refresh_ns;
  state->first_target_present_ns =
      feedback.time_ns + 120ULL * state->refresh_ns;
  return true;
}

bool initialize_graphics(State* state) {
  state->wl_display_handle = wl_display_connect(nullptr);
  if (state->wl_display_handle == nullptr) return false;
  wl_registry* registry = wl_display_get_registry(state->wl_display_handle);
  wl_registry_add_listener(registry, &kRegistryListener, state);
  wl_display_roundtrip(state->wl_display_handle);
  wl_registry_destroy(registry);
  if (state->compositor == nullptr || state->wm_base == nullptr ||
      state->presentation == nullptr) {
    std::cerr << "required Wayland globals are unavailable\n";
    return false;
  }
  xdg_wm_base_add_listener(state->wm_base, &kWmBaseListener, state);
  wp_presentation_add_listener(state->presentation, &kPresentationListener,
                               state);
  wl_display_roundtrip(state->wl_display_handle);
  if (!state->clock_received || clock_ns(state->presentation_clock) == 0) {
    std::cerr << "presentation clock is unavailable\n";
    return false;
  }

  state->wl_surface_handle = wl_compositor_create_surface(state->compositor);
#ifdef CONNECT_HAVE_COMMIT_TIMING
  if (state->commit_timing_manager != nullptr) {
    state->commit_timer = wp_commit_timing_manager_v1_get_timer(
        state->commit_timing_manager, state->wl_surface_handle);
  }
#endif
#ifdef CONNECT_HAVE_FIFO
  if (state->fifo_manager != nullptr) {
    state->fifo = wp_fifo_manager_v1_get_fifo(state->fifo_manager,
                                               state->wl_surface_handle);
  }
#endif
  state->xdg_surface_handle =
      xdg_wm_base_get_xdg_surface(state->wm_base, state->wl_surface_handle);
  xdg_surface_add_listener(state->xdg_surface_handle, &kSurfaceListener, state);
  state->toplevel = xdg_surface_get_toplevel(state->xdg_surface_handle);
  xdg_toplevel_add_listener(state->toplevel, &kToplevelListener, state);
  xdg_toplevel_set_title(state->toplevel, "StationConnect client pipeline");
  xdg_toplevel_set_fullscreen(state->toplevel, nullptr);
  wl_surface_commit(state->wl_surface_handle);
  while (!state->configured &&
         wl_display_dispatch(state->wl_display_handle) >= 0) {}

  state->egl_display = eglGetPlatformDisplay(
      EGL_PLATFORM_WAYLAND_KHR, state->wl_display_handle, nullptr);
  EGLint major = 0;
  EGLint minor = 0;
  if (state->egl_display == EGL_NO_DISPLAY ||
      eglInitialize(state->egl_display, &major, &minor) != EGL_TRUE ||
      eglBindAPI(EGL_OPENGL_ES_API) != EGL_TRUE) {
    return false;
  }
  const char* egl_extensions =
      eglQueryString(state->egl_display, EGL_EXTENSIONS);
  if (!has_extension(egl_extensions, "EGL_EXT_image_dma_buf_import") ||
      !has_extension(egl_extensions,
                     "EGL_EXT_image_dma_buf_import_modifiers")) {
    return false;
  }
  const EGLint config_attributes[] = {
      EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
      EGL_RED_SIZE, 10, EGL_GREEN_SIZE, 10, EGL_BLUE_SIZE, 10, EGL_ALPHA_SIZE, 2,
      EGL_NONE};
  EGLint config_count = 0;
  if (eglChooseConfig(state->egl_display, config_attributes, &state->egl_config,
                      1, &config_count) != EGL_TRUE ||
      config_count != 1) {
    return false;
  }
  EGLint red = 0;
  EGLint green = 0;
  EGLint blue = 0;
  eglGetConfigAttrib(state->egl_display, state->egl_config,
                     EGL_NATIVE_VISUAL_ID, &state->native_visual);
  eglGetConfigAttrib(state->egl_display, state->egl_config, EGL_RED_SIZE, &red);
  eglGetConfigAttrib(state->egl_display, state->egl_config, EGL_GREEN_SIZE,
                     &green);
  eglGetConfigAttrib(state->egl_display, state->egl_config, EGL_BLUE_SIZE,
                     &blue);
  const bool visual_is_10_bit =
      state->native_visual == static_cast<EGLint>(DRM_FORMAT_ARGB2101010) ||
      state->native_visual == static_cast<EGLint>(DRM_FORMAT_ABGR2101010) ||
      state->native_visual == static_cast<EGLint>(DRM_FORMAT_XRGB2101010) ||
      state->native_visual == static_cast<EGLint>(DRM_FORMAT_XBGR2101010);
  if (red != 10 || green != 10 || blue != 10 || !visual_is_10_bit) return false;

  state->window = wl_egl_window_create(state->wl_surface_handle,
                                       state->surface_width,
                                       state->surface_height);
  state->egl_surface = eglCreateWindowSurface(
      state->egl_display, state->egl_config,
      reinterpret_cast<EGLNativeWindowType>(state->window), nullptr);
  const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  state->egl_context =
      eglCreateContext(state->egl_display, state->egl_config, EGL_NO_CONTEXT,
                       context_attributes);
  if (state->window == nullptr || state->egl_surface == EGL_NO_SURFACE ||
      state->egl_context == EGL_NO_CONTEXT ||
      eglMakeCurrent(state->egl_display, state->egl_surface, state->egl_surface,
                     state->egl_context) != EGL_TRUE) {
    return false;
  }
  const char* gl_extensions =
      reinterpret_cast<const char*>(glGetString(GL_EXTENSIONS));
  if (!has_extension(gl_extensions, "GL_OES_EGL_image_external_essl3")) {
    return false;
  }
  state->create_image = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(
      eglGetProcAddress("eglCreateImageKHR"));
  state->destroy_image = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(
      eglGetProcAddress("eglDestroyImageKHR"));
  state->image_target_texture =
      reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(
          eglGetProcAddress("glEGLImageTargetTexture2DOES"));
  if (state->create_image == nullptr || state->destroy_image == nullptr ||
      state->image_target_texture == nullptr) {
    return false;
  }

  const char* vertex_source = R"glsl(#version 300 es
out vec2 texture_coordinate;
void main() {
  if (gl_VertexID == 0) {
    gl_Position = vec4(-1.0, -1.0, 0.0, 1.0);
    texture_coordinate = vec2(0.0, 1.0);
  } else if (gl_VertexID == 1) {
    gl_Position = vec4(3.0, -1.0, 0.0, 1.0);
    texture_coordinate = vec2(2.0, 1.0);
  } else {
    gl_Position = vec4(-1.0, 3.0, 0.0, 1.0);
    texture_coordinate = vec2(0.0, -1.0);
  }
}
)glsl";
  const char* fragment_source = R"glsl(#version 300 es
#extension GL_OES_EGL_image_external_essl3 : require
precision highp float;
uniform samplerExternalOES source_texture;
in vec2 texture_coordinate;
out vec4 fragment_color;
void main() {
  fragment_color = texture(source_texture, texture_coordinate);
}
)glsl";
  const GLuint vertex = compile_shader(GL_VERTEX_SHADER, vertex_source);
  const GLuint fragment = compile_shader(GL_FRAGMENT_SHADER, fragment_source);
  if (vertex == 0 || fragment == 0) return false;
  state->program = glCreateProgram();
  glAttachShader(state->program, vertex);
  glAttachShader(state->program, fragment);
  glLinkProgram(state->program);
  glDeleteShader(vertex);
  glDeleteShader(fragment);
  GLint linked = GL_FALSE;
  glGetProgramiv(state->program, GL_LINK_STATUS, &linked);
  if (linked != GL_TRUE) return false;
  glGenVertexArrays(1, &state->vertex_array);
  eglSwapInterval(state->egl_display, 0);
  if (!establish_presentation_phase(state)) return false;
  return eglMakeCurrent(state->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                        EGL_NO_CONTEXT) == EGL_TRUE;
}

void shutdown_graphics(State* state) {
  if (state->egl_display != EGL_NO_DISPLAY) {
    eglMakeCurrent(state->egl_display, state->egl_surface, state->egl_surface,
                   state->egl_context);
    if (state->vertex_array != 0) glDeleteVertexArrays(1, &state->vertex_array);
    if (state->program != 0) glDeleteProgram(state->program);
    eglMakeCurrent(state->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                   EGL_NO_CONTEXT);
    if (state->egl_context != EGL_NO_CONTEXT)
      eglDestroyContext(state->egl_display, state->egl_context);
    if (state->egl_surface != EGL_NO_SURFACE)
      eglDestroySurface(state->egl_display, state->egl_surface);
    eglTerminate(state->egl_display);
  }
  if (state->window != nullptr) wl_egl_window_destroy(state->window);
  if (state->toplevel != nullptr) xdg_toplevel_destroy(state->toplevel);
  if (state->xdg_surface_handle != nullptr)
    xdg_surface_destroy(state->xdg_surface_handle);
#ifdef CONNECT_HAVE_COMMIT_TIMING
  if (state->commit_timer != nullptr)
    wp_commit_timer_v1_destroy(state->commit_timer);
#endif
#ifdef CONNECT_HAVE_FIFO
  if (state->fifo != nullptr) wp_fifo_v1_destroy(state->fifo);
#endif
  if (state->wl_surface_handle != nullptr)
    wl_surface_destroy(state->wl_surface_handle);
  if (state->presentation != nullptr)
    wp_presentation_destroy(state->presentation);
#ifdef CONNECT_HAVE_COMMIT_TIMING
  if (state->commit_timing_manager != nullptr)
    wp_commit_timing_manager_v1_destroy(state->commit_timing_manager);
#endif
#ifdef CONNECT_HAVE_FIFO
  if (state->fifo_manager != nullptr)
    wp_fifo_manager_v1_destroy(state->fifo_manager);
#endif
  if (state->wm_base != nullptr) xdg_wm_base_destroy(state->wm_base);
  if (state->compositor != nullptr) wl_compositor_destroy(state->compositor);
  if (state->wl_display_handle != nullptr)
    wl_display_disconnect(state->wl_display_handle);
}

bool import_and_present(State* state, int fd, const GstVideoMeta* meta,
                        const char* drm_format, const SubmitStamp& submit,
                        std::uint64_t surface_ready_ns) {
  const char* separator = std::strchr(drm_format, ':');
  if (separator == nullptr) return false;
  char* end = nullptr;
  const std::uint64_t modifier = std::strtoull(separator + 1, &end, 0);
  if (end == separator + 1 || *end != '\0') return false;
  const EGLint attributes[] = {
      EGL_WIDTH, static_cast<EGLint>(meta->width),
      EGL_HEIGHT, static_cast<EGLint>(meta->height),
      EGL_LINUX_DRM_FOURCC_EXT, static_cast<EGLint>(DRM_FORMAT_XRGB2101010),
      EGL_DMA_BUF_PLANE0_FD_EXT, fd,
      EGL_DMA_BUF_PLANE0_OFFSET_EXT, static_cast<EGLint>(meta->offset[0]),
      EGL_DMA_BUF_PLANE0_PITCH_EXT, meta->stride[0],
      EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
      static_cast<EGLint>(modifier & 0xffffffffU),
      EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT,
      static_cast<EGLint>(modifier >> 32U), EGL_NONE};
  EGLImageKHR image = state->create_image(
      state->egl_display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr,
      attributes);
  if (image == EGL_NO_IMAGE_KHR ||
      eglMakeCurrent(state->egl_display, state->egl_surface,
                     state->egl_surface, state->egl_context) != EGL_TRUE) {
    return false;
  }

  GLuint texture = 0;
  glGenTextures(1, &texture);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_EXTERNAL_OES, texture);
  glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  state->image_target_texture(GL_TEXTURE_EXTERNAL_OES,
                              reinterpret_cast<GLeglImageOES>(image));
  glViewport(0, 0, state->surface_width, state->surface_height);
  glDisable(GL_DITHER);
  glUseProgram(state->program);
  glUniform1i(glGetUniformLocation(state->program, "source_texture"), 0);
  glBindVertexArray(state->vertex_array);
  glDrawArrays(GL_TRIANGLES, 0, 3);
  if (glGetError() != GL_NO_ERROR) return false;

#ifdef CONNECT_HAVE_COMMIT_TIMING
  if (submit.target_present_ns != 0 && state->commit_timer != nullptr) {
    const std::uint64_t seconds = submit.target_present_ns / 1000000000ULL;
    wp_commit_timer_v1_set_timestamp(
        state->commit_timer, static_cast<std::uint32_t>(seconds >> 32U),
        static_cast<std::uint32_t>(seconds),
        static_cast<std::uint32_t>(submit.target_present_ns % 1000000000ULL));
    ++state->commit_timing_frames;
  }
#endif
#ifdef CONNECT_HAVE_FIFO
  if (state->fifo_enabled && state->fifo != nullptr) {
    wp_fifo_v1_set_barrier(state->fifo);
    wp_fifo_v1_wait_barrier(state->fifo);
    ++state->fifo_frames;
  }
#endif
  Feedback feedback;
  AsyncFeedback* async_feedback = nullptr;
  const std::uint64_t render_started_ns = clock_ns(state->presentation_clock);
  struct wp_presentation_feedback* feedback_handle =
      wp_presentation_feedback(state->presentation, state->wl_surface_handle);
  if (state->async_feedback) {
    async_feedback = new AsyncFeedback{state, submit, surface_ready_ns,
                                       render_started_ns, 0};
    wp_presentation_feedback_add_listener(
        feedback_handle, &kAsyncFeedbackListener, async_feedback);
  } else {
    wp_presentation_feedback_add_listener(feedback_handle, &kFeedbackListener,
                                          &feedback);
  }
  if (eglSwapBuffers(state->egl_display, state->egl_surface) != EGL_TRUE) {
    wl_proxy_destroy(reinterpret_cast<wl_proxy*>(feedback_handle));
    delete async_feedback;
    return false;
  }
  const std::uint64_t swap_submitted_ns = clock_ns(state->presentation_clock);

  glDeleteTextures(1, &texture);
  state->destroy_image(state->egl_display, image);
  eglMakeCurrent(state->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                 EGL_NO_CONTEXT);
  if (state->async_feedback) {
    async_feedback->swap_submitted_ns = swap_submitted_ns;
    ++state->async_inflight;
    state->max_async_inflight =
        std::max(state->max_async_inflight, state->async_inflight);
    if (wl_display_roundtrip(state->wl_display_handle) < 0) return false;
    return !state->failed.load();
  }
  while (!feedback.done &&
         wl_display_dispatch(state->wl_display_handle) >= 0) {}
  return feedback.presented &&
         record_presentation(state, submit, surface_ready_ns,
                             render_started_ns, swap_submitted_ns,
                             feedback.time_ns, feedback.flags);
}

GstPadProbeReturn on_decoder_input(GstPad*, GstPadProbeInfo* info,
                                   gpointer user_data) {
  auto* state = static_cast<State*>(user_data);
  if ((GST_PAD_PROBE_INFO_TYPE(info) & GST_PAD_PROBE_TYPE_BUFFER) == 0) {
    return GST_PAD_PROBE_OK;
  }
  const std::uint64_t frame = ++state->submitted;
  std::uint64_t target_present_ns = 0;
  if (state->submit_lead_ns != 0) {
    std::uint64_t target =
        state->first_target_present_ns + (frame - 1) * state->refresh_ns -
        state->submit_lead_ns;
    const std::uint64_t now = clock_ns(state->presentation_clock);
    if (target <= now) {
      const std::uint64_t periods = (now - target) / state->refresh_ns + 1;
      state->first_target_present_ns += periods * state->refresh_ns;
      target += periods * state->refresh_ns;
    }
    target_present_ns = target + state->submit_lead_ns;
    timespec wake_time{};
    wake_time.tv_sec = static_cast<time_t>(target / 1000000000ULL);
    wake_time.tv_nsec = static_cast<long>(target % 1000000000ULL);
    int sleep_status = 0;
    do {
      sleep_status = clock_nanosleep(state->presentation_clock, TIMER_ABSTIME,
                                     &wake_time, nullptr);
    } while (sleep_status == EINTR);
    if (sleep_status != 0) {
      state->failed = true;
      return GST_PAD_PROBE_DROP;
    }
    const std::uint64_t actual = clock_ns(state->presentation_clock);
    state->input_schedule_late_ms.push_back(
        actual > target
            ? static_cast<double>(actual - target) / 1000000.0
            : 0.0);
  }
  const SubmitStamp stamp{frame, clock_ns(state->presentation_clock),
                          target_present_ns};
  std::lock_guard<std::mutex> lock(state->submit_mutex);
  state->submit_queue.push_back(stamp);
  state->max_submit_depth =
      std::max(state->max_submit_depth, state->submit_queue.size());
  return GST_PAD_PROBE_OK;
}

gboolean on_propose_allocation(GstAppSink*, GstQuery* query, gpointer) {
  gst_query_add_allocation_meta(query, GST_VIDEO_META_API_TYPE, nullptr);
  return TRUE;
}

bool process_sample(State* state, GstSample* sample, const SubmitStamp& submit,
                    std::uint64_t surface_ready_ns);

GstFlowReturn on_new_sample(GstAppSink* sink, gpointer user_data) {
  auto* state = static_cast<State*>(user_data);
  GstSample* sample = gst_app_sink_pull_sample(sink);
  if (sample == nullptr) return GST_FLOW_ERROR;
  const std::uint64_t surface_ready_ns = clock_ns(state->presentation_clock);
  SubmitStamp submit;
  {
    std::lock_guard<std::mutex> lock(state->submit_mutex);
    if (state->submit_queue.empty()) {
      state->failed = true;
      gst_sample_unref(sample);
      return GST_FLOW_ERROR;
    }
    submit = state->submit_queue.front();
    state->submit_queue.pop_front();
  }

  if (state->threaded) {
    std::unique_lock<std::mutex> lock(state->ready_mutex);
    state->ready_consumed.wait(
        lock, [state] { return state->ready_sample == nullptr ||
                              state->worker_stop; });
    if (state->worker_stop) {
      gst_sample_unref(sample);
      return GST_FLOW_ERROR;
    }
    state->ready_sample = sample;
    state->ready_submit = submit;
    state->ready_surface_ns = surface_ready_ns;
    state->max_ready_depth = 1;
    const std::uint64_t frames = ++state->queued;
    lock.unlock();
    state->ready_available.notify_one();
    return frames >= state->expected_frames ? GST_FLOW_EOS : GST_FLOW_OK;
  }

  ++state->queued;
  const bool valid = process_sample(state, sample, submit, surface_ready_ns);
  gst_sample_unref(sample);
  if (!valid) {
    state->failed = true;
    return GST_FLOW_ERROR;
  }
  const std::uint64_t frames = ++state->presented;
  return frames >= state->expected_frames ? GST_FLOW_EOS : GST_FLOW_OK;
}

bool process_sample(State* state, GstSample* sample, const SubmitStamp& submit,
                    std::uint64_t surface_ready_ns) {

  if (state->async_feedback) {
    while (state->async_inflight >= state->async_inflight_limit) {
      if (wl_display_dispatch(state->wl_display_handle) < 0) {
        state->failed = true;
        return false;
      }
    }
    if (submit.target_present_ns != 0) {
      const std::uint64_t now = clock_ns(state->presentation_clock);
      constexpr std::uint64_t kStaleToleranceNs = 1000000ULL;
      if (now > submit.target_present_ns + kStaleToleranceNs) {
        ++state->stale_frames_dropped;
        state->stale_drop_late_ms.push_back(
            static_cast<double>(now - submit.target_present_ns) / 1000000.0);
        return true;
      }
    }
  }

  GstBuffer* buffer = gst_sample_get_buffer(sample);
  GstCaps* caps = gst_sample_get_caps(sample);
  GstVideoMeta* meta =
      buffer == nullptr ? nullptr : gst_buffer_get_video_meta(buffer);
  const GstStructure* structure =
      caps == nullptr ? nullptr : gst_caps_get_structure(caps, 0);
  const gchar* drm_format =
      structure == nullptr ? nullptr
                           : gst_structure_get_string(structure, "drm-format");
  bool valid = buffer != nullptr && meta != nullptr && drm_format != nullptr &&
               std::string(drm_format).rfind("Y410", 0) == 0 &&
               gst_buffer_n_memory(buffer) == 1;
  int fd = -1;
  if (valid) {
    GstMemory* memory = gst_buffer_peek_memory(buffer, 0);
    valid = gst_is_dmabuf_memory(memory);
    if (valid) fd = gst_dmabuf_memory_get_fd(memory);
    valid = valid && fd >= 0;
  }
  if (valid) {
    state->drm_format = drm_format;
    state->width = meta->width;
    state->height = meta->height;
    valid = import_and_present(state, fd, meta, drm_format, submit,
                               surface_ready_ns);
  }
  return valid;
}

bool drain_async_feedback(State* state) {
  while (state->async_inflight != 0) {
    if (wl_display_dispatch(state->wl_display_handle) < 0) {
      state->failed = true;
      return false;
    }
  }
  return !state->failed.load();
}

void presentation_worker(State* state) {
  while (true) {
    GstSample* sample = nullptr;
    SubmitStamp submit;
    std::uint64_t surface_ready_ns = 0;
    {
      std::unique_lock<std::mutex> lock(state->ready_mutex);
      state->ready_available.wait(lock, [state] {
        return state->ready_sample != nullptr || state->producer_done ||
               state->worker_stop;
      });
      if (state->worker_stop) {
        sample = state->ready_sample;
        state->ready_sample = nullptr;
        lock.unlock();
        state->ready_consumed.notify_all();
        if (sample != nullptr) gst_sample_unref(sample);
        if (state->async_feedback) drain_async_feedback(state);
        return;
      }
      if (state->ready_sample == nullptr && state->producer_done) {
        lock.unlock();
        if (state->async_feedback) drain_async_feedback(state);
        return;
      }
      sample = state->ready_sample;
      submit = state->ready_submit;
      surface_ready_ns = state->ready_surface_ns;
      state->ready_sample = nullptr;
    }
    state->ready_consumed.notify_one();

    const bool valid = process_sample(state, sample, submit, surface_ready_ns);
    gst_sample_unref(sample);
    if (!valid) {
      state->failed = true;
      {
        std::lock_guard<std::mutex> lock(state->ready_mutex);
        state->worker_stop = true;
      }
      state->ready_available.notify_all();
      state->ready_consumed.notify_all();
      if (state->async_feedback) drain_async_feedback(state);
      return;
    }
    if (!state->async_feedback) ++state->presented;
  }
}

double percentile(std::vector<double> values, double fraction) {
  if (values.empty()) return 0.0;
  std::sort(values.begin(), values.end());
  const std::size_t index = static_cast<std::size_t>(
      fraction * static_cast<double>(values.size() - 1));
  return values[index];
}

void print_stats(const char* name, const std::vector<double>& values) {
  std::cout << name << "_p50_ms=" << percentile(values, 0.50) << '\n'
            << name << "_p95_ms=" << percentile(values, 0.95) << '\n'
            << name << "_p99_ms=" << percentile(values, 0.99) << '\n';
}

bool parse_positive(const char* text, std::uint64_t* value) {
  char* end = nullptr;
  const unsigned long long parsed = std::strtoull(text, &end, 10);
  if (end == text || *end != '\0' || parsed == 0) return false;
  *value = parsed;
  return true;
}

bool parse_nonnegative(const char* text, std::uint64_t* value) {
  char* end = nullptr;
  const unsigned long long parsed = std::strtoull(text, &end, 10);
  if (end == text || *end != '\0') return false;
  *value = parsed;
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2 || argc > 6) {
    std::cerr << "usage: " << argv[0]
              << " BITSTREAM [FRAME_COUNT] [SUBMIT_LEAD_US] "
                 "[serial|threaded|async|async-nofifo] [ASYNC_INFLIGHT]\n";
    return 2;
  }
  State state;
  state.expected_frames = 600;
  if (argc >= 3 && !parse_positive(argv[2], &state.expected_frames)) return 2;
  if (argc >= 4) {
    std::uint64_t submit_lead_us = 0;
    if (!parse_nonnegative(argv[3], &submit_lead_us) ||
        submit_lead_us >= 16667) {
      std::cerr << "submit lead must be between 0 and 16666 us\n";
      return 2;
    }
    state.submit_lead_ns = submit_lead_us * 1000ULL;
  }
  if (argc >= 5) {
    const std::string mode = argv[4];
    if (mode != "serial" && mode != "threaded" && mode != "async" &&
        mode != "async-nofifo") {
      std::cerr << "pipeline mode must be serial, threaded, async, or "
                   "async-nofifo\n";
      return 2;
    }
    state.threaded = mode != "serial";
    state.async_feedback = mode == "async" || mode == "async-nofifo";
    state.fifo_enabled = mode == "async";
  }
  if (argc == 6) {
    if (!state.async_feedback ||
        !parse_positive(argv[5], &state.async_inflight_limit) ||
        state.async_inflight_limit > 4) {
      std::cerr << "async in-flight limit must be between 1 and 4 and is only "
                   "valid in async mode\n";
      return 2;
    }
  }
  if (!initialize_graphics(&state)) {
    std::cerr << "graphics initialization failed\n";
    shutdown_graphics(&state);
    return 3;
  }

  gst_init(&argc, &argv);
  const gchar* description =
      "filesrc name=input ! h265parse name=parser ! "
      "video/x-h265,stream-format=byte-stream,alignment=au ! vah265dec ! "
      "video/x-raw(memory:DMABuf) ! appsink name=dmabuf_sink";
  GError* error = nullptr;
  GstElement* pipeline = gst_parse_launch(description, &error);
  if (pipeline == nullptr || error != nullptr) {
    if (error != nullptr) std::cerr << error->message << '\n';
    g_clear_error(&error);
    shutdown_graphics(&state);
    return 4;
  }
  GstElement* source = gst_bin_get_by_name(GST_BIN(pipeline), "input");
  GstElement* parser = gst_bin_get_by_name(GST_BIN(pipeline), "parser");
  GstElement* sink = gst_bin_get_by_name(GST_BIN(pipeline), "dmabuf_sink");
  GstPad* parser_src =
      parser == nullptr ? nullptr : gst_element_get_static_pad(parser, "src");
  if (source == nullptr || parser == nullptr || sink == nullptr ||
      parser_src == nullptr) {
    shutdown_graphics(&state);
    gst_object_unref(pipeline);
    return 4;
  }
  g_object_set(source, "location", argv[1], nullptr);
  g_object_set(sink, "emit-signals", TRUE, "sync", FALSE, "max-buffers", 1U,
               nullptr);
  gst_pad_add_probe(parser_src, GST_PAD_PROBE_TYPE_BUFFER, on_decoder_input,
                    &state, nullptr);
  g_signal_connect(sink, "propose-allocation",
                   G_CALLBACK(on_propose_allocation), &state);
  g_signal_connect(sink, "new-sample", G_CALLBACK(on_new_sample), &state);
  gst_object_unref(source);
  gst_object_unref(parser);
  gst_object_unref(parser_src);

  std::thread worker;
  if (state.threaded) worker = std::thread(presentation_worker, &state);
  bool reached_eos =
      gst_element_set_state(pipeline, GST_STATE_PLAYING) !=
      GST_STATE_CHANGE_FAILURE;
  GstBus* bus = gst_element_get_bus(pipeline);
  GstMessage* message = gst_bus_timed_pop_filtered(
      bus, GST_CLOCK_TIME_NONE,
      static_cast<GstMessageType>(GST_MESSAGE_ERROR | GST_MESSAGE_EOS));
  if (message == nullptr || GST_MESSAGE_TYPE(message) == GST_MESSAGE_ERROR) {
    reached_eos = false;
    if (message != nullptr) {
      GError* pipeline_error = nullptr;
      gchar* debug = nullptr;
      gst_message_parse_error(message, &pipeline_error, &debug);
      std::cerr << "pipeline failed: " << pipeline_error->message << '\n';
      if (debug != nullptr) std::cerr << debug << '\n';
      g_clear_error(&pipeline_error);
      g_free(debug);
    }
  }
  if (message != nullptr) gst_message_unref(message);
  if (state.threaded) {
    {
      std::lock_guard<std::mutex> lock(state.ready_mutex);
      state.producer_done = true;
      if (!reached_eos) state.worker_stop = true;
    }
    state.ready_available.notify_all();
    state.ready_consumed.notify_all();
    worker.join();
  }
  gst_element_set_state(pipeline, GST_STATE_NULL);
  gst_object_unref(bus);
  gst_object_unref(sink);
  gst_object_unref(pipeline);
  shutdown_graphics(&state);

  const std::uint64_t frames = state.presented.load();
  const double effective_fps =
      frames > 1 && state.last_presentation_ns > state.first_presentation_ns
          ? static_cast<double>(frames - 1) * 1000000000.0 /
                static_cast<double>(state.last_presentation_ns -
                                    state.first_presentation_ns)
          : 0.0;
  const std::uint64_t missed_refresh_intervals = static_cast<std::uint64_t>(
      std::count_if(state.presentation_interval_ms.begin(),
                    state.presentation_interval_ms.end(), [&state](double ms) {
                      return ms * 1000000.0 >
                             static_cast<double>(state.refresh_ns) * 1.5;
                    }));
  const bool frame_pacing_passed =
      effective_fps >= 59.9 && missed_refresh_intervals == 0 &&
      percentile(state.presentation_interval_ms, 0.95) <= 16.8;
  const bool passed = reached_eos && !state.failed.load() &&
                      frames == state.expected_frames &&
                      state.submit_to_present_ms.size() == frames &&
                      frame_pacing_passed;
  std::cout << std::fixed << std::setprecision(3)
            << "frames_submitted=" << state.submitted.load() << '\n'
            << "frames_queued=" << state.queued.load() << '\n'
            << "frames_presented=" << frames << '\n'
            << "stale_frames_dropped=" << state.stale_frames_dropped << '\n'
            << "max_submit_depth=" << state.max_submit_depth << '\n'
            << "max_ready_depth=" << state.max_ready_depth << '\n'
            << "max_async_inflight=" << state.max_async_inflight << '\n'
            << "async_inflight_limit=" << state.async_inflight_limit << '\n'
            << "pipeline_mode="
            << (state.async_feedback
                    ? (state.fifo_enabled ? "async" : "async-nofifo")
                    : (state.threaded ? "threaded" : "serial"))
            << '\n'
            << "submit_lead_us=" << state.submit_lead_ns / 1000ULL << '\n'
            << "refresh_ns=" << state.refresh_ns << '\n'
            << "decoded_drm_format=" << state.drm_format << '\n'
            << "decoded_width=" << state.width << '\n'
            << "decoded_height=" << state.height << '\n'
            << "egl_native_visual=0x" << std::hex
            << static_cast<std::uint32_t>(state.native_visual) << std::dec
            << '\n';
  print_stats("decode", state.decode_ms);
  print_stats("surface_to_swap", state.surface_to_swap_ms);
  print_stats("swap_submit", state.swap_submit_ms);
  print_stats("surface_to_present", state.surface_to_present_ms);
  print_stats("submit_to_present", state.submit_to_present_ms);
  print_stats("presentation_interval", state.presentation_interval_ms);
  if (!state.input_schedule_late_ms.empty())
    print_stats("input_schedule_late", state.input_schedule_late_ms);
  if (!state.surface_vs_target_ms.empty()) {
    print_stats("surface_vs_target", state.surface_vs_target_ms);
    print_stats("swap_vs_target", state.swap_vs_target_ms);
    print_stats("presentation_vs_target", state.presentation_vs_target_ms);
  }
  if (!state.stale_drop_late_ms.empty())
    print_stats("stale_drop_late", state.stale_drop_late_ms);
  std::cout << "vsync_frames=" << state.vsync_frames << '\n'
            << "hardware_clock_frames=" << state.hw_clock_frames << '\n'
            << "hardware_completion_frames=" << state.hw_completion_frames
            << '\n'
            << "zero_copy_frames=" << state.zero_copy_frames << '\n'
            << "commit_timing_available="
            << (state.commit_timing_available ? "yes" : "no") << '\n'
            << "commit_timing_frames=" << state.commit_timing_frames << '\n'
            << "fifo_available=" << (state.fifo_available ? "yes" : "no")
            << '\n'
            << "fifo_enabled=" << (state.fifo_enabled ? "yes" : "no")
            << '\n'
            << "fifo_frames=" << state.fifo_frames << '\n'
            << "effective_presentation_fps=" << effective_fps << '\n'
            << "missed_refresh_intervals=" << missed_refresh_intervals << '\n'
            << "frame_pacing_gate="
            << (frame_pacing_passed ? "pass" : "fail") << '\n'
            << "decoded_surface_cpu_map=no\n"
            << "integrated_client_pipeline_gate="
            << (passed ? "pass" : "fail") << '\n';
  return passed ? 0 : 1;
}
