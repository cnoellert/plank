#include <NvFBC.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <deque>
#include <exception>
#include <mutex>
#include <numeric>
#include <stdexcept>
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

constexpr std::uint32_t kBitrate = 80'000'000;

constexpr char kIdentityKernelPtx[] = R"ptx(
.version 6.4
.target sm_50
.address_size 64

.visible .entry bgra8_to_gbr10(
    .param .u64 source_ptr,
    .param .u64 destination_ptr,
    .param .u32 width,
    .param .u32 height,
    .param .u64 destination_pitch)
{
    .reg .pred %p<5>;
    .reg .b32 %r<28>;
    .reg .b64 %rd<16>;

    ld.param.u64 %rd1, [source_ptr];
    ld.param.u64 %rd2, [destination_ptr];
    ld.param.u32 %r1, [width];
    ld.param.u32 %r2, [height];
    ld.param.u64 %rd3, [destination_pitch];

    mov.u32 %r3, %ctaid.x;
    mov.u32 %r4, %ntid.x;
    mov.u32 %r5, %tid.x;
    mad.lo.u32 %r6, %r3, %r4, %r5;
    mul.lo.u32 %r7, %r1, %r2;
    setp.ge.u32 %p1, %r6, %r7;
    @%p1 bra done;

    mul.wide.u32 %rd4, %r6, 4;
    add.u64 %rd5, %rd1, %rd4;
    ld.global.u8 %r8, [%rd5];
    ld.global.u8 %r9, [%rd5+1];
    ld.global.u8 %r10, [%rd5+2];

    shl.b32 %r11, %r8, 2;
    setp.ge.u32 %p2, %r8, 43;
    selp.u32 %r14, 1, 0, %p2;
    add.u32 %r11, %r11, %r14;
    setp.ge.u32 %p3, %r8, 128;
    selp.u32 %r15, 1, 0, %p3;
    add.u32 %r11, %r11, %r15;
    setp.ge.u32 %p4, %r8, 213;
    selp.u32 %r16, 1, 0, %p4;
    add.u32 %r11, %r11, %r16;
    shl.b32 %r11, %r11, 6;

    shl.b32 %r12, %r9, 2;
    setp.ge.u32 %p2, %r9, 43;
    selp.u32 %r14, 1, 0, %p2;
    add.u32 %r12, %r12, %r14;
    setp.ge.u32 %p3, %r9, 128;
    selp.u32 %r15, 1, 0, %p3;
    add.u32 %r12, %r12, %r15;
    setp.ge.u32 %p4, %r9, 213;
    selp.u32 %r16, 1, 0, %p4;
    add.u32 %r12, %r12, %r16;
    shl.b32 %r12, %r12, 6;

    shl.b32 %r13, %r10, 2;
    setp.ge.u32 %p2, %r10, 43;
    selp.u32 %r14, 1, 0, %p2;
    add.u32 %r13, %r13, %r14;
    setp.ge.u32 %p3, %r10, 128;
    selp.u32 %r15, 1, 0, %p3;
    add.u32 %r13, %r13, %r15;
    setp.ge.u32 %p4, %r10, 213;
    selp.u32 %r16, 1, 0, %p4;
    add.u32 %r13, %r13, %r16;
    shl.b32 %r13, %r13, 6;

    mul.wide.u32 %rd6, %r6, 2;
    cvt.u64.u32 %rd7, %r2;
    mul.lo.u64 %rd8, %rd3, %rd7;

    add.u64 %rd9, %rd2, %rd6;
    st.global.u16 [%rd9], %r12;
    add.u64 %rd10, %rd9, %rd8;
    st.global.u16 [%rd10], %r11;
    add.u64 %rd11, %rd10, %rd8;
    st.global.u16 [%rd11], %r13;

done:
    ret;
}
)ptx";

std::uint16_t expand_to_msb_aligned_10_bit(std::uint8_t value) {
  const std::uint32_t expanded =
      (static_cast<std::uint32_t>(value) * 1023U + 127U) / 255U;
  return static_cast<std::uint16_t>(expanded << 6U);
}

template <typename Value>
double percentile(std::vector<Value> values, unsigned int percent) {
  if (values.empty()) {
    return 0.0;
  }
  std::sort(values.begin(), values.end());
  const std::size_t index =
      ((values.size() * percent + 99U) / 100U) - 1U;
  return static_cast<double>(values[index]);
}

template <typename Value>
double average(const std::vector<Value>& values) {
  if (values.empty()) {
    return 0.0;
  }
  const auto sum = std::accumulate(values.begin(), values.end(),
                                   static_cast<Value>(0));
  return static_cast<double>(sum) / static_cast<double>(values.size());
}

std::string cuda_error(CudaFunctions* cuda, CUresult status) {
  const char* name = nullptr;
  const char* description = nullptr;
  if (cuda != nullptr) {
    cuda->cuGetErrorName(status, &name);
    cuda->cuGetErrorString(status, &description);
  }
  return std::string(name == nullptr ? "CUDA_ERROR" : name) + ": " +
         (description == nullptr ? "unknown" : description);
}

void require_cuda(CudaFunctions* cuda, CUresult status,
                  const char* operation) {
  if (status != CUDA_SUCCESS) {
    throw std::runtime_error(std::string(operation) + " failed: " +
                             cuda_error(cuda, status));
  }
}

void require_nvenc(NVENCSTATUS status, const char* operation) {
  if (status != NV_ENC_SUCCESS) {
    throw std::runtime_error(std::string(operation) +
                             " failed: status=" + std::to_string(status));
  }
}

struct Resources {
  struct EncodeSlot {
    CUdeviceptr surface = 0;
    std::size_t pitch = 0;
    NV_ENC_REGISTERED_PTR registered = nullptr;
    NV_ENC_INPUT_PTR mapped = nullptr;
    NV_ENC_OUTPUT_PTR bitstream = nullptr;
    bool bitstream_locked = false;
  };

  CudaFunctions* cuda = nullptr;
  NvencFunctions* nvenc_loader = nullptr;
  CUcontext cuda_context = nullptr;
  CUstream conversion_stream = nullptr;
  CUmodule cuda_module = nullptr;
  CUfunction conversion_kernel = nullptr;
  std::array<EncodeSlot, 2> encode_slots{};

  void* nvfbc_library = nullptr;
  NVFBC_API_FUNCTION_LIST nvfbc{};
  NVFBC_SESSION_HANDLE nvfbc_handle = 0;
  bool nvfbc_capture_created = false;

  NV_ENCODE_API_FUNCTION_LIST nvenc{};
  void* encoder = nullptr;

  ~Resources() {
    for (EncodeSlot& slot : encode_slots) {
      if (slot.bitstream_locked && encoder != nullptr) {
        nvenc.nvEncUnlockBitstream(encoder, slot.bitstream);
      }
      if (slot.mapped != nullptr && encoder != nullptr) {
        nvenc.nvEncUnmapInputResource(encoder, slot.mapped);
      }
      if (slot.bitstream != nullptr && encoder != nullptr) {
        nvenc.nvEncDestroyBitstreamBuffer(encoder, slot.bitstream);
      }
      if (slot.registered != nullptr && encoder != nullptr) {
        nvenc.nvEncUnregisterResource(encoder, slot.registered);
      }
    }
    if (encoder != nullptr) {
      nvenc.nvEncDestroyEncoder(encoder);
    }
    nvenc_free_functions(&nvenc_loader);

    if (nvfbc_capture_created && nvfbc.nvFBCDestroyCaptureSession != nullptr) {
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

    for (EncodeSlot& slot : encode_slots) {
      if (slot.surface != 0 && cuda != nullptr) {
        cuda->cuMemFree(slot.surface);
      }
    }
    if (conversion_stream != nullptr && cuda != nullptr) {
      cuda->cuStreamDestroy(conversion_stream);
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

void initialize_cuda(Resources& resources) {
  if (cuda_load_functions(&resources.cuda, nullptr) != 0) {
    throw std::runtime_error("CUDA driver loading failed");
  }
  require_cuda(resources.cuda, resources.cuda->cuInit(0), "cuInit");
  CUdevice device = 0;
  require_cuda(resources.cuda, resources.cuda->cuDeviceGet(&device, 0),
               "cuDeviceGet");
  char device_name[128]{};
  require_cuda(resources.cuda,
               resources.cuda->cuDeviceGetName(device_name, sizeof(device_name),
                                                device),
               "cuDeviceGetName");
  require_cuda(resources.cuda,
               resources.cuda->cuCtxCreate(&resources.cuda_context,
                                           CU_CTX_SCHED_BLOCKING_SYNC, device),
               "cuCtxCreate");
  int least_priority = 0;
  int greatest_priority = 0;
  require_cuda(resources.cuda,
               resources.cuda->cuCtxGetStreamPriorityRange(&least_priority,
                                                           &greatest_priority),
               "cuCtxGetStreamPriorityRange");
  require_cuda(resources.cuda,
               resources.cuda->cuStreamCreateWithPriority(
                   &resources.conversion_stream, CU_STREAM_NON_BLOCKING,
                   greatest_priority),
               "cuStreamCreateWithPriority");
  require_cuda(resources.cuda,
               resources.cuda->cuModuleLoadData(&resources.cuda_module,
                                                kIdentityKernelPtx),
               "cuModuleLoadData");
  require_cuda(resources.cuda,
               resources.cuda->cuModuleGetFunction(&resources.conversion_kernel,
                                                   resources.cuda_module,
                                                   "bgra8_to_gbr10"),
               "cuModuleGetFunction");
  std::cout << "cuda_device=" << device_name << '\n';
}

void launch_conversion(Resources& resources, CUdeviceptr source,
                       CUdeviceptr destination, std::uint32_t width,
                       std::uint32_t height, std::uint64_t pitch) {
  void* parameters[] = {&source, &destination, &width, &height, &pitch};
  const std::uint64_t pixels =
      static_cast<std::uint64_t>(width) * static_cast<std::uint64_t>(height);
  const unsigned int threads = 256;
  const unsigned int blocks =
      static_cast<unsigned int>((pixels + threads - 1U) / threads);
  require_cuda(resources.cuda,
               resources.cuda->cuLaunchKernel(
                   resources.conversion_kernel, blocks, 1, 1, threads, 1, 1, 0,
                   resources.conversion_stream, parameters, nullptr),
               "cuLaunchKernel");
  require_cuda(resources.cuda,
               resources.cuda->cuStreamSynchronize(resources.conversion_stream),
               "cuStreamSynchronize");
}

void self_test_conversion(Resources& resources) {
  constexpr std::uint32_t width = 4;
  constexpr std::uint32_t height = 1;
  constexpr std::uint64_t pitch = width * sizeof(std::uint16_t);
  const std::uint8_t source[] = {
      0, 0, 0, 255, 255, 255, 255, 255,
      255, 0, 0, 255, 0, 128, 255, 255,
  };
  CUdeviceptr device_source = 0;
  CUdeviceptr device_destination = 0;
  require_cuda(resources.cuda,
               resources.cuda->cuMemAlloc(&device_source, sizeof(source)),
               "cuMemAlloc(test source)");
  require_cuda(resources.cuda,
               resources.cuda->cuMemAlloc(&device_destination,
                                          pitch * height * 3U),
               "cuMemAlloc(test destination)");
  try {
    require_cuda(resources.cuda,
                 resources.cuda->cuMemcpyHtoD(device_source, source,
                                              sizeof(source)),
                 "cuMemcpyHtoD(test)");
    launch_conversion(resources, device_source, device_destination, width, height,
                      pitch);
    std::uint16_t result[width * 3U]{};
    require_cuda(resources.cuda,
                 resources.cuda->cuMemcpyDtoH(result, device_destination,
                                              sizeof(result)),
                 "cuMemcpyDtoH(test)");
    const std::uint16_t maximum = expand_to_msb_aligned_10_bit(255);
    const std::uint16_t midpoint = expand_to_msb_aligned_10_bit(128);
    const std::uint16_t expected[] = {
        0, maximum, 0, midpoint,
        0, maximum, maximum, 0,
        0, maximum, 0, maximum,
    };
    if (!std::equal(std::begin(result), std::end(result),
                    std::begin(expected))) {
      throw std::runtime_error("identity GBR CUDA pixel self-test failed");
    }
  } catch (...) {
    resources.cuda->cuMemFree(device_destination);
    resources.cuda->cuMemFree(device_source);
    throw;
  }
  resources.cuda->cuMemFree(device_destination);
  resources.cuda->cuMemFree(device_source);
  std::cout << "identity_gbr_pixel_self_test=pass\n";
}

NVFBC_RANDR_OUTPUT_INFO initialize_nvfbc(Resources& resources,
                                         const std::string& output_name) {
  resources.nvfbc_library =
      dlopen("libnvidia-fbc.so.1", RTLD_NOW | RTLD_LOCAL);
  if (resources.nvfbc_library == nullptr) {
    throw std::runtime_error(std::string("NvFBC runtime load failed: ") +
                             dlerror());
  }
  const auto create_instance = reinterpret_cast<PNVFBCCREATEINSTANCE>(
      dlsym(resources.nvfbc_library, "NvFBCCreateInstance"));
  if (create_instance == nullptr) {
    throw std::runtime_error("NvFBCCreateInstance symbol is unavailable");
  }
  resources.nvfbc.dwVersion = NVFBC_VERSION;
  if (create_instance(&resources.nvfbc) != NVFBC_SUCCESS) {
    throw std::runtime_error("NvFBC API initialization failed");
  }
  NVFBC_CREATE_HANDLE_PARAMS handle_parameters{};
  handle_parameters.dwVersion = NVFBC_CREATE_HANDLE_PARAMS_VER;
  handle_parameters.eBackend = NVFBC_BACKEND_X11;
  NVFBCSTATUS status = resources.nvfbc.nvFBCCreateHandle(
      &resources.nvfbc_handle, &handle_parameters);
  if (status != NVFBC_SUCCESS) {
    throw std::runtime_error("NvFBCCreateHandle failed: status=" +
                             std::to_string(status));
  }

  NVFBC_GET_STATUS_PARAMS status_parameters{};
  status_parameters.dwVersion = NVFBC_GET_STATUS_PARAMS_VER;
  status = resources.nvfbc.nvFBCGetStatus(resources.nvfbc_handle,
                                          &status_parameters);
  if (status != NVFBC_SUCCESS || !status_parameters.bCanCreateNow) {
    throw std::runtime_error("NvFBC capture is unavailable");
  }
  for (std::uint32_t index = 0; index < status_parameters.dwOutputNum; ++index) {
    const NVFBC_RANDR_OUTPUT_INFO& output = status_parameters.outputs[index];
    if (output_name == output.name) {
      NVFBC_CREATE_CAPTURE_SESSION_PARAMS capture_parameters{};
      capture_parameters.dwVersion =
          NVFBC_CREATE_CAPTURE_SESSION_PARAMS_VER;
      capture_parameters.eCaptureType = NVFBC_CAPTURE_SHARED_CUDA;
      capture_parameters.eTrackingType = NVFBC_TRACKING_OUTPUT;
      capture_parameters.dwOutputId = output.dwId;
      capture_parameters.bWithCursor = NVFBC_TRUE;
      capture_parameters.dwSamplingRateMs = 16;
      capture_parameters.bPushModel = NVFBC_FALSE;
      capture_parameters.bAllowDirectCapture = NVFBC_FALSE;
      status = resources.nvfbc.nvFBCCreateCaptureSession(
          resources.nvfbc_handle, &capture_parameters);
      if (status != NVFBC_SUCCESS) {
        throw std::runtime_error("NvFBCCreateCaptureSession failed: status=" +
                                 std::to_string(status));
      }
      resources.nvfbc_capture_created = true;

      NVFBC_TOCUDA_SETUP_PARAMS setup_parameters{};
      setup_parameters.dwVersion = NVFBC_TOCUDA_SETUP_PARAMS_VER;
      setup_parameters.eBufferFormat = NVFBC_BUFFER_FORMAT_BGRA;
      status = resources.nvfbc.nvFBCToCudaSetUp(resources.nvfbc_handle,
                                                &setup_parameters);
      if (status != NVFBC_SUCCESS) {
        throw std::runtime_error("NvFBCToCudaSetUp failed: status=" +
                                 std::to_string(status));
      }
      return output;
    }
  }
  throw std::runtime_error("NvFBC output not found: " + output_name);
}

void initialize_nvenc(Resources& resources, std::uint32_t width,
                      std::uint32_t height, std::uint32_t frame_rate,
                      NV_ENC_SPLIT_ENCODE_MODE split_mode,
                      NV_ENC_TUNING_INFO tuning,
                      std::uint32_t intra_refresh_period,
                      bool single_slice_intra_refresh,
                      std::uint32_t intra_refresh_count,
                      std::uint32_t reference_frames) {
  if (nvenc_load_functions(&resources.nvenc_loader, nullptr) != 0) {
    throw std::runtime_error("NVENC loader initialization failed");
  }
  resources.nvenc = {};
  resources.nvenc.version = NV_ENCODE_API_FUNCTION_LIST_VER;
  require_nvenc(resources.nvenc_loader->NvEncodeAPICreateInstance(
                     &resources.nvenc),
                 "NvEncodeAPICreateInstance");

  NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS open_parameters{};
  open_parameters.version = NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS_VER;
  open_parameters.deviceType = NV_ENC_DEVICE_TYPE_CUDA;
  open_parameters.device = resources.cuda_context;
  open_parameters.apiVersion = NVENCAPI_VERSION;
  require_nvenc(resources.nvenc.nvEncOpenEncodeSessionEx(
                     &open_parameters, &resources.encoder),
                 "nvEncOpenEncodeSessionEx");

  NV_ENC_PRESET_CONFIG preset{};
  preset.version = NV_ENC_PRESET_CONFIG_VER;
  preset.presetCfg.version = NV_ENC_CONFIG_VER;
  require_nvenc(resources.nvenc.nvEncGetEncodePresetConfigEx(
                     resources.encoder, NV_ENC_CODEC_HEVC_GUID,
                     NV_ENC_PRESET_P1_GUID, tuning,
                     &preset),
                 "nvEncGetEncodePresetConfigEx");

  NV_ENC_CONFIG config = preset.presetCfg;
  config.version = NV_ENC_CONFIG_VER;
  config.profileGUID = NV_ENC_HEVC_PROFILE_FREXT_GUID;
  config.gopLength = NVENC_INFINITE_GOPLENGTH;
  config.frameIntervalP = 1;
  config.rcParams.rateControlMode = NV_ENC_PARAMS_RC_CBR;
  config.rcParams.averageBitRate = kBitrate;
  config.rcParams.maxBitRate = kBitrate;
  config.rcParams.vbvBufferSize = kBitrate / frame_rate;
  config.rcParams.vbvInitialDelay = config.rcParams.vbvBufferSize;
  config.rcParams.enableLookahead = 0;
  config.rcParams.zeroReorderDelay = 1;
  config.rcParams.multiPass = NV_ENC_MULTI_PASS_DISABLED;

  NV_ENC_CONFIG_HEVC& hevc = config.encodeCodecConfig.hevcConfig;
  hevc.chromaFormatIDC = 3;
  hevc.inputBitDepth = NV_ENC_BIT_DEPTH_10;
  hevc.outputBitDepth = NV_ENC_BIT_DEPTH_10;
  hevc.idrPeriod = NVENC_INFINITE_GOPLENGTH;
  hevc.enableIntraRefresh = intra_refresh_count > 0 ? 1U : 0U;
  hevc.intraRefreshPeriod = intra_refresh_period;
  hevc.intraRefreshCnt = intra_refresh_count;
  hevc.singleSliceIntraRefresh =
      intra_refresh_count > 0 && single_slice_intra_refresh ? 1U : 0U;
  hevc.maxNumRefFramesInDPB = reference_frames;
  hevc.repeatSPSPPS = 1;
  hevc.hevcVUIParameters.videoSignalTypePresentFlag = 1;
  hevc.hevcVUIParameters.videoFormat = NV_ENC_VUI_VIDEO_FORMAT_COMPONENT;
  hevc.hevcVUIParameters.videoFullRangeFlag = 1;
  hevc.hevcVUIParameters.colourDescriptionPresentFlag = 1;
  hevc.hevcVUIParameters.colourPrimaries = NV_ENC_VUI_COLOR_PRIMARIES_BT709;
  hevc.hevcVUIParameters.transferCharacteristics =
      NV_ENC_VUI_TRANSFER_CHARACTERISTIC_SRGB;
  hevc.hevcVUIParameters.colourMatrix = NV_ENC_VUI_MATRIX_COEFFS_RGB;

  NV_ENC_INITIALIZE_PARAMS initialize{};
  initialize.version = NV_ENC_INITIALIZE_PARAMS_VER;
  initialize.encodeGUID = NV_ENC_CODEC_HEVC_GUID;
  initialize.presetGUID = NV_ENC_PRESET_P1_GUID;
  initialize.encodeWidth = width;
  initialize.encodeHeight = height;
  initialize.darWidth = width;
  initialize.darHeight = height;
  initialize.frameRateNum = frame_rate;
  initialize.frameRateDen = 1;
  initialize.enablePTD = 1;
  initialize.tuningInfo = tuning;
  initialize.splitEncodeMode = split_mode;
  initialize.maxEncodeWidth = width;
  initialize.maxEncodeHeight = height;
  initialize.encodeConfig = &config;
  require_nvenc(resources.nvenc.nvEncInitializeEncoder(resources.encoder,
                                                       &initialize),
                 "nvEncInitializeEncoder");

  for (Resources::EncodeSlot& slot : resources.encode_slots) {
    require_cuda(resources.cuda,
                 resources.cuda->cuMemAllocPitch(
                     &slot.surface, &slot.pitch,
                     static_cast<std::size_t>(width) * sizeof(std::uint16_t),
                     static_cast<std::size_t>(height) * 3U, 16),
                 "cuMemAllocPitch(encoder surface)");

    NV_ENC_REGISTER_RESOURCE registration{};
    registration.version = NV_ENC_REGISTER_RESOURCE_VER;
    registration.resourceType = NV_ENC_INPUT_RESOURCE_TYPE_CUDADEVICEPTR;
    registration.resourceToRegister = reinterpret_cast<void*>(
        static_cast<std::uintptr_t>(slot.surface));
    registration.width = width;
    registration.height = height;
    registration.pitch = static_cast<std::uint32_t>(slot.pitch);
    registration.bufferFormat = NV_ENC_BUFFER_FORMAT_YUV444_10BIT;
    registration.bufferUsage = NV_ENC_INPUT_IMAGE;
    require_nvenc(resources.nvenc.nvEncRegisterResource(resources.encoder,
                                                         &registration),
                   "nvEncRegisterResource");
    slot.registered = registration.registeredResource;

    NV_ENC_CREATE_BITSTREAM_BUFFER create_bitstream{};
    create_bitstream.version = NV_ENC_CREATE_BITSTREAM_BUFFER_VER;
    require_nvenc(resources.nvenc.nvEncCreateBitstreamBuffer(
                       resources.encoder, &create_bitstream),
                   "nvEncCreateBitstreamBuffer");
    slot.bitstream = create_bitstream.bitstreamBuffer;
  }
}

int self_test() {
  const bool passed = expand_to_msb_aligned_10_bit(0) == 0 &&
                      expand_to_msb_aligned_10_bit(128) == 32896 &&
                      expand_to_msb_aligned_10_bit(255) == 65472;
  std::cout << "identity_mapping=Y:G,U:B,V:R\n"
            << "identity_zero=" << expand_to_msb_aligned_10_bit(0) << '\n'
            << "identity_mid=" << expand_to_msb_aligned_10_bit(128) << '\n'
            << "identity_max=" << expand_to_msb_aligned_10_bit(255) << '\n'
            << "video-pipeline-self-test=" << (passed ? "pass" : "fail")
            << '\n';
  return passed ? 0 : 1;
}

}  // namespace

int main(int argc, char** argv) {
  unsigned int frame_count = 600;
  unsigned int frame_rate = 60;
  unsigned int queue_depth = 1;
  unsigned int simulate_loss_frame = 0;
  unsigned int invalidate_delay_frames = 2;
  unsigned int force_idr_frame = 0;
  unsigned int reference_frames = 0;
  bool reference_invalidation_enabled = true;
  int intra_refresh_period = -1;
  int intra_refresh_count = -1;
  bool single_slice_intra_refresh = true;
  bool require_changing_source = false;
  bool require_robustness = false;
  std::string output_name = "DP-2";
  std::string bitstream_path = "stationconnect-identity-gbr.hevc";
  NV_ENC_SPLIT_ENCODE_MODE split_mode = NV_ENC_SPLIT_AUTO_MODE;
  std::string split_mode_name = "auto";
  NV_ENC_TUNING_INFO tuning = NV_ENC_TUNING_INFO_LOW_LATENCY;
  std::string tuning_name = "low-latency";
  for (int index = 1; index < argc; ++index) {
    const std::string argument = argv[index];
    if (argument == "--self-test") {
      return self_test();
    }
    if (argument == "--require-changing") {
      require_changing_source = true;
      continue;
    }
    if (argument == "--require-robustness") {
      require_robustness = true;
      continue;
    }
    if (argument == "--no-reference-invalidation") {
      reference_invalidation_enabled = false;
      continue;
    }
    if (argument == "--queue-depth" && index + 1 < argc) {
      const std::string value = argv[++index];
      if (value != "0" && value != "1") {
        std::cerr << "queue depth must be 0 or 1\n";
        return 2;
      }
      queue_depth = static_cast<unsigned int>(value[0] - '0');
      continue;
    }
    if (argument == "--intra-refresh-count" && index + 1 < argc) {
      try {
        intra_refresh_count = std::stoi(argv[++index]);
      } catch (const std::exception&) {
        std::cerr << "invalid intra-refresh count\n";
        return 2;
      }
      if (intra_refresh_count < 0 || intra_refresh_count > 36000) {
        std::cerr << "intra-refresh count is outside the supported range\n";
        return 2;
      }
      continue;
    }
    if (argument == "--intra-refresh-period" && index + 1 < argc) {
      try {
        intra_refresh_period = std::stoi(argv[++index]);
      } catch (const std::exception&) {
        std::cerr << "invalid intra-refresh period\n";
        return 2;
      }
      if (intra_refresh_period <= 0 || intra_refresh_period > 36000) {
        std::cerr << "intra-refresh period is outside the supported range\n";
        return 2;
      }
      continue;
    }
    if (argument == "--single-slice-intra-refresh" && index + 1 < argc) {
      const std::string value = argv[++index];
      if (value != "0" && value != "1") {
        std::cerr << "single-slice intra-refresh must be 0 or 1\n";
        return 2;
      }
      single_slice_intra_refresh = value == "1";
      continue;
    }
    if ((argument == "--frames" || argument == "--fps" ||
         argument == "--simulate-loss-frame" ||
         argument == "--invalidate-delay-frames" ||
         argument == "--force-idr-frame" ||
         argument == "--reference-frames") &&
        index + 1 < argc) {
      unsigned long value = 0;
      try {
        value = std::stoul(argv[++index]);
      } catch (const std::exception&) {
        std::cerr << "invalid numeric argument\n";
        return 2;
      }
      const bool zero_allowed = argument == "--reference-frames";
      if ((!zero_allowed && value == 0) || value > 36000) {
        std::cerr << "numeric argument is outside the supported range\n";
        return 2;
      }
      if (argument == "--frames") {
        frame_count = static_cast<unsigned int>(value);
      } else if (argument == "--fps") {
        frame_rate = static_cast<unsigned int>(value);
      } else if (argument == "--simulate-loss-frame") {
        simulate_loss_frame = static_cast<unsigned int>(value);
      } else if (argument == "--invalidate-delay-frames") {
        invalidate_delay_frames = static_cast<unsigned int>(value);
      } else if (argument == "--force-idr-frame") {
        force_idr_frame = static_cast<unsigned int>(value);
      } else {
        reference_frames = static_cast<unsigned int>(value);
      }
      continue;
    }
    if ((argument == "--output" || argument == "--bitstream") &&
        index + 1 < argc) {
      if (argument == "--output") {
        output_name = argv[++index];
      } else {
        bitstream_path = argv[++index];
      }
      continue;
    }
    if (argument == "--split" && index + 1 < argc) {
      split_mode_name = argv[++index];
      if (split_mode_name == "auto") {
        split_mode = NV_ENC_SPLIT_AUTO_MODE;
      } else if (split_mode_name == "forced") {
        split_mode = NV_ENC_SPLIT_AUTO_FORCED_MODE;
      } else if (split_mode_name == "disabled") {
        split_mode = NV_ENC_SPLIT_DISABLE_MODE;
      } else {
        std::cerr << "split mode must be auto, forced, or disabled\n";
        return 2;
      }
      continue;
    }
    if (argument == "--tuning" && index + 1 < argc) {
      tuning_name = argv[++index];
      if (tuning_name == "low-latency") {
        tuning = NV_ENC_TUNING_INFO_LOW_LATENCY;
      } else if (tuning_name == "ultra-low-latency") {
        tuning = NV_ENC_TUNING_INFO_ULTRA_LOW_LATENCY;
      } else {
        std::cerr << "tuning must be low-latency or ultra-low-latency\n";
        return 2;
      }
      continue;
    }
    std::cerr << "usage: " << argv[0]
              << " [--output NAME] [--frames COUNT] [--fps RATE]"
                 " [--bitstream PATH] [--split MODE] [--require-changing]"
                 " [--queue-depth 0|1] [--intra-refresh-count COUNT]"
                 " [--intra-refresh-period PERIOD]"
                 " [--single-slice-intra-refresh 0|1]"
                 " [--simulate-loss-frame FRAME]"
                 " [--invalidate-delay-frames COUNT]"
                 " [--force-idr-frame FRAME] [--reference-frames COUNT]"
                 " [--no-reference-invalidation]"
                 " [--tuning low-latency|ultra-low-latency]"
                 " [--require-robustness] [--self-test]\n";
    return 2;
  }
  if (frame_rate > 240) {
    std::cerr << "frame rate must not exceed 240\n";
    return 2;
  }
  if (intra_refresh_period < 0) {
    intra_refresh_period = static_cast<int>(frame_rate);
  }
  if (intra_refresh_count < 0) {
    intra_refresh_count = intra_refresh_period / 2;
  }
  if (intra_refresh_count > 0 &&
      intra_refresh_count >= intra_refresh_period) {
    std::cerr << "intra-refresh count must be smaller than the period\n";
    return 2;
  }
  if (simulate_loss_frame > frame_count || force_idr_frame > frame_count ||
      (simulate_loss_frame != 0 && reference_invalidation_enabled &&
       simulate_loss_frame + invalidate_delay_frames > frame_count)) {
    std::cerr << "recovery frame is outside the encoded frame range\n";
    return 2;
  }
  if (reference_frames > 8) {
    std::cerr << "reference frame count must not exceed 8\n";
    return 2;
  }
  if (simulate_loss_frame != 0 && reference_invalidation_enabled &&
      reference_frames == 0) {
    reference_frames = 4;
  }
  if (simulate_loss_frame != 0 && reference_invalidation_enabled &&
      queue_depth == 1 &&
      invalidate_delay_frames < 2) {
    std::cerr << "threaded recovery requires at least two feedback frames\n";
    return 2;
  }

  try {
    Resources resources;
    initialize_cuda(resources);
    self_test_conversion(resources);
    const NVFBC_RANDR_OUTPUT_INFO output =
        initialize_nvfbc(resources, output_name);
    const std::uint32_t width = output.trackedBox.w;
    const std::uint32_t height = output.trackedBox.h;
    initialize_nvenc(resources, width, height, frame_rate, split_mode, tuning,
                     static_cast<std::uint32_t>(intra_refresh_period),
                     single_slice_intra_refresh,
                     static_cast<std::uint32_t>(intra_refresh_count),
                     reference_frames);

    std::ofstream bitstream_file(bitstream_path,
                                 std::ios::binary | std::ios::trunc);
    if (!bitstream_file) {
      throw std::runtime_error("unable to open bitstream output: " +
                               bitstream_path);
    }

    using Clock = std::chrono::steady_clock;
    const auto run_started = Clock::now();
    const auto frame_period =
        std::chrono::nanoseconds(1'000'000'000LL / frame_rate);
    std::vector<std::int64_t> capture_us;
    std::vector<std::int64_t> conversion_us;
    std::vector<std::int64_t> resource_map_us;
    std::vector<std::int64_t> picture_setup_us;
    std::vector<std::int64_t> encode_submit_us;
    std::vector<std::int64_t> output_dispatch_us;
    std::vector<std::int64_t> bitstream_lock_wait_us;
    std::vector<std::int64_t> bitstream_write_us;
    std::vector<std::int64_t> resource_release_us;
    std::vector<std::int64_t> encode_us;
    std::vector<std::int64_t> pipeline_us;
    std::vector<std::int64_t> slot_lifetime_us;
    std::array<Clock::time_point, 2> pipeline_started_at{};
    std::array<Clock::time_point, 2> converted_at{};
    std::array<Clock::time_point, 2> submitted_at{};
    capture_us.reserve(frame_count);
    conversion_us.reserve(frame_count);
    resource_map_us.reserve(frame_count);
    picture_setup_us.reserve(frame_count);
    encode_submit_us.reserve(frame_count);
    output_dispatch_us.reserve(frame_count);
    bitstream_lock_wait_us.reserve(frame_count);
    bitstream_write_us.reserve(frame_count);
    resource_release_us.reserve(frame_count);
    encode_us.reserve(frame_count);
    pipeline_us.reserve(frame_count);
    slot_lifetime_us.reserve(frame_count);
    unsigned int new_frames = 0;
    unsigned int deadline_misses = 0;
    unsigned int bitstream_frames_written = 0;
    unsigned int bitstream_frames_dropped = 0;
    bool reference_invalidation_called = false;
    bool forced_idr_submitted = false;
    std::uint64_t encoded_bytes = 0;

    const auto drain_slot = [&](unsigned int slot_index) {
      Resources::EncodeSlot& slot = resources.encode_slots[slot_index];
      NV_ENC_LOCK_BITSTREAM lock{};
      lock.version = NV_ENC_LOCK_BITSTREAM_VER;
      lock.outputBitstream = slot.bitstream;
      const auto lock_started = Clock::now();
      require_nvenc(resources.nvenc.nvEncLockBitstream(resources.encoder, &lock),
                    "nvEncLockBitstream");
      slot.bitstream_locked = true;
      const auto encoded = Clock::now();
      if (simulate_loss_frame != 0 &&
          lock.outputTimeStamp == simulate_loss_frame) {
        ++bitstream_frames_dropped;
      } else {
        bitstream_file.write(
            static_cast<const char*>(lock.bitstreamBufferPtr),
            static_cast<std::streamsize>(lock.bitstreamSizeInBytes));
        if (!bitstream_file) {
          throw std::runtime_error("bitstream write failed");
        }
        ++bitstream_frames_written;
        encoded_bytes += lock.bitstreamSizeInBytes;
      }
      const auto written = Clock::now();
      require_nvenc(resources.nvenc.nvEncUnlockBitstream(resources.encoder,
                                                         slot.bitstream),
                    "nvEncUnlockBitstream");
      slot.bitstream_locked = false;
      require_nvenc(resources.nvenc.nvEncUnmapInputResource(resources.encoder,
                                                             slot.mapped),
                    "nvEncUnmapInputResource");
      slot.mapped = nullptr;
      const auto released = Clock::now();

      output_dispatch_us.push_back(
          std::chrono::duration_cast<std::chrono::microseconds>(
              lock_started - submitted_at[slot_index])
              .count());
      bitstream_lock_wait_us.push_back(
          std::chrono::duration_cast<std::chrono::microseconds>(
              encoded - lock_started)
              .count());
      bitstream_write_us.push_back(
          std::chrono::duration_cast<std::chrono::microseconds>(written - encoded)
              .count());
      resource_release_us.push_back(
          std::chrono::duration_cast<std::chrono::microseconds>(released - written)
              .count());
      encode_us.push_back(
          std::chrono::duration_cast<std::chrono::microseconds>(
              encoded - converted_at[slot_index])
              .count());
      pipeline_us.push_back(
          std::chrono::duration_cast<std::chrono::microseconds>(
              encoded - pipeline_started_at[slot_index])
              .count());
      slot_lifetime_us.push_back(
          std::chrono::duration_cast<std::chrono::microseconds>(
              released - pipeline_started_at[slot_index])
              .count());
    };

    std::mutex queue_mutex;
    std::condition_variable output_ready;
    std::condition_variable slot_released;
    std::deque<unsigned int> pending_slots;
    std::array<bool, 2> slot_in_use{};
    bool input_done = false;
    std::exception_ptr worker_error;
    std::thread output_worker;
    if (queue_depth == 1) {
      output_worker = std::thread([&] {
        while (true) {
          unsigned int slot_index = 0;
          {
            std::unique_lock<std::mutex> lock(queue_mutex);
            output_ready.wait(lock, [&] {
              return input_done || !pending_slots.empty();
            });
            if (pending_slots.empty()) {
              return;
            }
            slot_index = pending_slots.front();
            pending_slots.pop_front();
          }
          try {
            drain_slot(slot_index);
          } catch (...) {
            std::lock_guard<std::mutex> lock(queue_mutex);
            worker_error = std::current_exception();
            input_done = true;
            slot_released.notify_all();
            return;
          }
          {
            std::lock_guard<std::mutex> lock(queue_mutex);
            slot_in_use[slot_index] = false;
          }
          slot_released.notify_all();
        }
      });
    }

    try {
      for (unsigned int frame = 0; frame < frame_count; ++frame) {
        std::this_thread::sleep_until(run_started + frame_period * frame);
        const auto pipeline_started = Clock::now();
        const unsigned int frame_id = frame + 1;
        const unsigned int slot_index = frame % resources.encode_slots.size();
        if (queue_depth == 1) {
          std::unique_lock<std::mutex> lock(queue_mutex);
          slot_released.wait(lock, [&] {
            return !slot_in_use[slot_index] || worker_error != nullptr;
          });
          if (worker_error != nullptr) {
            std::rethrow_exception(worker_error);
          }
        }
        if (simulate_loss_frame != 0 && reference_invalidation_enabled &&
            frame_id == simulate_loss_frame + invalidate_delay_frames) {
          require_nvenc(resources.nvenc.nvEncInvalidateRefFrames(
                            resources.encoder, simulate_loss_frame),
                        "nvEncInvalidateRefFrames");
          reference_invalidation_called = true;
        }
        Resources::EncodeSlot& slot = resources.encode_slots[slot_index];
        void* captured_buffer = nullptr;
        NVFBC_FRAME_GRAB_INFO frame_info{};
        NVFBC_TOCUDA_GRAB_FRAME_PARAMS grab{};
        grab.dwVersion = NVFBC_TOCUDA_GRAB_FRAME_PARAMS_VER;
        grab.dwFlags = NVFBC_TOCUDA_GRAB_FLAGS_NOWAIT |
                       NVFBC_TOCUDA_GRAB_FLAGS_FORCE_REFRESH;
        grab.pFrameGrabInfo = &frame_info;
        grab.pCUDADeviceBuffer = &captured_buffer;
        NVFBCSTATUS fbc_status = resources.nvfbc.nvFBCToCudaGrabFrame(
            resources.nvfbc_handle, &grab);
        const auto captured = Clock::now();
        if (fbc_status != NVFBC_SUCCESS || captured_buffer == nullptr) {
          throw std::runtime_error("NvFBCToCudaGrabFrame failed: status=" +
                                   std::to_string(fbc_status));
        }
        if (frame_info.dwWidth != width || frame_info.dwHeight != height) {
          throw std::runtime_error("captured output geometry changed");
        }
        new_frames += frame_info.bIsNewFrame ? 1U : 0U;

        launch_conversion(
            resources,
            static_cast<CUdeviceptr>(
                reinterpret_cast<std::uintptr_t>(captured_buffer)),
            slot.surface, width, height,
            static_cast<std::uint64_t>(slot.pitch));
        const auto converted = Clock::now();
        pipeline_started_at[slot_index] = pipeline_started;
        converted_at[slot_index] = converted;

        NV_ENC_MAP_INPUT_RESOURCE map{};
        map.version = NV_ENC_MAP_INPUT_RESOURCE_VER;
        map.registeredResource = slot.registered;
        const auto map_started = Clock::now();
        require_nvenc(resources.nvenc.nvEncMapInputResource(resources.encoder,
                                                             &map),
                       "nvEncMapInputResource");
        const auto mapped = Clock::now();
        slot.mapped = map.mappedResource;

        NV_ENC_PIC_PARAMS picture{};
        picture.version = NV_ENC_PIC_PARAMS_VER;
        picture.inputBuffer = slot.mapped;
        picture.bufferFmt = NV_ENC_BUFFER_FORMAT_YUV444_10BIT;
        picture.inputWidth = width;
        picture.inputHeight = height;
        picture.outputBitstream = slot.bitstream;
        picture.pictureStruct = NV_ENC_PIC_STRUCT_FRAME;
        picture.inputTimeStamp = frame_id;
        picture.inputDuration = 1;
        if (frame_id == force_idr_frame) {
          picture.encodePicFlags = NV_ENC_PIC_FLAG_FORCEIDR |
                                   NV_ENC_PIC_FLAG_OUTPUT_SPSPPS;
          forced_idr_submitted = true;
        }
        const auto submit_started = Clock::now();
        const NVENCSTATUS encode_status =
            resources.nvenc.nvEncEncodePicture(resources.encoder, &picture);
        const auto submitted = Clock::now();
        if (encode_status != NV_ENC_SUCCESS) {
          throw std::runtime_error("nvEncEncodePicture failed: status=" +
                                   std::to_string(encode_status));
        }
        submitted_at[slot_index] = submitted;

        capture_us.push_back(
            std::chrono::duration_cast<std::chrono::microseconds>(
                captured - pipeline_started)
                .count());
        conversion_us.push_back(
            std::chrono::duration_cast<std::chrono::microseconds>(converted -
                                                                  captured)
                .count());
        resource_map_us.push_back(
            std::chrono::duration_cast<std::chrono::microseconds>(mapped -
                                                                  map_started)
                .count());
        picture_setup_us.push_back(
            std::chrono::duration_cast<std::chrono::microseconds>(
                submit_started - mapped)
                .count());
        encode_submit_us.push_back(
            std::chrono::duration_cast<std::chrono::microseconds>(
                submitted - submit_started)
                .count());
        const auto deadline = run_started + frame_period * (frame + 1);
        if (queue_depth == 0) {
          drain_slot(slot_index);
        } else {
          {
            std::lock_guard<std::mutex> lock(queue_mutex);
            slot_in_use[slot_index] = true;
            pending_slots.push_back(slot_index);
          }
          output_ready.notify_one();
        }
        if (Clock::now() > deadline) {
          ++deadline_misses;
        }
      }
      if (queue_depth == 1) {
        {
          std::lock_guard<std::mutex> lock(queue_mutex);
          input_done = true;
        }
        output_ready.notify_all();
        output_worker.join();
        if (worker_error != nullptr) {
          std::rethrow_exception(worker_error);
        }
      }
    } catch (...) {
      if (queue_depth == 1 && output_worker.joinable()) {
        {
          std::lock_guard<std::mutex> lock(queue_mutex);
          input_done = true;
        }
        output_ready.notify_all();
        output_worker.join();
      }
      throw;
    }

    NV_ENC_PIC_PARAMS eos{};
    eos.version = NV_ENC_PIC_PARAMS_VER;
    eos.encodePicFlags = NV_ENC_PIC_FLAG_EOS;
    require_nvenc(resources.nvenc.nvEncEncodePicture(resources.encoder, &eos),
                   "nvEncEncodePicture(EOS)");
    bitstream_file.close();

    const double elapsed_seconds =
        std::chrono::duration<double>(Clock::now() - run_started).count();
    const double achieved_fps = frame_count / elapsed_seconds;
    const double observed_bitrate_mbps =
        static_cast<double>(encoded_bytes) * 8.0 / elapsed_seconds / 1'000'000.0;
    const double capture_p95 = percentile(capture_us, 95);
    const double conversion_p95 = percentile(conversion_us, 95);
    const double encode_p95 = percentile(encode_us, 95);
    const double pipeline_p95 = percentile(pipeline_us, 95);
    const double pipeline_p99 = percentile(pipeline_us, 99);
    const auto pipeline_max = *std::max_element(pipeline_us.begin(),
                                                pipeline_us.end());
    const double frame_budget_us = 1'000'000.0 / frame_rate;
    const double frame_budget_headroom_us = frame_budget_us - pipeline_p95;
    const unsigned int allowed_deadline_misses =
        std::max(1U, frame_count / 100U);
    const bool source_activity_passed =
        !require_changing_source || new_frames * 10U >= frame_count * 9U;
    const bool capture_conversion_target =
        capture_p95 + conversion_p95 <= 3000.0;
    const bool nvenc_target = encode_p95 <= 8000.0;
    const bool local_pipeline_target = pipeline_p95 <= 25000.0;
    const bool realtime_passed =
        achieved_fps >= static_cast<double>(frame_rate) * 0.99 &&
        deadline_misses <= allowed_deadline_misses &&
        pipeline_p95 <= frame_budget_us &&
        capture_conversion_target && local_pipeline_target &&
        source_activity_passed;
    const bool realtime_robustness_passed =
        realtime_passed && pipeline_p99 <= frame_budget_us &&
        deadline_misses == 0;
    const bool component_targets_passed =
        capture_conversion_target && nvenc_target && local_pipeline_target;
    const bool bitstream_loss_passed =
        simulate_loss_frame == 0 || bitstream_frames_dropped == 1;
    const bool reference_invalidation_requested =
        simulate_loss_frame != 0 && reference_invalidation_enabled;
    const bool reference_invalidation_passed =
        !reference_invalidation_requested || reference_invalidation_called;
    const bool forced_idr_passed =
        force_idr_frame == 0 || forced_idr_submitted;

    std::cout << "capture_output=" << output.name << '\n'
              << "geometry=" << width << 'x' << height << '\n'
              << "source_format=BGRA8888\n"
              << "source_precision=8\n"
              << "conversion=identity-gbr\n"
              << "identity_plane_mapping=Y:G,U:B,V:R\n"
              << "encoder_format=YUV444_10BIT\n"
              << "codec=hevc-frext-10bit-444\n"
              << "nvenc_tuning=" << tuning_name << '\n'
              << "split_encode_mode=" << split_mode_name << '\n'
              << "intra_refresh_period=" << intra_refresh_period << '\n'
              << "intra_refresh_count=" << intra_refresh_count << '\n'
              << "single_slice_intra_refresh="
              << (single_slice_intra_refresh ? "yes" : "no") << '\n'
              << "reference_frames=" << reference_frames << '\n'
              << "simulated_loss_frame=" << simulate_loss_frame << '\n'
              << "reference_invalidation_requested="
              << (reference_invalidation_requested ? "yes" : "no") << '\n'
              << "invalidate_delay_frames=" << invalidate_delay_frames << '\n'
              << "force_idr_frame=" << force_idr_frame << '\n'
              << "frames_requested=" << frame_count << '\n'
              << "new_frames_observed=" << new_frames << '\n'
              << "changing_source_required="
              << (require_changing_source ? "yes" : "no") << '\n'
              << "encoded_frames=" << frame_count << '\n'
              << "bitstream_frames_written=" << bitstream_frames_written
              << '\n'
              << "bitstream_frames_dropped=" << bitstream_frames_dropped
              << '\n'
              << "encoded_bytes=" << encoded_bytes << '\n'
              << "configured_bitrate_mbps=" << kBitrate / 1'000'000U << '\n'
              << "observed_bitrate_mbps=" << observed_bitrate_mbps << '\n'
              << "queue_depth=" << queue_depth << '\n'
              << "nvenc_latency_scope="
              << (queue_depth == 0 ? "blocking" : "adaptive-completion")
              << '\n'
              << std::fixed << std::setprecision(2)
              << "target_fps=" << frame_rate << '\n'
              << "achieved_fps=" << achieved_fps << '\n'
              << "frame_budget_us=" << frame_budget_us << '\n'
              << "capture_us_average=" << average(capture_us) << '\n'
              << "capture_us_p95=" << capture_p95 << '\n'
              << "conversion_us_average=" << average(conversion_us) << '\n'
              << "conversion_us_p95=" << conversion_p95 << '\n'
              << "nvenc_us_average=" << average(encode_us) << '\n'
              << "nvenc_us_p95=" << encode_p95 << '\n'
              << "pipeline_us_average=" << average(pipeline_us) << '\n'
              << "pipeline_us_p95=" << pipeline_p95 << '\n'
              << "pipeline_us_p99=" << pipeline_p99 << '\n'
              << "pipeline_us_max=" << pipeline_max << '\n'
              << "frame_budget_headroom_us=" << frame_budget_headroom_us
              << '\n'
              << "deadline_misses=" << deadline_misses << '\n'
              << "bitstream=" << bitstream_path << '\n'
              << "source_activity_gate="
              << (source_activity_passed ? "pass" : "fail") << '\n'
              << "capture_conversion_3ms_target="
              << (capture_conversion_target ? "pass" : "fail") << '\n'
              << "nvenc_8ms_target="
              << (nvenc_target ? "pass" : "fail")
              << '\n'
              << "local_pipeline_25ms_target="
              << (local_pipeline_target ? "pass" : "fail") << '\n'
              << "component_latency_targets="
              << (component_targets_passed ? "pass" : "fail")
              << '\n'
              << "integrated_2160p60_gate="
              << (realtime_passed ? "pass" : "fail")
              << '\n'
              << "integrated_2160p60_robustness_gate="
              << (realtime_robustness_passed ? "pass" : "fail")
              << '\n'
              << "bitstream_loss_injection_gate="
              << (bitstream_loss_passed ? "pass" : "fail") << '\n'
              << "reference_invalidation_gate="
              << (!reference_invalidation_requested
                      ? "not-requested"
                      : (reference_invalidation_passed ? "pass" : "fail"))
              << '\n'
              << "forced_idr_submission_gate="
              << (force_idr_frame == 0
                      ? "not-requested"
                      : (forced_idr_passed ? "pass" : "fail"))
              << '\n'
              << "robustness_required="
              << (require_robustness ? "yes" : "no")
              << '\n';
    const auto print_distribution = [](const char* name,
                                       const std::vector<std::int64_t>& values) {
      std::cout << name << "_us_average=" << average(values) << '\n'
                << name << "_us_p50=" << percentile(values, 50) << '\n'
                << name << "_us_p95=" << percentile(values, 95) << '\n'
                << name << "_us_p99=" << percentile(values, 99) << '\n'
                << name << "_us_max="
                << *std::max_element(values.begin(), values.end()) << '\n';
    };
    std::cout << "timing_nvenc_completion_scope="
                 "map+setup+submit+dispatch+lock-wait\n";
    print_distribution("capture", capture_us);
    print_distribution("conversion", conversion_us);
    print_distribution("resource_map", resource_map_us);
    print_distribution("picture_setup", picture_setup_us);
    print_distribution("encode_submit_call", encode_submit_us);
    print_distribution("output_dispatch", output_dispatch_us);
    print_distribution("bitstream_lock_wait", bitstream_lock_wait_us);
    print_distribution("nvenc_completion", encode_us);
    print_distribution("capture_to_bitstream", pipeline_us);
    print_distribution("bitstream_write", bitstream_write_us);
    print_distribution("resource_release", resource_release_us);
    print_distribution("slot_lifetime", slot_lifetime_us);
    const bool requested_gates_passed =
        bitstream_loss_passed && reference_invalidation_passed &&
        forced_idr_passed;
    return ((require_robustness ? realtime_robustness_passed : realtime_passed) &&
            requested_gates_passed)
               ? 0
               : 1;
  } catch (const std::exception& error) {
    std::cerr << "video pipeline probe failed: " << error.what() << '\n';
    return 3;
  }
}
