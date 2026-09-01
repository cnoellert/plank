#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <drm_fourcc.h>
#include <wayland-client.h>
#include <wayland-egl.h>

#include "xdg-shell-client-protocol.h"

namespace {

struct State {
  wl_display* display = nullptr;
  wl_compositor* compositor = nullptr;
  xdg_wm_base* wm_base = nullptr;
  wl_surface* surface = nullptr;
  xdg_surface* xdg_surface_handle = nullptr;
  xdg_toplevel* toplevel = nullptr;
  wl_egl_window* window = nullptr;
  bool configured = false;
  int width = 3840;
  int height = 2160;
};

void on_registry_global(void* data, wl_registry* registry, std::uint32_t name,
                        const char* interface, std::uint32_t version) {
  auto* state = static_cast<State*>(data);
  if (std::string(interface) == wl_compositor_interface.name) {
    state->compositor = static_cast<wl_compositor*>(
        wl_registry_bind(registry, name, &wl_compositor_interface,
                         std::min(version, 4U)));
  } else if (std::string(interface) == xdg_wm_base_interface.name) {
    state->wm_base = static_cast<xdg_wm_base*>(
        wl_registry_bind(registry, name, &xdg_wm_base_interface, 1));
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
    state->width = width;
    state->height = height;
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

void on_frame_done(void* data, wl_callback* callback, std::uint32_t) {
  *static_cast<bool*>(data) = true;
  wl_callback_destroy(callback);
}
const wl_callback_listener kFrameListener = {on_frame_done};

double percentile(std::vector<double> values, double fraction) {
  if (values.empty()) return 0.0;
  std::sort(values.begin(), values.end());
  const std::size_t index = static_cast<std::size_t>(
      fraction * static_cast<double>(values.size() - 1));
  return values[index];
}

void cleanup(State* state, EGLDisplay egl_display, EGLSurface egl_surface,
             EGLContext egl_context) {
  if (egl_display != EGL_NO_DISPLAY) {
    eglMakeCurrent(egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (egl_context != EGL_NO_CONTEXT) eglDestroyContext(egl_display, egl_context);
    if (egl_surface != EGL_NO_SURFACE) eglDestroySurface(egl_display, egl_surface);
    eglTerminate(egl_display);
  }
  if (state->window != nullptr) wl_egl_window_destroy(state->window);
  if (state->toplevel != nullptr) xdg_toplevel_destroy(state->toplevel);
  if (state->xdg_surface_handle != nullptr)
    xdg_surface_destroy(state->xdg_surface_handle);
  if (state->surface != nullptr) wl_surface_destroy(state->surface);
  if (state->wm_base != nullptr) xdg_wm_base_destroy(state->wm_base);
  if (state->compositor != nullptr) wl_compositor_destroy(state->compositor);
  if (state->display != nullptr) wl_display_disconnect(state->display);
}

}  // namespace

int main(int argc, char** argv) {
  std::uint64_t frame_count = 180;
  if (argc > 2) {
    std::cerr << "usage: " << argv[0] << " [FRAME_COUNT]\n";
    return 2;
  }
  if (argc == 2) {
    char* end = nullptr;
    frame_count = std::strtoull(argv[1], &end, 10);
    if (end == argv[1] || *end != '\0' || frame_count == 0) return 2;
  }

  State state;
  state.display = wl_display_connect(nullptr);
  if (state.display == nullptr) {
    std::cerr << "failed to connect to Wayland display\n";
    return 3;
  }
  wl_registry* registry = wl_display_get_registry(state.display);
  wl_registry_add_listener(registry, &kRegistryListener, &state);
  wl_display_roundtrip(state.display);
  wl_registry_destroy(registry);
  if (state.compositor == nullptr || state.wm_base == nullptr) {
    cleanup(&state, EGL_NO_DISPLAY, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    return 3;
  }
  xdg_wm_base_add_listener(state.wm_base, &kWmBaseListener, &state);
  state.surface = wl_compositor_create_surface(state.compositor);
  state.xdg_surface_handle =
      xdg_wm_base_get_xdg_surface(state.wm_base, state.surface);
  xdg_surface_add_listener(state.xdg_surface_handle, &kSurfaceListener, &state);
  state.toplevel = xdg_surface_get_toplevel(state.xdg_surface_handle);
  xdg_toplevel_add_listener(state.toplevel, &kToplevelListener, &state);
  xdg_toplevel_set_title(state.toplevel, "PLANK XR30 probe");
  xdg_toplevel_set_fullscreen(state.toplevel, nullptr);
  wl_surface_commit(state.surface);
  while (!state.configured && wl_display_dispatch(state.display) >= 0) {}

  EGLDisplay egl_display = eglGetPlatformDisplay(
      EGL_PLATFORM_WAYLAND_KHR, state.display, nullptr);
  EGLint major = 0;
  EGLint minor = 0;
  if (egl_display == EGL_NO_DISPLAY ||
      eglInitialize(egl_display, &major, &minor) != EGL_TRUE ||
      eglBindAPI(EGL_OPENGL_ES_API) != EGL_TRUE) {
    cleanup(&state, egl_display, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    return 4;
  }
  const EGLint config_attributes[] = {
      EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
      EGL_RED_SIZE, 10, EGL_GREEN_SIZE, 10, EGL_BLUE_SIZE, 10, EGL_ALPHA_SIZE, 2,
      EGL_NONE};
  EGLConfig config = nullptr;
  EGLint config_count = 0;
  if (eglChooseConfig(egl_display, config_attributes, &config, 1,
                      &config_count) != EGL_TRUE || config_count != 1) {
    std::cerr << "no 10-bit Wayland EGL configuration\n";
    cleanup(&state, egl_display, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    return 4;
  }
  EGLint visual_id = 0;
  EGLint red = 0;
  EGLint green = 0;
  EGLint blue = 0;
  eglGetConfigAttrib(egl_display, config, EGL_NATIVE_VISUAL_ID, &visual_id);
  eglGetConfigAttrib(egl_display, config, EGL_RED_SIZE, &red);
  eglGetConfigAttrib(egl_display, config, EGL_GREEN_SIZE, &green);
  eglGetConfigAttrib(egl_display, config, EGL_BLUE_SIZE, &blue);

  state.window = wl_egl_window_create(state.surface, state.width, state.height);
  EGLSurface egl_surface =
      eglCreateWindowSurface(egl_display, config,
                             reinterpret_cast<EGLNativeWindowType>(state.window),
                             nullptr);
  const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  EGLContext context = eglCreateContext(egl_display, config, EGL_NO_CONTEXT,
                                        context_attributes);
  if (state.window == nullptr || egl_surface == EGL_NO_SURFACE ||
      context == EGL_NO_CONTEXT ||
      eglMakeCurrent(egl_display, egl_surface, egl_surface, context) != EGL_TRUE) {
    cleanup(&state, egl_display, egl_surface, context);
    return 4;
  }
  eglSwapInterval(egl_display, 1);

  std::vector<double> swap_ms;
  std::vector<double> frame_callback_ms;
  swap_ms.reserve(frame_count);
  frame_callback_ms.reserve(frame_count);
  for (std::uint64_t frame = 0; frame < frame_count; ++frame) {
    const float phase = static_cast<float>(frame % 1024U) / 1023.0F;
    glViewport(0, 0, state.width, state.height);
    glClearColor(phase, 1.0F - phase, 0.5F, 1.0F);
    glClear(GL_COLOR_BUFFER_BIT);
    bool frame_done = false;
    wl_callback* callback = wl_surface_frame(state.surface);
    wl_callback_add_listener(callback, &kFrameListener, &frame_done);
    const auto start = std::chrono::steady_clock::now();
    if (eglSwapBuffers(egl_display, egl_surface) != EGL_TRUE) break;
    const auto submitted = std::chrono::steady_clock::now();
    while (!frame_done && wl_display_dispatch(state.display) >= 0) {}
    const auto done = std::chrono::steady_clock::now();
    swap_ms.push_back(std::chrono::duration<double, std::milli>(submitted - start).count());
    frame_callback_ms.push_back(
        std::chrono::duration<double, std::milli>(done - start).count());
  }

  const bool visual_is_10_bit =
      visual_id == static_cast<EGLint>(DRM_FORMAT_ARGB2101010) ||
      visual_id == static_cast<EGLint>(DRM_FORMAT_ABGR2101010) ||
      visual_id == static_cast<EGLint>(DRM_FORMAT_XRGB2101010) ||
      visual_id == static_cast<EGLint>(DRM_FORMAT_XBGR2101010);
  const bool passed = swap_ms.size() == frame_count && red == 10 && green == 10 &&
                      blue == 10 && visual_is_10_bit && glGetError() == GL_NO_ERROR;
  std::cout << "frames_presented=" << swap_ms.size() << '\n'
            << "surface_width=" << state.width << '\n'
            << "surface_height=" << state.height << '\n'
            << "egl_red_bits=" << red << '\n'
            << "egl_green_bits=" << green << '\n'
            << "egl_blue_bits=" << blue << '\n'
            << "egl_native_visual=0x" << std::hex
            << static_cast<std::uint32_t>(visual_id) << std::dec << '\n'
            << std::fixed << std::setprecision(3)
            << "swap_submit_p50_ms=" << percentile(swap_ms, 0.50) << '\n'
            << "swap_submit_p95_ms=" << percentile(swap_ms, 0.95) << '\n'
            << "frame_callback_p50_ms=" << percentile(frame_callback_ms, 0.50) << '\n'
            << "frame_callback_p95_ms=" << percentile(frame_callback_ms, 0.95) << '\n'
            << "wayland_xr30_gate=" << (passed ? "pass" : "fail") << '\n';
  cleanup(&state, egl_display, egl_surface, context);
  return passed ? 0 : 1;
}
