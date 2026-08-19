#include <NvFBC.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <iomanip>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

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

const char* backend_name(NVFBC_BACKEND backend) {
  switch (backend) {
    case NVFBC_BACKEND_X11:
      return "x11";
    case NVFBC_BACKEND_PIPEWIRE:
      return "pipewire";
    case NVFBC_BACKEND_DIRECT:
      return "direct";
    case NVFBC_BACKEND_AUTO:
      return "auto";
  }
  return "unknown";
}

void print_precision_contract() {
  std::cout << "capture_format=BGRA8888\n"
            << "capture_memory=cuda-device\n"
            << "cpu_readback=no\n"
            << "nvfbc_native_10_bit_output=no\n"
            << "precision_gate=8-bit-source-only\n";
}

int self_test() {
  const bool passed = NVFBC_VERSION_MAJOR == 1 && NVFBC_VERSION_MINOR >= 9 &&
                      NVFBC_BUFFER_FORMAT_BGRA != NVFBC_BUFFER_FORMAT_ARGB;
  std::cout << "nvfbc_header_api=" << NVFBC_VERSION_MAJOR << '.'
            << NVFBC_VERSION_MINOR << '\n';
  print_precision_contract();
  std::cout << "nvfbc-probe-self-test=" << (passed ? "pass" : "fail") << '\n';
  return passed ? 0 : 1;
}

void print_error(const NVFBC_API_FUNCTION_LIST& api,
                 NVFBC_SESSION_HANDLE handle, const char* operation,
                 NVFBCSTATUS status) {
  const char* detail = api.nvFBCGetLastErrorStr == nullptr
                           ? ""
                           : api.nvFBCGetLastErrorStr(handle);
  std::cerr << operation << " failed: status=" << status;
  if (detail != nullptr && detail[0] != '\0') {
    std::cerr << " detail=" << detail;
  }
  std::cerr << '\n';
}

}  // namespace

int main(int argc, char** argv) {
  unsigned int frame_count = 120;
  unsigned int target_fps = 60;
  bool status_only = false;
  for (int index = 1; index < argc; ++index) {
    const std::string argument = argv[index];
    if (argument == "--self-test") {
      return self_test();
    }
    if (argument == "--status-only") {
      status_only = true;
      continue;
    }
    if (argument == "--frames" && index + 1 < argc) {
      try {
        frame_count = static_cast<unsigned int>(std::stoul(argv[++index]));
      } catch (const std::exception&) {
        std::cerr << "invalid frame count\n";
        return 2;
      }
      if (frame_count == 0 || frame_count > 600) {
        std::cerr << "frame count must be between 1 and 600\n";
        return 2;
      }
      continue;
    }
    if (argument == "--fps" && index + 1 < argc) {
      try {
        target_fps = static_cast<unsigned int>(std::stoul(argv[++index]));
      } catch (const std::exception&) {
        std::cerr << "invalid target frame rate\n";
        return 2;
      }
      if (target_fps == 0 || target_fps > 240) {
        std::cerr << "target frame rate must be between 1 and 240\n";
        return 2;
      }
      continue;
    }
    std::cerr << "usage: " << argv[0]
              << " [--status-only] [--frames COUNT] [--fps RATE]"
                 " [--self-test]\n";
    return 2;
  }

  int result = 0;
  CudaFunctions* cuda = nullptr;
  CUcontext cuda_context = nullptr;
  void* library = nullptr;
  NVFBC_SESSION_HANDLE handle = 0;
  NVFBC_API_FUNCTION_LIST api{};
  bool capture_created = false;
  std::vector<std::int64_t> capture_times_us;

  if (cuda_load_functions(&cuda, nullptr) != 0 ||
      cuda->cuInit(0) != CUDA_SUCCESS) {
    std::cerr << "CUDA driver initialization failed\n";
    result = 3;
    goto cleanup;
  }

  {
    CUdevice device = 0;
    char device_name[128]{};
    if (cuda->cuDeviceGet(&device, 0) != CUDA_SUCCESS ||
        cuda->cuDeviceGetName(device_name, sizeof(device_name), device) !=
            CUDA_SUCCESS ||
        cuda->cuCtxCreate(&cuda_context, CU_CTX_SCHED_BLOCKING_SYNC, device) !=
            CUDA_SUCCESS) {
      std::cerr << "CUDA device/context creation failed\n";
      result = 4;
      goto cleanup;
    }
    std::cout << "cuda_device=" << device_name << '\n';
  }

  library = dlopen("libnvidia-fbc.so.1", RTLD_NOW | RTLD_LOCAL);
  if (library == nullptr) {
    std::cerr << "NvFBC runtime load failed: " << dlerror() << '\n';
    result = 5;
    goto cleanup;
  }

  {
    const auto create_instance = reinterpret_cast<PNVFBCCREATEINSTANCE>(
        dlsym(library, "NvFBCCreateInstance"));
    if (create_instance == nullptr) {
      std::cerr << "NvFBCCreateInstance symbol is unavailable\n";
      result = 6;
      goto cleanup;
    }
    api.dwVersion = NVFBC_VERSION;
    const NVFBCSTATUS status = create_instance(&api);
    if (status != NVFBC_SUCCESS) {
      std::cerr << "NvFBC API initialization failed: status=" << status << '\n';
      result = 7;
      goto cleanup;
    }
  }

  {
    NVFBC_CREATE_HANDLE_PARAMS parameters{};
    parameters.dwVersion = NVFBC_CREATE_HANDLE_PARAMS_VER;
    parameters.eBackend = NVFBC_BACKEND_X11;
    const NVFBCSTATUS status = api.nvFBCCreateHandle(&handle, &parameters);
    if (status != NVFBC_SUCCESS) {
      print_error(api, handle, "NvFBCCreateHandle", status);
      result = 8;
      goto cleanup;
    }
    std::cout << "backend=" << backend_name(parameters.eBackend) << '\n';
  }

  {
    NVFBC_GET_STATUS_PARAMS parameters{};
    parameters.dwVersion = NVFBC_GET_STATUS_PARAMS_VER;
    const NVFBCSTATUS status = api.nvFBCGetStatus(handle, &parameters);
    if (status != NVFBC_SUCCESS) {
      print_error(api, handle, "NvFBCGetStatus", status);
      result = 9;
      goto cleanup;
    }
    std::cout << "nvfbc_runtime_api=" << (parameters.dwNvFBCVersion >> 8U)
              << '.' << (parameters.dwNvFBCVersion & 0xffU) << '\n'
              << "capture_possible="
              << (parameters.bIsCapturePossible ? "yes" : "no") << '\n'
              << "capture_available_now="
              << (parameters.bCanCreateNow ? "yes" : "no") << '\n'
              << "screen=" << parameters.screenSize.w << 'x'
              << parameters.screenSize.h << '\n'
              << "xrandr=" << (parameters.bXRandRAvailable ? "yes" : "no")
              << '\n'
              << "outputs=" << parameters.dwOutputNum << '\n';
    for (std::uint32_t index = 0; index < parameters.dwOutputNum; ++index) {
      const NVFBC_RANDR_OUTPUT_INFO& output = parameters.outputs[index];
      std::cout << "  output=" << output.name << " id=" << output.dwId
                << " geometry=" << output.trackedBox.w << 'x'
                << output.trackedBox.h << '+' << output.trackedBox.x << '+'
                << output.trackedBox.y << '\n';
    }
    print_precision_contract();
    if (!parameters.bIsCapturePossible || !parameters.bCanCreateNow) {
      result = 10;
      goto cleanup;
    }
  }

  if (status_only) {
    goto cleanup;
  }

  {
    NVFBC_CREATE_CAPTURE_SESSION_PARAMS parameters{};
    parameters.dwVersion = NVFBC_CREATE_CAPTURE_SESSION_PARAMS_VER;
    parameters.eCaptureType = NVFBC_CAPTURE_SHARED_CUDA;
    parameters.eTrackingType = NVFBC_TRACKING_SCREEN;
    parameters.bWithCursor = NVFBC_TRUE;
    parameters.dwSamplingRateMs = 16;
    parameters.bPushModel = NVFBC_FALSE;
    parameters.bAllowDirectCapture = NVFBC_FALSE;
    const NVFBCSTATUS status = api.nvFBCCreateCaptureSession(handle, &parameters);
    if (status != NVFBC_SUCCESS) {
      print_error(api, handle, "NvFBCCreateCaptureSession", status);
      result = 11;
      goto cleanup;
    }
    capture_created = true;
  }

  {
    NVFBC_TOCUDA_SETUP_PARAMS parameters{};
    parameters.dwVersion = NVFBC_TOCUDA_SETUP_PARAMS_VER;
    parameters.eBufferFormat = NVFBC_BUFFER_FORMAT_BGRA;
    const NVFBCSTATUS status = api.nvFBCToCudaSetUp(handle, &parameters);
    if (status != NVFBC_SUCCESS) {
      print_error(api, handle, "NvFBCToCudaSetUp", status);
      result = 12;
      goto cleanup;
    }
  }

  {
    using Clock = std::chrono::steady_clock;
    const auto run_started = Clock::now();
    const auto frame_period =
        std::chrono::nanoseconds(1'000'000'000LL / target_fps);
    unsigned int deadline_misses = 0;
    std::uint64_t driver_missed_frames = 0;
    unsigned int new_frames = 0;
    NVFBC_FRAME_GRAB_INFO last_info{};
    capture_times_us.reserve(frame_count);

    for (unsigned int frame = 0; frame < frame_count; ++frame) {
      void* cuda_buffer = nullptr;
      NVFBC_FRAME_GRAB_INFO info{};
      NVFBC_TOCUDA_GRAB_FRAME_PARAMS parameters{};
      parameters.dwVersion = NVFBC_TOCUDA_GRAB_FRAME_PARAMS_VER;
      parameters.dwFlags = NVFBC_TOCUDA_GRAB_FLAGS_NOWAIT |
                           NVFBC_TOCUDA_GRAB_FLAGS_FORCE_REFRESH;
      parameters.pFrameGrabInfo = &info;
      parameters.pCUDADeviceBuffer = &cuda_buffer;
      const auto capture_started = Clock::now();
      const NVFBCSTATUS status = api.nvFBCToCudaGrabFrame(handle, &parameters);
      const auto capture_finished = Clock::now();
      const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
          capture_finished - capture_started);
      if (status != NVFBC_SUCCESS) {
        print_error(api, handle, "NvFBCToCudaGrabFrame", status);
        result = 13;
        goto cleanup;
      }
      if (cuda_buffer == nullptr || info.dwWidth == 0 || info.dwHeight == 0) {
        std::cerr << "NvFBC returned an invalid CUDA frame\n";
        result = 14;
        goto cleanup;
      }
      capture_times_us.push_back(elapsed.count());
      new_frames += info.bIsNewFrame ? 1U : 0U;
      driver_missed_frames += info.dwMissedFrames;
      last_info = info;

      const auto deadline = run_started + frame_period * (frame + 1);
      if (capture_finished > deadline) {
        ++deadline_misses;
      }
      std::this_thread::sleep_until(deadline);
    }

    const auto run_finished = Clock::now();
    const double elapsed_seconds =
        std::chrono::duration<double>(run_finished - run_started).count();
    const double achieved_fps = frame_count / elapsed_seconds;
    std::sort(capture_times_us.begin(), capture_times_us.end());
    std::int64_t total_capture_us = 0;
    for (const std::int64_t value : capture_times_us) {
      total_capture_us += value;
    }
    const std::size_t p95_index =
        ((capture_times_us.size() * 95U + 99U) / 100U) - 1U;
    const std::int64_t frame_budget_us = 1'000'000LL / target_fps;
    const double average_capture_us =
        static_cast<double>(total_capture_us) / capture_times_us.size();
    const unsigned int allowed_deadline_misses =
        std::max(1U, frame_count / 100U);
    const bool performance_pass =
        achieved_fps >= static_cast<double>(target_fps) * 0.99 &&
        capture_times_us[p95_index] <= frame_budget_us &&
        deadline_misses <= allowed_deadline_misses;

    std::cout << "frame_geometry=" << last_info.dwWidth << 'x'
              << last_info.dwHeight << '\n'
              << "frame_bytes=" << last_info.dwByteSize << '\n'
              << "cursor="
              << (last_info.bCursorComposited ? "composited" : "not-composited")
              << '\n'
              << "capture_calls=" << frame_count << '\n'
              << "new_frames_observed=" << new_frames << '\n'
              << "cadence_scope=forced-refresh-capture-calls\n"
              << "content_rate=desktop-damage-dependent\n"
              << "driver_missed_frames=" << driver_missed_frames << '\n'
              << "target_fps=" << target_fps << '\n'
              << std::fixed << std::setprecision(2)
              << "achieved_fps=" << achieved_fps << '\n'
              << "capture_us_average=" << average_capture_us << '\n'
              << "capture_us_p95=" << capture_times_us[p95_index] << '\n'
              << "capture_us_max=" << capture_times_us.back() << '\n'
              << "frame_budget_us=" << frame_budget_us << '\n'
              << "deadline_misses=" << deadline_misses << '\n'
              << "nvfbc_60fps_gate="
              << (performance_pass ? "pass" : "fail") << '\n';
    if (!performance_pass) {
      result = 15;
      goto cleanup;
    }
  }
  std::cout << "nvfbc_cuda_capture=pass\n";

cleanup:
  if (capture_created && api.nvFBCDestroyCaptureSession != nullptr) {
    NVFBC_DESTROY_CAPTURE_SESSION_PARAMS parameters{};
    parameters.dwVersion = NVFBC_DESTROY_CAPTURE_SESSION_PARAMS_VER;
    api.nvFBCDestroyCaptureSession(handle, &parameters);
  }
  if (handle != 0 && api.nvFBCDestroyHandle != nullptr) {
    NVFBC_DESTROY_HANDLE_PARAMS parameters{};
    parameters.dwVersion = NVFBC_DESTROY_HANDLE_PARAMS_VER;
    api.nvFBCDestroyHandle(handle, &parameters);
  }
  if (library != nullptr) {
    dlclose(library);
  }
  if (cuda_context != nullptr && cuda != nullptr) {
    cuda->cuCtxDestroy(cuda_context);
  }
  cuda_free_functions(&cuda);
  return result;
}
