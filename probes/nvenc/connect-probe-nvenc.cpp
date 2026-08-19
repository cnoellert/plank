#include <cstdio>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

#define FFNV_LOG_FUNC(logctx, message, ...) \
  do {                                         \
    (void)(logctx);                            \
    std::fprintf(stderr, message, __VA_ARGS__); \
  } while (false)
#define FFNV_DEBUG_LOG_FUNC(logctx, message, ...) \
  do {                                               \
    (void)(logctx);                                  \
  } while (false)
#include <ffnvcodec/dynlink_loader.h>

namespace {

bool guid_equal(const GUID& left, const GUID& right) {
  return std::memcmp(&left, &right, sizeof(GUID)) == 0;
}

bool query_capability(const NV_ENCODE_API_FUNCTION_LIST& api, void* encoder,
                      NV_ENC_CAPS capability, const char* name,
                      int minimum = 1) {
  NV_ENC_CAPS_PARAM parameters{};
  parameters.version = NV_ENC_CAPS_PARAM_VER;
  parameters.capsToQuery = capability;
  int value = 0;
  const NVENCSTATUS status =
      api.nvEncGetEncodeCaps(encoder, NV_ENC_CODEC_HEVC_GUID, &parameters, &value);
  if (status != NV_ENC_SUCCESS) {
    std::cout << name << "=query_failed status=" << status << '\n';
    return false;
  }
  std::cout << name << '=' << value << '\n';
  return value >= minimum;
}

}  // namespace

int main() {
  CudaFunctions* cuda = nullptr;
  NvencFunctions* loader = nullptr;
  CUcontext context = nullptr;
  void* encoder = nullptr;
  int result = 0;

  if (cuda_load_functions(&cuda, nullptr) != 0 || cuda->cuInit(0) != CUDA_SUCCESS) {
    std::cerr << "CUDA driver initialization failed\n";
    result = 2;
    goto cleanup;
  }

  {
    CUdevice device = 0;
    char device_name[128]{};
    if (cuda->cuDeviceGet(&device, 0) != CUDA_SUCCESS ||
        cuda->cuDeviceGetName(device_name, sizeof(device_name), device) !=
            CUDA_SUCCESS ||
        cuda->cuCtxCreate(&context, CU_CTX_SCHED_BLOCKING_SYNC, device) !=
            CUDA_SUCCESS) {
      std::cerr << "CUDA device/context creation failed\n";
      result = 3;
      goto cleanup;
    }
    std::cout << "cuda_device=" << device_name << '\n';
  }

  if (nvenc_load_functions(&loader, nullptr) != 0) {
    std::cerr << "NVENC loader initialization failed\n";
    result = 4;
    goto cleanup;
  }

  {
    std::uint32_t maximum_api = 0;
    if (loader->NvEncodeAPIGetMaxSupportedVersion(&maximum_api) != NV_ENC_SUCCESS) {
      std::cerr << "NVENC API version query failed\n";
      result = 5;
      goto cleanup;
    }
    std::cout << "nvenc_api_max=" << (maximum_api >> 4U) << '.'
              << (maximum_api & 0x0fU) << '\n';
  }

  {
    NV_ENCODE_API_FUNCTION_LIST api{};
    api.version = NV_ENCODE_API_FUNCTION_LIST_VER;
    if (loader->NvEncodeAPICreateInstance(&api) != NV_ENC_SUCCESS) {
      std::cerr << "NVENC function-list creation failed\n";
      result = 6;
      goto cleanup;
    }

    NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS open_parameters{};
    open_parameters.version = NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS_VER;
    open_parameters.deviceType = NV_ENC_DEVICE_TYPE_CUDA;
    open_parameters.device = context;
    open_parameters.apiVersion = NVENCAPI_VERSION;
    const NVENCSTATUS open_status =
        api.nvEncOpenEncodeSessionEx(&open_parameters, &encoder);
    if (open_status != NV_ENC_SUCCESS) {
      std::cerr << "NVENC session creation failed, status=" << open_status << '\n';
      result = 7;
      goto cleanup;
    }

    bool passed = true;
    std::uint32_t profile_count = 0;
    NVENCSTATUS status = api.nvEncGetEncodeProfileGUIDCount(
        encoder, NV_ENC_CODEC_HEVC_GUID, &profile_count);
    std::vector<GUID> profiles(profile_count);
    if (status == NV_ENC_SUCCESS) {
      status = api.nvEncGetEncodeProfileGUIDs(
          encoder, NV_ENC_CODEC_HEVC_GUID, profiles.data(), profile_count,
          &profile_count);
    }
    bool has_frext = status == NV_ENC_SUCCESS;
    if (has_frext) {
      has_frext = false;
      for (const GUID& profile : profiles) {
        has_frext = has_frext || guid_equal(profile, NV_ENC_HEVC_PROFILE_FREXT_GUID);
      }
    }
    std::cout << "hevc_frext_profile=" << (has_frext ? "yes" : "no") << '\n';
    passed = passed && has_frext;

    std::uint32_t format_count = 0;
    status = api.nvEncGetInputFormatCount(encoder, NV_ENC_CODEC_HEVC_GUID,
                                          &format_count);
    std::vector<NV_ENC_BUFFER_FORMAT> formats(format_count);
    if (status == NV_ENC_SUCCESS) {
      status = api.nvEncGetInputFormats(encoder, NV_ENC_CODEC_HEVC_GUID,
                                        formats.data(), format_count,
                                        &format_count);
    }
    bool has_yuv444_10bit = status == NV_ENC_SUCCESS;
    if (has_yuv444_10bit) {
      has_yuv444_10bit = false;
      for (const NV_ENC_BUFFER_FORMAT format : formats) {
        has_yuv444_10bit =
            has_yuv444_10bit || format == NV_ENC_BUFFER_FORMAT_YUV444_10BIT;
      }
    }
    std::cout << "input_yuv444_10bit="
              << (has_yuv444_10bit ? "yes" : "no") << '\n';
    passed = passed && has_yuv444_10bit;

    passed = query_capability(api, encoder, NV_ENC_CAPS_SUPPORT_10BIT_ENCODE,
                              "caps_10bit_encode") &&
             passed;
    passed = query_capability(api, encoder, NV_ENC_CAPS_SUPPORT_YUV444_ENCODE,
                              "caps_yuv444_encode") &&
             passed;
    query_capability(api, encoder, NV_ENC_CAPS_SUPPORT_YUV422_ENCODE,
                     "caps_yuv422_encode", 0);
    passed = query_capability(api, encoder, NV_ENC_CAPS_SUPPORT_INTRA_REFRESH,
                              "caps_intra_refresh") &&
             passed;
    passed = query_capability(api, encoder,
                              NV_ENC_CAPS_SUPPORT_REF_PIC_INVALIDATION,
                              "caps_ref_pic_invalidation") &&
             passed;
    passed = query_capability(api, encoder,
                              NV_ENC_CAPS_SINGLE_SLICE_INTRA_REFRESH,
                              "caps_single_slice_intra_refresh") &&
             passed;
    passed = query_capability(api, encoder, NV_ENC_CAPS_NUM_ENCODER_ENGINES,
                              "caps_encoder_engines") &&
             passed;
    passed = query_capability(api, encoder, NV_ENC_CAPS_WIDTH_MAX,
                              "caps_width_max", 3840) &&
             passed;
    passed = query_capability(api, encoder, NV_ENC_CAPS_HEIGHT_MAX,
                              "caps_height_max", 2160) &&
             passed;
    std::cout << "required_nvenc_caps=" << (passed ? "pass" : "fail") << '\n';
    if (!passed) {
      result = 8;
    }
    api.nvEncDestroyEncoder(encoder);
    encoder = nullptr;
  }

cleanup:
  if (encoder != nullptr) {
    NV_ENCODE_API_FUNCTION_LIST api{};
    api.version = NV_ENCODE_API_FUNCTION_LIST_VER;
    if (loader != nullptr &&
        loader->NvEncodeAPICreateInstance(&api) == NV_ENC_SUCCESS) {
      api.nvEncDestroyEncoder(encoder);
    }
  }
  nvenc_free_functions(&loader);
  if (context != nullptr && cuda != nullptr) {
    cuda->cuCtxDestroy(context);
  }
  cuda_free_functions(&cuda);
  return result;
}
