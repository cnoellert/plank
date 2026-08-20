#include <NvFBC.h>

#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <dlfcn.h>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

#define FFNV_LOG_FUNC(logctx, message, ...)       \
  do {                                            \
    (void)(logctx);                               \
    std::fprintf(stderr, message, __VA_ARGS__);   \
  } while (false)
#define FFNV_DEBUG_LOG_FUNC(logctx, message, ...) \
  do {                                            \
    (void)(logctx);                               \
  } while (false)
#include <ffnvcodec/dynlink_loader.h>

namespace {

constexpr const char* kConversionPtx = R"ptx(
.version 5.0
.target sm_50
.address_size 64

.visible .entry bgra8_to_gbr8(
    .param .u64 source_ptr,
    .param .u64 destination_ptr,
    .param .u32 pixel_count)
{
    .reg .pred %p<2>;
    .reg .b32 %r<10>;
    .reg .b64 %rd<10>;

    ld.param.u64 %rd1, [source_ptr];
    ld.param.u64 %rd2, [destination_ptr];
    ld.param.u32 %r1, [pixel_count];
    mov.u32 %r2, %ctaid.x;
    mov.u32 %r3, %ntid.x;
    mov.u32 %r4, %tid.x;
    mad.lo.u32 %r5, %r2, %r3, %r4;
    setp.ge.u32 %p1, %r5, %r1;
    @%p1 bra done8;

    mul.wide.u32 %rd3, %r5, 4;
    add.u64 %rd4, %rd1, %rd3;
    ld.global.u8 %r6, [%rd4];
    ld.global.u8 %r7, [%rd4+1];
    ld.global.u8 %r8, [%rd4+2];

    cvt.u64.u32 %rd5, %r5;
    cvt.u64.u32 %rd6, %r1;
    add.u64 %rd7, %rd2, %rd5;
    st.global.u8 [%rd7], %r7;
    add.u64 %rd8, %rd7, %rd6;
    st.global.u8 [%rd8], %r6;
    add.u64 %rd9, %rd8, %rd6;
    st.global.u8 [%rd9], %r8;

done8:
    ret;
}

.visible .entry bgra8_to_gbr10(
    .param .u64 source_ptr,
    .param .u64 destination_ptr,
    .param .u32 pixel_count)
{
    .reg .pred %p<5>;
    .reg .b32 %r<22>;
    .reg .b64 %rd<11>;

    ld.param.u64 %rd1, [source_ptr];
    ld.param.u64 %rd2, [destination_ptr];
    ld.param.u32 %r1, [pixel_count];
    mov.u32 %r2, %ctaid.x;
    mov.u32 %r3, %ntid.x;
    mov.u32 %r4, %tid.x;
    mad.lo.u32 %r5, %r2, %r3, %r4;
    setp.ge.u32 %p1, %r5, %r1;
    @%p1 bra done10;

    mul.wide.u32 %rd3, %r5, 4;
    add.u64 %rd4, %rd1, %rd3;
    ld.global.u8 %r6, [%rd4];
    ld.global.u8 %r7, [%rd4+1];
    ld.global.u8 %r8, [%rd4+2];

    shl.b32 %r9, %r6, 2;
    setp.ge.u32 %p2, %r6, 43;
    selp.u32 %r15, 1, 0, %p2;
    add.u32 %r9, %r9, %r15;
    setp.ge.u32 %p3, %r6, 128;
    selp.u32 %r16, 1, 0, %p3;
    add.u32 %r9, %r9, %r16;
    setp.ge.u32 %p4, %r6, 213;
    selp.u32 %r17, 1, 0, %p4;
    add.u32 %r9, %r9, %r17;

    shl.b32 %r10, %r7, 2;
    setp.ge.u32 %p2, %r7, 43;
    selp.u32 %r15, 1, 0, %p2;
    add.u32 %r10, %r10, %r15;
    setp.ge.u32 %p3, %r7, 128;
    selp.u32 %r16, 1, 0, %p3;
    add.u32 %r10, %r10, %r16;
    setp.ge.u32 %p4, %r7, 213;
    selp.u32 %r17, 1, 0, %p4;
    add.u32 %r10, %r10, %r17;

    shl.b32 %r11, %r8, 2;
    setp.ge.u32 %p2, %r8, 43;
    selp.u32 %r15, 1, 0, %p2;
    add.u32 %r11, %r11, %r15;
    setp.ge.u32 %p3, %r8, 128;
    selp.u32 %r16, 1, 0, %p3;
    add.u32 %r11, %r11, %r16;
    setp.ge.u32 %p4, %r8, 213;
    selp.u32 %r17, 1, 0, %p4;
    add.u32 %r11, %r11, %r17;

    mul.wide.u32 %rd5, %r5, 2;
    cvt.u64.u32 %rd6, %r1;
    shl.b64 %rd7, %rd6, 1;
    add.u64 %rd8, %rd2, %rd5;
    st.global.u16 [%rd8], %r10;
    add.u64 %rd9, %rd8, %rd7;
    st.global.u16 [%rd9], %r9;
    add.u64 %rd10, %rd9, %rd7;
    st.global.u16 [%rd10], %r11;

done10:
    ret;
}
)ptx";

enum class OutputFormat { kBgra, kGbrIdentity8, kGbrIdentity10 };

const char* output_format_name(OutputFormat format) {
  switch (format) {
    case OutputFormat::kBgra:
      return "bgra";
    case OutputFormat::kGbrIdentity8:
      return "yuv444p-gbr-identity";
    case OutputFormat::kGbrIdentity10:
      return "yuv444p10le-gbr-identity";
  }
  return "unknown";
}

struct Resources {
  CudaFunctions* cuda = nullptr;
  CUcontext cuda_context = nullptr;
  void* nvfbc_library = nullptr;
  NVFBC_API_FUNCTION_LIST nvfbc{};
  NVFBC_SESSION_HANDLE nvfbc_handle = 0;
  bool capture_created = false;
  void* host_buffer = nullptr;
  CUdeviceptr converted_buffer = 0;
  CUmodule cuda_module = nullptr;
  CUfunction conversion_kernel = nullptr;

  ~Resources() {
    if (converted_buffer != 0 && cuda != nullptr) {
      cuda->cuMemFree(converted_buffer);
    }
    if (host_buffer != nullptr && cuda != nullptr) {
      cuda->cuMemFreeHost(host_buffer);
    }
    if (capture_created && nvfbc.nvFBCDestroyCaptureSession != nullptr) {
      NVFBC_DESTROY_CAPTURE_SESSION_PARAMS parameters{};
      parameters.dwVersion = NVFBC_DESTROY_CAPTURE_SESSION_PARAMS_VER;
      nvfbc.nvFBCDestroyCaptureSession(nvfbc_handle, &parameters);
    }
    if (nvfbc_handle != 0 && nvfbc.nvFBCDestroyHandle != nullptr) {
      NVFBC_DESTROY_HANDLE_PARAMS parameters{};
      parameters.dwVersion = NVFBC_DESTROY_HANDLE_PARAMS_VER;
      nvfbc.nvFBCDestroyHandle(nvfbc_handle, &parameters);
    }
    if (nvfbc_library != nullptr) {
      dlclose(nvfbc_library);
    }
    if (cuda_module != nullptr && cuda != nullptr) {
      cuda->cuModuleUnload(cuda_module);
    }
    if (cuda_context != nullptr && cuda != nullptr) {
      cuda->cuCtxDestroy(cuda_context);
    }
    cuda_free_functions(&cuda);
  }
};

[[noreturn]] void fail(const std::string& message) {
  throw std::runtime_error(message);
}

unsigned int parse_unsigned(const char* value, const char* name,
                            unsigned int maximum) {
  try {
    const auto parsed = std::stoul(value);
    if (parsed == 0 || parsed > maximum) {
      fail(std::string(name) + " is outside the supported range");
    }
    return static_cast<unsigned int>(parsed);
  } catch (const std::exception&) {
    fail(std::string("invalid ") + name);
  }
}

}  // namespace

int main(int argc, char** argv) {
  std::string output_name = "DP-2";
  unsigned int frame_count = 600;
  unsigned int frame_rate = 60;
  OutputFormat output_format = OutputFormat::kBgra;
  for (int index = 1; index < argc; ++index) {
    const std::string argument = argv[index];
    if (argument == "--output" && index + 1 < argc) {
      output_name = argv[++index];
    } else if (argument == "--frames" && index + 1 < argc) {
      frame_count = parse_unsigned(argv[++index], "frame count", 36000);
    } else if (argument == "--fps" && index + 1 < argc) {
      frame_rate = parse_unsigned(argv[++index], "frame rate", 240);
    } else if (argument == "--format" && index + 1 < argc) {
      const std::string format = argv[++index];
      if (format == "bgra") {
        output_format = OutputFormat::kBgra;
      } else if (format == "gbr-identity8") {
        output_format = OutputFormat::kGbrIdentity8;
      } else if (format == "gbr-identity10") {
        output_format = OutputFormat::kGbrIdentity10;
      } else {
        fail("unsupported output format: " + format);
      }
    } else {
      std::cerr << "usage: " << argv[0]
                << " [--output NAME] [--frames COUNT] [--fps RATE]"
                   " [--format bgra|gbr-identity8|gbr-identity10]\n";
      return 2;
    }
  }

  std::signal(SIGPIPE, SIG_IGN);
  Resources resources;
  try {
    if (cuda_load_functions(&resources.cuda, nullptr) != 0 ||
        resources.cuda->cuInit(0) != CUDA_SUCCESS) {
      fail("CUDA driver initialization failed");
    }
    CUdevice device = 0;
    if (resources.cuda->cuDeviceGet(&device, 0) != CUDA_SUCCESS ||
        resources.cuda->cuCtxCreate(&resources.cuda_context,
                                    CU_CTX_SCHED_BLOCKING_SYNC,
                                    device) != CUDA_SUCCESS) {
      fail("CUDA context creation failed");
    }
    if (output_format != OutputFormat::kBgra) {
      if (resources.cuda->cuModuleLoadData(&resources.cuda_module,
                                           kConversionPtx) != CUDA_SUCCESS) {
        fail("CUDA conversion-module loading failed");
      }
      const char* kernel_name = output_format == OutputFormat::kGbrIdentity8
                                    ? "bgra8_to_gbr8"
                                    : "bgra8_to_gbr10";
      if (resources.cuda->cuModuleGetFunction(&resources.conversion_kernel,
                                              resources.cuda_module,
                                              kernel_name) != CUDA_SUCCESS) {
        fail("CUDA conversion-kernel lookup failed");
      }
    }

    resources.nvfbc_library =
        dlopen("libnvidia-fbc.so.1", RTLD_NOW | RTLD_LOCAL);
    if (resources.nvfbc_library == nullptr) {
      fail(std::string("NvFBC runtime load failed: ") + dlerror());
    }
    const auto create_instance = reinterpret_cast<PNVFBCCREATEINSTANCE>(
        dlsym(resources.nvfbc_library, "NvFBCCreateInstance"));
    if (create_instance == nullptr) {
      fail("NvFBCCreateInstance is unavailable");
    }
    resources.nvfbc.dwVersion = NVFBC_VERSION;
    if (create_instance(&resources.nvfbc) != NVFBC_SUCCESS) {
      fail("NvFBC API initialization failed");
    }

    NVFBC_CREATE_HANDLE_PARAMS handle_parameters{};
    handle_parameters.dwVersion = NVFBC_CREATE_HANDLE_PARAMS_VER;
    handle_parameters.eBackend = NVFBC_BACKEND_X11;
    if (resources.nvfbc.nvFBCCreateHandle(&resources.nvfbc_handle,
                                          &handle_parameters) !=
        NVFBC_SUCCESS) {
      fail("NvFBC handle creation failed");
    }

    NVFBC_GET_STATUS_PARAMS status_parameters{};
    status_parameters.dwVersion = NVFBC_GET_STATUS_PARAMS_VER;
    if (resources.nvfbc.nvFBCGetStatus(resources.nvfbc_handle,
                                       &status_parameters) != NVFBC_SUCCESS ||
        !status_parameters.bCanCreateNow) {
      fail("NvFBC capture is unavailable");
    }

    const NVFBC_RANDR_OUTPUT_INFO* selected_output = nullptr;
    for (std::uint32_t index = 0; index < status_parameters.dwOutputNum;
         ++index) {
      if (output_name == status_parameters.outputs[index].name) {
        selected_output = &status_parameters.outputs[index];
        break;
      }
    }
    if (selected_output == nullptr) {
      fail("NvFBC output not found: " + output_name);
    }

    NVFBC_CREATE_CAPTURE_SESSION_PARAMS capture_parameters{};
    capture_parameters.dwVersion = NVFBC_CREATE_CAPTURE_SESSION_PARAMS_VER;
    capture_parameters.eCaptureType = NVFBC_CAPTURE_SHARED_CUDA;
    capture_parameters.eTrackingType = NVFBC_TRACKING_OUTPUT;
    capture_parameters.dwOutputId = selected_output->dwId;
    capture_parameters.bWithCursor = NVFBC_TRUE;
    capture_parameters.dwSamplingRateMs = 16;
    capture_parameters.bPushModel = NVFBC_FALSE;
    capture_parameters.bAllowDirectCapture = NVFBC_FALSE;
    if (resources.nvfbc.nvFBCCreateCaptureSession(resources.nvfbc_handle,
                                                   &capture_parameters) !=
        NVFBC_SUCCESS) {
      fail("NvFBC capture-session creation failed");
    }
    resources.capture_created = true;

    NVFBC_TOCUDA_SETUP_PARAMS setup_parameters{};
    setup_parameters.dwVersion = NVFBC_TOCUDA_SETUP_PARAMS_VER;
    setup_parameters.eBufferFormat = NVFBC_BUFFER_FORMAT_BGRA;
    if (resources.nvfbc.nvFBCToCudaSetUp(resources.nvfbc_handle,
                                         &setup_parameters) != NVFBC_SUCCESS) {
      fail("NvFBC CUDA setup failed");
    }

    using Clock = std::chrono::steady_clock;
    const auto started = Clock::now();
    const auto frame_period =
        std::chrono::nanoseconds(1'000'000'000LL / frame_rate);
    std::uint32_t width = 0;
    std::uint32_t height = 0;
    std::uint32_t capture_bytes = 0;
    std::size_t output_bytes = 0;
    for (unsigned int frame = 0; frame < frame_count; ++frame) {
      void* device_buffer = nullptr;
      NVFBC_FRAME_GRAB_INFO info{};
      NVFBC_TOCUDA_GRAB_FRAME_PARAMS grab{};
      grab.dwVersion = NVFBC_TOCUDA_GRAB_FRAME_PARAMS_VER;
      grab.dwFlags = NVFBC_TOCUDA_GRAB_FLAGS_NOWAIT |
                     NVFBC_TOCUDA_GRAB_FLAGS_FORCE_REFRESH;
      grab.pFrameGrabInfo = &info;
      grab.pCUDADeviceBuffer = &device_buffer;
      if (resources.nvfbc.nvFBCToCudaGrabFrame(resources.nvfbc_handle,
                                               &grab) != NVFBC_SUCCESS ||
          device_buffer == nullptr || info.dwByteSize == 0) {
        fail("NvFBC frame capture failed");
      }
      if (resources.host_buffer == nullptr) {
        width = info.dwWidth;
        height = info.dwHeight;
        capture_bytes = info.dwByteSize;
        const std::size_t pixel_count =
            static_cast<std::size_t>(width) * height;
        output_bytes = output_format == OutputFormat::kBgra
                           ? capture_bytes
                           : pixel_count *
                                 (output_format == OutputFormat::kGbrIdentity8
                                      ? 3U
                                      : 6U);
        if (output_format != OutputFormat::kBgra &&
            resources.cuda->cuMemAlloc(&resources.converted_buffer,
                                       output_bytes) != CUDA_SUCCESS) {
          fail("CUDA converted-frame allocation failed");
        }
        if (resources.cuda->cuMemHostAlloc(&resources.host_buffer, output_bytes,
                                           0) != CUDA_SUCCESS) {
          fail("CUDA pinned-host allocation failed");
        }
      } else if (info.dwWidth != width || info.dwHeight != height ||
                 info.dwByteSize != capture_bytes) {
        fail("capture geometry changed during the run");
      }
      const auto device_address = static_cast<CUdeviceptr>(
          reinterpret_cast<std::uintptr_t>(device_buffer));
      CUdeviceptr copy_source = device_address;
      if (output_format != OutputFormat::kBgra) {
        const std::uint32_t pixel_count = width * height;
        void* kernel_arguments[] = {&copy_source, &resources.converted_buffer,
                                    const_cast<std::uint32_t*>(&pixel_count)};
        constexpr unsigned int threads = 256;
        const unsigned int blocks = (pixel_count + threads - 1U) / threads;
        if (resources.cuda->cuLaunchKernel(
                resources.conversion_kernel, blocks, 1, 1, threads, 1, 1, 0,
                nullptr, kernel_arguments, nullptr) != CUDA_SUCCESS ||
            resources.cuda->cuCtxSynchronize() != CUDA_SUCCESS) {
          fail("CUDA identity conversion failed");
        }
        copy_source = resources.converted_buffer;
      }
      if (resources.cuda->cuMemcpyDtoH(resources.host_buffer, copy_source,
                                       output_bytes) != CUDA_SUCCESS) {
        fail("CUDA device-to-host copy failed");
      }
      if (std::fwrite(resources.host_buffer, output_bytes, 1, stdout) != 1) {
        fail("raw frame output failed");
      }
      std::this_thread::sleep_until(started + frame_period * (frame + 1));
    }
    std::fflush(stdout);
    const double elapsed =
        std::chrono::duration<double>(Clock::now() - started).count();
    std::cerr << "nvfbc_raw_output=" << output_name << '\n'
              << "nvfbc_raw_geometry=" << width << 'x' << height << '\n'
              << "nvfbc_raw_format=" << output_format_name(output_format)
              << '\n'
              << "nvfbc_raw_bytes_per_frame=" << output_bytes << '\n'
              << "nvfbc_raw_frames=" << frame_count << '\n'
              << "nvfbc_raw_elapsed_seconds=" << elapsed << '\n'
              << "nvfbc_raw_fps=" << frame_count / elapsed << '\n';
  } catch (const std::exception& error) {
    std::cerr << "error=" << error.what() << '\n';
    return 1;
  }
  return 0;
}
