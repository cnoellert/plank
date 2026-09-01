#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <exception>
#include <fcntl.h>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <mutex>
#include <numeric>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include <unistd.h>

#include <x264.h>

namespace {

using Clock = std::chrono::steady_clock;

enum class PixelFormat { kBgr0, kIdentity8, kIdentity10 };

struct Options {
  std::string input = "-";
  PixelFormat format = PixelFormat::kBgr0;
  unsigned int width = 3840;
  unsigned int height = 2160;
  unsigned int frames = 600;
  unsigned int fps = 60;
  unsigned int bitrate_kbps = 100000;
  unsigned int vbv_kbits = 2000;
  bool preload = false;
};

[[noreturn]] void fail(const std::string& message) {
  throw std::runtime_error(message);
}

unsigned int parse_unsigned(const char* value, const char* name,
                            unsigned int maximum) {
  try {
    const unsigned long parsed = std::stoul(value);
    if (parsed == 0 || parsed > maximum) {
      fail(std::string(name) + " is outside the supported range");
    }
    return static_cast<unsigned int>(parsed);
  } catch (const std::exception&) {
    fail(std::string("invalid ") + name);
  }
}

const char* format_name(PixelFormat format) {
  switch (format) {
    case PixelFormat::kBgr0:
      return "bgr0-native-rgb8";
    case PixelFormat::kIdentity8:
      return "gbr-identity8";
    case PixelFormat::kIdentity10:
      return "gbr-identity10";
  }
  return "unknown";
}

std::size_t checked_multiply(std::size_t left, std::size_t right) {
  if (left != 0 && right > std::numeric_limits<std::size_t>::max() / left) {
    fail("input size overflows size_t");
  }
  return left * right;
}

std::size_t bytes_per_frame(const Options& options) {
  const std::size_t pixels =
      checked_multiply(options.width, options.height);
  switch (options.format) {
    case PixelFormat::kBgr0:
      return checked_multiply(pixels, 4);
    case PixelFormat::kIdentity8:
      return checked_multiply(pixels, 3);
    case PixelFormat::kIdentity10:
      return checked_multiply(pixels, 6);
  }
  fail("unknown pixel format");
}

void read_exact(int input, uint8_t* destination, std::size_t bytes,
                unsigned int frame_index) {
  std::size_t offset = 0;
  while (offset < bytes) {
    const ssize_t received =
        ::read(input, destination + offset, bytes - offset);
    if (received < 0 && errno == EINTR) {
      continue;
    }
    if (received <= 0) {
      const std::string detail = received < 0 ? ": " + std::string(std::strerror(errno))
                                               : std::string();
      fail("short input while reading frame " + std::to_string(frame_index) +
           detail);
    }
    offset += static_cast<std::size_t>(received);
  }
}

double percentile(const std::vector<double>& sorted, double fraction) {
  if (sorted.empty()) {
    return 0.0;
  }
  const double position = fraction * static_cast<double>(sorted.size() - 1);
  const std::size_t lower = static_cast<std::size_t>(std::floor(position));
  const std::size_t upper = static_cast<std::size_t>(std::ceil(position));
  const double blend = position - static_cast<double>(lower);
  return sorted[lower] + (sorted[upper] - sorted[lower]) * blend;
}

void configure_picture(x264_picture_t& picture, const Options& options,
                       uint8_t* frame) {
  x264_picture_init(&picture);
  picture.img.i_csp = options.format == PixelFormat::kBgr0
                          ? X264_CSP_BGRA
                          : X264_CSP_I444 |
                                (options.format == PixelFormat::kIdentity10
                                     ? X264_CSP_HIGH_DEPTH
                                     : 0);
  if (options.format == PixelFormat::kBgr0) {
    picture.img.i_plane = 1;
    picture.img.i_stride[0] = static_cast<int>(options.width * 4U);
    picture.img.plane[0] = frame;
    return;
  }

  const std::size_t plane_bytes = checked_multiply(
      checked_multiply(options.width, options.height),
      options.format == PixelFormat::kIdentity10 ? 2U : 1U);
  picture.img.i_plane = 3;
  for (int plane = 0; plane < 3; ++plane) {
    picture.img.i_stride[plane] = static_cast<int>(
        options.width * (options.format == PixelFormat::kIdentity10 ? 2U : 1U));
    picture.img.plane[plane] = frame + plane_bytes * plane;
  }
}

Options parse_options(int argc, char** argv) {
  Options options;
  for (int index = 1; index < argc; ++index) {
    const std::string argument = argv[index];
    if (argument == "--input" && index + 1 < argc) {
      options.input = argv[++index];
    } else if (argument == "--format" && index + 1 < argc) {
      const std::string format = argv[++index];
      if (format == "bgr0") {
        options.format = PixelFormat::kBgr0;
      } else if (format == "identity8") {
        options.format = PixelFormat::kIdentity8;
      } else if (format == "identity10") {
        options.format = PixelFormat::kIdentity10;
      } else {
        fail("unsupported format: " + format);
      }
    } else if (argument == "--width" && index + 1 < argc) {
      options.width = parse_unsigned(argv[++index], "width", 16384);
    } else if (argument == "--height" && index + 1 < argc) {
      options.height = parse_unsigned(argv[++index], "height", 16384);
    } else if (argument == "--frames" && index + 1 < argc) {
      options.frames = parse_unsigned(argv[++index], "frame count", 36000);
    } else if (argument == "--fps" && index + 1 < argc) {
      options.fps = parse_unsigned(argv[++index], "frame rate", 240);
    } else if (argument == "--bitrate-kbps" && index + 1 < argc) {
      options.bitrate_kbps =
          parse_unsigned(argv[++index], "bitrate", 1000000);
    } else if (argument == "--vbv-kbits" && index + 1 < argc) {
      options.vbv_kbits = parse_unsigned(argv[++index], "VBV size", 1000000);
    } else if (argument == "--preload") {
      options.preload = true;
    } else if (argument == "--help") {
      std::cout
          << "Usage: plank-benchmark-x264 [--input FILE|-] "
             "[--format bgr0|identity8|identity10] [--width N] [--height N] "
             "[--frames N] [--fps N] [--bitrate-kbps N] [--vbv-kbits N] "
             "[--preload]\n";
      std::exit(0);
    } else {
      fail("unknown or incomplete argument: " + argument);
    }
  }
  if (options.preload && options.input == "-") {
    fail("--preload requires a regular input file");
  }
  return options;
}

}  // namespace

int main(int argc, char** argv) {
  try {
    const Options options = parse_options(argc, argv);
    const std::size_t frame_bytes = bytes_per_frame(options);

    int input = STDIN_FILENO;
    if (options.input != "-") {
      input = ::open(options.input.c_str(), O_RDONLY);
      if (input < 0) {
        fail("cannot open input " + options.input + ": " +
             std::strerror(errno));
      }
    }

    std::vector<uint8_t> preloaded;
    constexpr std::size_t kInputSlots = 3;
    std::vector<std::vector<uint8_t>> input_slots;
    if (options.preload) {
      preloaded.resize(checked_multiply(frame_bytes, options.frames));
      for (unsigned int index = 0; index < options.frames; ++index) {
        read_exact(input, preloaded.data() + frame_bytes * index, frame_bytes,
                   index);
      }
    } else {
      input_slots.resize(kInputSlots);
      for (auto& slot : input_slots) {
        slot.resize(frame_bytes);
      }
    }

    x264_param_t parameters{};
    if (x264_param_default_preset(&parameters, "ultrafast", "zerolatency") < 0) {
      fail("x264 rejected ultrafast/zerolatency");
    }
    parameters.i_width = static_cast<int>(options.width);
    parameters.i_height = static_cast<int>(options.height);
    parameters.i_csp = options.format == PixelFormat::kBgr0
                           ? X264_CSP_BGRA
                           : X264_CSP_I444 |
                                 (options.format == PixelFormat::kIdentity10
                                      ? X264_CSP_HIGH_DEPTH
                                      : 0);
    parameters.i_bitdepth =
        options.format == PixelFormat::kIdentity10 ? 10 : 8;
    parameters.i_fps_num = options.fps;
    parameters.i_fps_den = 1;
    parameters.i_timebase_num = 1;
    parameters.i_timebase_den = options.fps;
    parameters.b_vfr_input = 0;
    parameters.i_frame_total = static_cast<int>(options.frames);
    parameters.i_keyint_max = static_cast<int>(options.fps);
    parameters.i_keyint_min = static_cast<int>(options.fps);
    parameters.i_scenecut_threshold = 0;
    parameters.i_bframe = 0;
    parameters.rc.i_rc_method = X264_RC_ABR;
    parameters.rc.i_bitrate = static_cast<int>(options.bitrate_kbps);
    parameters.rc.i_vbv_max_bitrate = static_cast<int>(options.bitrate_kbps);
    parameters.rc.i_vbv_buffer_size = static_cast<int>(options.vbv_kbits);
    parameters.rc.b_filler = 1;
    parameters.i_nal_hrd = X264_NAL_HRD_CBR;
    parameters.b_repeat_headers = 1;
    parameters.b_annexb = 1;
    parameters.vui.b_fullrange = 1;
    parameters.vui.i_colmatrix = 0;
    parameters.vui.i_colorprim = 1;
    parameters.vui.i_transfer = 13;
    parameters.i_log_level = X264_LOG_WARNING;
    if (x264_param_apply_profile(&parameters, "high444") < 0) {
      fail("x264 rejected the High 4:4:4 profile");
    }

    std::unique_ptr<x264_t, decltype(&x264_encoder_close)> encoder(
        x264_encoder_open(&parameters), &x264_encoder_close);
    if (!encoder) {
      fail("x264_encoder_open failed");
    }
    x264_param_t active_parameters{};
    x264_encoder_parameters(encoder.get(), &active_parameters);

    std::vector<double> read_us(options.frames, 0.0);
    std::vector<double> encode_us;
    encode_us.reserve(options.frames);
    std::uint64_t output_bytes = 0;
    unsigned int output_frames = 0;
    unsigned int delayed_calls = 0;

    std::mutex input_mutex;
    std::condition_variable input_ready;
    std::vector<bool> slot_ready(kInputSlots, false);
    bool stop_reader = false;
    std::exception_ptr reader_error;
    std::thread reader;
    if (!options.preload) {
      reader = std::thread([&] {
        try {
          for (unsigned int index = 0; index < options.frames; ++index) {
            const std::size_t slot_index = index % kInputSlots;
            {
              std::unique_lock<std::mutex> lock(input_mutex);
              input_ready.wait(lock, [&] {
                return stop_reader || !slot_ready[slot_index];
              });
              if (stop_reader) {
                return;
              }
            }
            const auto read_start = Clock::now();
            read_exact(input, input_slots[slot_index].data(), frame_bytes,
                       index);
            const auto read_end = Clock::now();
            read_us[index] =
                std::chrono::duration<double, std::micro>(read_end - read_start)
                    .count();
            {
              std::lock_guard<std::mutex> lock(input_mutex);
              slot_ready[slot_index] = true;
            }
            input_ready.notify_all();
          }
        } catch (...) {
          std::lock_guard<std::mutex> lock(input_mutex);
          reader_error = std::current_exception();
          input_ready.notify_all();
        }
      });
    }

    const auto run_start = Clock::now();
    try {
      for (unsigned int index = 0; index < options.frames; ++index) {
      uint8_t* frame_data = nullptr;
      if (options.preload) {
        frame_data = preloaded.data() + frame_bytes * index;
      } else {
        const std::size_t slot_index = index % kInputSlots;
        std::unique_lock<std::mutex> lock(input_mutex);
        input_ready.wait(lock, [&] {
          return slot_ready[slot_index] || reader_error != nullptr;
        });
        if (reader_error != nullptr) {
          std::rethrow_exception(reader_error);
        }
        frame_data = input_slots[slot_index].data();
      }

      x264_picture_t picture_in{};
      x264_picture_t picture_out{};
      configure_picture(picture_in, options, frame_data);
      picture_in.i_pts = index;
      x264_nal_t* nals = nullptr;
      int nal_count = 0;
      const auto encode_start = Clock::now();
      const int bytes = x264_encoder_encode(encoder.get(), &nals, &nal_count,
                                            &picture_in, &picture_out);
      const auto encode_end = Clock::now();
      if (bytes < 0) {
        fail("x264_encoder_encode failed on frame " + std::to_string(index));
      }
      encode_us.push_back(
          std::chrono::duration<double, std::micro>(encode_end - encode_start)
              .count());
      output_bytes += static_cast<unsigned int>(bytes);
      if (bytes == 0) {
        ++delayed_calls;
      } else {
        ++output_frames;
        if (picture_out.i_pts != static_cast<std::int64_t>(index)) {
          fail("encoder output was reordered or delayed");
        }
      }
      if (!options.preload) {
        const std::size_t slot_index = index % kInputSlots;
        {
          std::lock_guard<std::mutex> lock(input_mutex);
          slot_ready[slot_index] = false;
        }
        input_ready.notify_all();
      }
      }
    } catch (...) {
      if (reader.joinable()) {
        {
          std::lock_guard<std::mutex> lock(input_mutex);
          stop_reader = true;
        }
        input_ready.notify_all();
        reader.join();
      }
      throw;
    }
    if (reader.joinable()) {
      reader.join();
    }

    while (x264_encoder_delayed_frames(encoder.get()) > 0) {
      x264_nal_t* nals = nullptr;
      int nal_count = 0;
      x264_picture_t picture_out{};
      const int bytes = x264_encoder_encode(encoder.get(), &nals, &nal_count,
                                            nullptr, &picture_out);
      if (bytes < 0) {
        fail("x264 flush failed");
      }
      output_bytes += static_cast<unsigned int>(bytes);
      if (bytes > 0) {
        ++output_frames;
      }
    }
    const auto run_end = Clock::now();

    std::vector<double> sorted = encode_us;
    std::sort(sorted.begin(), sorted.end());
    const auto maximum =
        std::max_element(encode_us.begin(), encode_us.end());
    const std::size_t maximum_index = static_cast<std::size_t>(
        std::distance(encode_us.begin(), maximum));
    const std::size_t steady_start = std::min<std::size_t>(
        options.fps, encode_us.size() > 1 ? encode_us.size() - 1 : 0);
    std::vector<double> steady(encode_us.begin() + steady_start,
                               encode_us.end());
    std::sort(steady.begin(), steady.end());
    const double mean = std::accumulate(encode_us.begin(), encode_us.end(), 0.0) /
                        static_cast<double>(encode_us.size());
    const double pipeline_seconds =
        std::chrono::duration<double>(run_end - run_start).count();
    const double budget_us = 1000000.0 / options.fps;
    const auto misses = static_cast<unsigned int>(std::count_if(
        encode_us.begin(), encode_us.end(),
        [budget_us](double duration) { return duration > budget_us; }));
    const auto steady_misses = static_cast<unsigned int>(std::count_if(
        steady.begin(), steady.end(),
        [budget_us](double duration) { return duration > budget_us; }));

    std::cout << std::fixed << std::setprecision(3)
              << "x264_benchmark_format=" << format_name(options.format) << '\n'
              << "x264_benchmark_geometry=" << options.width << 'x'
              << options.height << '\n'
              << "x264_benchmark_frames=" << options.frames << '\n'
              << "x264_benchmark_output_frames=" << output_frames << '\n'
              << "x264_benchmark_delayed_calls=" << delayed_calls << '\n'
              << "x264_benchmark_preloaded="
              << (options.preload ? "yes" : "no") << '\n'
              << "x264_benchmark_input_model="
              << (options.preload ? "preloaded" : "three-slot-threaded")
              << '\n'
              << "x264_benchmark_threads=" << active_parameters.i_threads << '\n'
              << "x264_benchmark_sliced_threads="
              << (active_parameters.b_sliced_threads ? "yes" : "no") << '\n'
              << "x264_benchmark_output_bytes=" << output_bytes << '\n'
              << "x264_encode_completion_mean_ms=" << mean / 1000.0 << '\n'
              << "x264_encode_completion_p50_ms="
              << percentile(sorted, 0.50) / 1000.0 << '\n'
              << "x264_encode_completion_p95_ms="
              << percentile(sorted, 0.95) / 1000.0 << '\n'
              << "x264_encode_completion_p99_ms="
              << percentile(sorted, 0.99) / 1000.0 << '\n'
              << "x264_encode_completion_max_ms=" << sorted.back() / 1000.0
              << '\n'
              << "x264_encode_completion_max_frame=" << maximum_index << '\n'
              << "x264_encode_steady_after_frames=" << steady_start << '\n'
              << "x264_encode_steady_p95_ms="
              << percentile(steady, 0.95) / 1000.0 << '\n'
              << "x264_encode_steady_p99_ms="
              << percentile(steady, 0.99) / 1000.0 << '\n'
              << "x264_encode_steady_max_ms=" << steady.back() / 1000.0
              << '\n'
              << "x264_encode_budget_ms=" << budget_us / 1000.0 << '\n'
              << "x264_encode_budget_misses=" << misses << '\n'
              << "x264_encode_budget_miss_percent="
              << 100.0 * misses / options.frames << '\n'
              << "x264_encode_steady_budget_misses=" << steady_misses << '\n'
              << "x264_max_sustainable_fps="
              << 1000000.0 / mean << '\n'
              << "x264_pipeline_observed_fps="
              << options.frames / pipeline_seconds << '\n';
    return output_frames == options.frames && delayed_calls == 0 ? 0 : 2;
  } catch (const std::exception& error) {
    std::cerr << "plank-benchmark-x264: " << error.what() << '\n';
    return 1;
  }
}
