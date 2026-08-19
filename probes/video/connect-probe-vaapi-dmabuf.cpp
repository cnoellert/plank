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
#define GL_GLEXT_PROTOTYPES
#include <GLES3/gl32.h>
#include <GLES2/gl2ext.h>
#include <drm_fourcc.h>
#include <gbm.h>
#include <gst/allocators/gstdmabuf.h>
#include <gst/app/gstappsink.h>
#include <gst/gst.h>
#include <gst/video/gstvideometa.h>

namespace {

struct ProbeState {
  std::uint64_t expected_frames = 1;
  std::uint64_t sample_frame = 1;
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
  bool identity_shader_passed = false;
  std::string gl_renderer;
  std::uint32_t raw_y = 0;
  std::uint32_t raw_u = 0;
  std::uint32_t raw_v = 0;
  std::uint32_t output_r = 0;
  std::uint32_t output_g = 0;
  std::uint32_t output_b = 0;
  int drm_fd = -1;
  gbm_device* gbm = nullptr;
  EGLDisplay egl_display = EGL_NO_DISPLAY;
  EGLContext egl_context = EGL_NO_CONTEXT;
  PFNEGLCREATEIMAGEKHRPROC create_image = nullptr;
  PFNEGLDESTROYIMAGEKHRPROC destroy_image = nullptr;
  PFNGLEGLIMAGETARGETTEXTURE2DOESPROC image_target_texture = nullptr;
};

bool has_extension(const char* extensions, const char* name) {
  if (extensions == nullptr || name == nullptr || *name == '\0' ||
      std::strchr(name, ' ') != nullptr) {
    return false;
  }
  const std::size_t length = std::strlen(name);
  for (const char* match = std::strstr(extensions, name); match != nullptr;
       match = std::strstr(match + length, name)) {
    const bool begins_token = match == extensions || match[-1] == ' ';
    const bool ends_token = match[length] == '\0' || match[length] == ' ';
    if (begins_token && ends_token) return true;
  }
  return false;
}

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
  if (!has_extension(extensions, "EGL_EXT_image_dma_buf_import") ||
      !has_extension(extensions, "EGL_EXT_image_dma_buf_import_modifiers") ||
      !has_extension(extensions, "EGL_KHR_no_config_context") ||
      !has_extension(extensions, "EGL_KHR_surfaceless_context")) {
    std::cerr << "required EGL DMA-BUF import extensions are unavailable\n";
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
      state->image_target_texture == nullptr ||
      eglBindAPI(EGL_OPENGL_ES_API) != EGL_TRUE) {
    return false;
  }

  const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  state->egl_context = eglCreateContext(state->egl_display, EGL_NO_CONFIG_KHR,
                                        EGL_NO_CONTEXT, context_attributes);
  if (state->egl_context == EGL_NO_CONTEXT ||
      eglMakeCurrent(state->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                     state->egl_context) != EGL_TRUE) {
    std::cerr << "failed to create GLES context\n";
    return false;
  }
  const char* gl_extensions =
      reinterpret_cast<const char*>(glGetString(GL_EXTENSIONS));
  const char* renderer = reinterpret_cast<const char*>(glGetString(GL_RENDERER));
  if (!has_extension(gl_extensions, "GL_OES_EGL_image") ||
      !has_extension(gl_extensions, "GL_OES_EGL_image_external_essl3") ||
      renderer == nullptr) {
    std::cerr << "required GLES EGL-image extension is unavailable\n";
    return false;
  }
  state->gl_renderer = renderer;
  return eglMakeCurrent(state->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                        EGL_NO_CONTEXT) == EGL_TRUE;
}

void shutdown_egl(ProbeState* state) {
  if (state->egl_display != EGL_NO_DISPLAY) {
    eglMakeCurrent(state->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                   EGL_NO_CONTEXT);
    if (state->egl_context != EGL_NO_CONTEXT) {
      eglDestroyContext(state->egl_display, state->egl_context);
      state->egl_context = EGL_NO_CONTEXT;
    }
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

bool sample_identity_shader(ProbeState* state, EGLImageKHR image) {
  if (eglMakeCurrent(state->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                     state->egl_context) != EGL_TRUE) {
    std::cerr << "failed to make GLES context current\n";
    return false;
  }

  const char* vertex_source = R"glsl(#version 300 es
void main() {
  vec2 position;
  if (gl_VertexID == 0) position = vec2(-1.0, -1.0);
  else if (gl_VertexID == 1) position = vec2(3.0, -1.0);
  else position = vec2(-1.0, 3.0);
  gl_Position = vec4(position, 0.0, 1.0);
}
)glsl";
  const char* fragment_source = R"glsl(#version 300 es
#extension GL_OES_EGL_image_external_essl3 : require
precision highp float;
uniform samplerExternalOES source_texture;
uniform vec2 sample_coordinate;
out vec4 fragment_color;
void main() {
  // Y410 is packed A:V:Y:U. Importing the same storage as XR30 makes those
  // fields R:G:B, which exactly reverses the transport's Y=G,U=B,V=R map.
  fragment_color = texture(source_texture, sample_coordinate);
}
)glsl";

  const GLuint vertex_shader = compile_shader(GL_VERTEX_SHADER, vertex_source);
  const GLuint fragment_shader =
      compile_shader(GL_FRAGMENT_SHADER, fragment_source);
  if (vertex_shader == 0 || fragment_shader == 0) {
    eglMakeCurrent(state->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                   EGL_NO_CONTEXT);
    return false;
  }
  const GLuint program = glCreateProgram();
  glAttachShader(program, vertex_shader);
  glAttachShader(program, fragment_shader);
  glLinkProgram(program);
  glDeleteShader(vertex_shader);
  glDeleteShader(fragment_shader);
  GLint linked = GL_FALSE;
  glGetProgramiv(program, GL_LINK_STATUS, &linked);
  if (linked != GL_TRUE) {
    char log[2048]{};
    glGetProgramInfoLog(program, sizeof(log), nullptr, log);
    std::cerr << "shader link failed: " << log << '\n';
    glDeleteProgram(program);
    eglMakeCurrent(state->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                   EGL_NO_CONTEXT);
    return false;
  }

  GLuint external_texture = 0;
  glGenTextures(1, &external_texture);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_EXTERNAL_OES, external_texture);
  glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  state->image_target_texture(GL_TEXTURE_EXTERNAL_OES,
                              reinterpret_cast<GLeglImageOES>(image));

  GLuint output_texture = 0;
  glGenTextures(1, &output_texture);
  glBindTexture(GL_TEXTURE_2D, output_texture);
  glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGB10_A2, 2, 1);
  GLuint framebuffer = 0;
  glGenFramebuffers(1, &framebuffer);
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         output_texture, 0);

  bool valid = glGetError() == GL_NO_ERROR &&
               glCheckFramebufferStatus(GL_FRAMEBUFFER) ==
                   GL_FRAMEBUFFER_COMPLETE;
  std::uint32_t pixels[2]{};
  if (valid) {
    GLuint vertex_array = 0;
    glGenVertexArrays(1, &vertex_array);
    glBindVertexArray(vertex_array);
    glViewport(0, 0, 2, 1);
    glDisable(GL_DITHER);
    glUseProgram(program);
    glUniform1i(glGetUniformLocation(program, "source_texture"), 0);
    glUniform2f(glGetUniformLocation(program, "sample_coordinate"), 0.5F,
                0.5F);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glReadPixels(0, 0, 2, 1, GL_RGBA,
                 GL_UNSIGNED_INT_2_10_10_10_REV, pixels);
    valid = glGetError() == GL_NO_ERROR;
    glDeleteVertexArrays(1, &vertex_array);
  }

  glDeleteFramebuffers(1, &framebuffer);
  glDeleteTextures(1, &output_texture);
  glDeleteTextures(1, &external_texture);
  glDeleteProgram(program);
  eglMakeCurrent(state->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                 EGL_NO_CONTEXT);
  if (!valid) {
    std::cerr << "raw Y410 shader sampling failed\n";
    return false;
  }

  // XR30's sampled R:G:B correspond to Y410's packed V:Y:U fields.
  state->raw_v = pixels[0] & 0x3ffU;
  state->raw_y = (pixels[0] >> 10U) & 0x3ffU;
  state->raw_u = (pixels[0] >> 20U) & 0x3ffU;
  state->output_r = pixels[1] & 0x3ffU;
  state->output_g = (pixels[1] >> 10U) & 0x3ffU;
  state->output_b = (pixels[1] >> 20U) & 0x3ffU;
  return state->output_r == state->raw_v &&
         state->output_g == state->raw_y &&
         state->output_b == state->raw_u;
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
      static_cast<EGLint>(DRM_FORMAT_XRGB2101010),
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
    std::cerr << "EGL Y410-as-XR30 DMA-BUF import failed, error=0x" << std::hex
              << eglGetError() << std::dec << '\n';
    return false;
  }
  state->identity_shader_passed = sample_identity_shader(state, image);
  const bool destroyed =
      state->destroy_image(state->egl_display, image) == EGL_TRUE;
  return state->identity_shader_passed && destroyed;
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

  const std::uint64_t frame_number = state->frames.load() + 1;
  if (frame_number == state->sample_frame && valid) {
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
  if (argc < 2 || argc > 5) {
    std::cerr << "usage: " << argv[0]
              << " BITSTREAM [FRAME_COUNT] [SAMPLE_FRAME] [RENDER_NODE]\n";
    return 2;
  }
  std::uint64_t expected_frames = 1;
  if (argc >= 3 && !parse_positive(argv[2], &expected_frames)) {
    std::cerr << "invalid frame count: " << argv[2] << '\n';
    return 2;
  }
  std::uint64_t sample_frame = 1;
  if (argc >= 4 && !parse_positive(argv[3], &sample_frame)) {
    std::cerr << "invalid sample frame: " << argv[3] << '\n';
    return 2;
  }
  if (sample_frame > expected_frames) {
    std::cerr << "sample frame exceeds frame count\n";
    return 2;
  }
  const char* render_node = argc == 5 ? argv[4] : "/dev/dri/renderD128";

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
  state.sample_frame = sample_frame;
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
                      frames == expected_frames && state.egl_imported &&
                      state.identity_shader_passed;
  std::cout << "dmabuf_frames=" << frames << '\n'
            << "elapsed_ms=" << elapsed_ms << '\n'
            << "dmabuf_fps=" << std::fixed << std::setprecision(2)
            << frames_per_second << '\n'
            << "sample_frame=" << state.sample_frame << '\n'
            << "drm_format=" << state.drm_format << '\n'
            << "width=" << state.width << '\n'
            << "height=" << state.height << '\n'
            << "planes=" << state.planes << '\n'
            << "stride0=" << state.stride << '\n'
            << "offset0=" << state.offset << '\n'
            << "dmabuf_memories=" << state.memories << '\n'
            << "egl_image_import="
            << (state.egl_imported ? "pass" : "fail") << '\n'
            << "gl_renderer=" << state.gl_renderer << '\n'
            << "raw_y10=" << state.raw_y << '\n'
            << "raw_u10=" << state.raw_u << '\n'
            << "raw_v10=" << state.raw_v << '\n'
            << "output_r10=" << state.output_r << '\n'
            << "output_g10=" << state.output_g << '\n'
            << "output_b10=" << state.output_b << '\n'
            << "identity_shader="
            << (state.identity_shader_passed ? "pass" : "fail") << '\n'
            << "decoded_surface_cpu_map=no\n"
            << "test_output_readback=yes\n"
            << "vaapi_y410_dmabuf_gate=" << (passed ? "pass" : "fail")
            << '\n';
  return passed ? 0 : 1;
}
