#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/extensions/Xcomposite.h>
#include <X11/extensions/XShm.h>

#include <sys/ipc.h>
#include <sys/shm.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <optional>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {

using clock_type = std::chrono::steady_clock;

struct channel_t {
  const char *name;
  unsigned long mask;
  unsigned int shift;
  unsigned int bits;
};

unsigned int trailing_zeroes(unsigned long value) {
  unsigned int count = 0;
  if (value == 0) {
    return 0;
  }
  while ((value & 1UL) == 0) {
    value >>= 1;
    ++count;
  }
  return count;
}

unsigned int bit_count(unsigned long value) {
  unsigned int count = 0;
  while (value != 0) {
    count += static_cast<unsigned int>(value & 1UL);
    value >>= 1;
  }
  return count;
}

channel_t make_channel(const char *name, unsigned long mask) {
  return {name, mask, trailing_zeroes(mask), bit_count(mask)};
}

unsigned long pack_code(const channel_t &channel, unsigned int code) {
  return (static_cast<unsigned long>(code) << channel.shift) & channel.mask;
}

unsigned int unpack_code(const channel_t &channel, unsigned long pixel) {
  return static_cast<unsigned int>((pixel & channel.mask) >> channel.shift);
}

const char *byte_order_name(int byte_order) {
  return byte_order == LSBFirst ? "LSBFirst" :
         byte_order == MSBFirst ? "MSBFirst" : "unknown";
}

class shm_image_t {
 public:
  shm_image_t(Display *display, Visual *visual, unsigned int depth,
              unsigned int width, unsigned int height):
      display_(display) {
    std::memset(&segment_, 0, sizeof(segment_));
    segment_.shmid = -1;
    segment_.shmaddr = reinterpret_cast<char *>(-1);

    try {
      image_ = XShmCreateImage(display_, visual, depth, ZPixmap, nullptr,
                               &segment_, width, height);
      if (image_ == nullptr) {
        throw std::runtime_error("XShmCreateImage failed");
      }

      const auto size = static_cast<std::size_t>(image_->bytes_per_line) *
                        static_cast<std::size_t>(image_->height);
      if (size == 0 || size > static_cast<std::size_t>(std::numeric_limits<int>::max()) * 16U) {
        throw std::runtime_error("invalid XShm image size");
      }

      segment_.shmid = shmget(IPC_PRIVATE, size, IPC_CREAT | 0600);
      if (segment_.shmid < 0) {
        throw std::runtime_error("shmget failed");
      }
      segment_.shmaddr = static_cast<char *>(shmat(segment_.shmid, nullptr, 0));
      if (segment_.shmaddr == reinterpret_cast<char *>(-1)) {
        throw std::runtime_error("shmat failed");
      }
      image_->data = segment_.shmaddr;
      segment_.readOnly = False;
      if (!XShmAttach(display_, &segment_)) {
        throw std::runtime_error("XShmAttach failed");
      }
      attached_ = true;
      XSync(display_, False);

      // The segment remains alive while both processes have it attached, but
      // no stale segment is left behind if the probe terminates unexpectedly.
      if (shmctl(segment_.shmid, IPC_RMID, nullptr) != 0) {
        throw std::runtime_error("shmctl(IPC_RMID) failed");
      }
      marked_for_removal_ = true;
    } catch (...) {
      cleanup();
      throw;
    }
  }

  shm_image_t(const shm_image_t &) = delete;
  shm_image_t &operator=(const shm_image_t &) = delete;

  ~shm_image_t() {
    cleanup();
  }

  XImage *get() const {
    return image_;
  }

  bool capture(Drawable drawable, int x, int y) const {
    return XShmGetImage(display_, drawable, image_, x, y, AllPlanes) != 0;
  }

 private:
  void cleanup() {
    if (attached_) {
      XShmDetach(display_, &segment_);
      XSync(display_, False);
      attached_ = false;
    }
    if (image_ != nullptr) {
      image_->data = nullptr;
      XDestroyImage(image_);
      image_ = nullptr;
    }
    if (segment_.shmaddr != reinterpret_cast<char *>(-1)) {
      shmdt(segment_.shmaddr);
      segment_.shmaddr = reinterpret_cast<char *>(-1);
    }
    if (segment_.shmid >= 0 && !marked_for_removal_) {
      shmctl(segment_.shmid, IPC_RMID, nullptr);
    }
    segment_.shmid = -1;
  }

  Display *display_;
  XImage *image_ = nullptr;
  XShmSegmentInfo segment_ {};
  bool attached_ = false;
  bool marked_for_removal_ = false;
};

struct timing_t {
  double minimum_ms;
  double median_ms;
  double p95_ms;
  double maximum_ms;
};

timing_t summarize(std::vector<double> samples) {
  std::sort(samples.begin(), samples.end());
  const auto percentile = [&samples](double fraction) {
    const auto index = static_cast<std::size_t>(
      fraction * static_cast<double>(samples.size() - 1));
    return samples[index];
  };
  return {samples.front(), percentile(0.50), percentile(0.95), samples.back()};
}

void print_timing(const char *name, const timing_t &timing,
                  std::size_t frame_bytes, int frames) {
  const double gib = static_cast<double>(frame_bytes) / (1024.0 * 1024.0 * 1024.0);
  const double median_gib_s = timing.median_ms > 0.0 ? gib * 1000.0 / timing.median_ms : 0.0;
  std::cout << name << "_frames=" << frames << '\n'
            << name << "_ms_min=" << timing.minimum_ms << '\n'
            << name << "_ms_median=" << timing.median_ms << '\n'
            << name << "_ms_p95=" << timing.p95_ms << '\n'
            << name << "_ms_max=" << timing.maximum_ms << '\n'
            << name << "_median_gib_per_second=" << median_gib_s << '\n';
}

bool is_eight_to_ten_expansion(unsigned int value) {
  for (unsigned int source = 0; source < 256; ++source) {
    if (((source << 2U) | (source >> 6U)) == value) {
      return true;
    }
  }
  return false;
}

void analyze_capture_image(XImage *image, const std::array<channel_t, 3> &channels) {
  constexpr std::size_t max_codes = 1024;
  std::array<std::array<bool, max_codes>, 3> observed {};
  std::array<std::uint64_t, 3> non_eight_bit_codes {};
  std::uint64_t samples = 0;

  const int x_step = std::max(1, image->width / 512);
  const int y_step = std::max(1, image->height / 256);
  for (int y = 0; y < image->height; y += y_step) {
    for (int x = 0; x < image->width; x += x_step) {
      const unsigned long pixel = XGetPixel(image, x, y);
      for (std::size_t index = 0; index < channels.size(); ++index) {
        const unsigned int value = unpack_code(channels[index], pixel);
        if (value < max_codes) {
          observed[index][value] = true;
        }
        if (channels[index].bits == 10 && !is_eight_to_ten_expansion(value)) {
          ++non_eight_bit_codes[index];
        }
      }
      ++samples;
    }
  }

  std::cout << "capture_sample_count=" << samples << '\n';
  for (std::size_t index = 0; index < channels.size(); ++index) {
    const auto unique = static_cast<unsigned int>(std::count(
      observed[index].begin(), observed[index].end(), true));
    std::cout << "capture_" << channels[index].name << "_unique_codes=" << unique << '\n'
              << "capture_" << channels[index].name
              << "_samples_outside_8_to_10_expansion=" << non_eight_bit_codes[index] << '\n';
  }
}

std::uint64_t sample_fingerprint(XImage *image) {
  std::uint64_t hash = 1469598103934665603ULL;
  const int x_step = std::max(1, image->width / 128);
  const int y_step = std::max(1, image->height / 72);
  for (int y = 0; y < image->height; y += y_step) {
    for (int x = 0; x < image->width; x += x_step) {
      hash ^= static_cast<std::uint64_t>(XGetPixel(image, x, y));
      hash *= 1099511628211ULL;
    }
  }
  return hash;
}

#if defined(__GNUC__)
#define CONNECT_NOINLINE __attribute__((noinline))
#else
#define CONNECT_NOINLINE
#endif

CONNECT_NOINLINE void copy_frame(const std::uint8_t *source,
                                 std::uint8_t *destination,
                                 std::size_t bytes) {
  std::memcpy(destination, source, bytes);
}

void unpack_identity_rows(const std::uint8_t *source, int width, int row_pitch,
                          int first_row, int end_row,
                          std::uint16_t *green, std::uint16_t *blue,
                          std::uint16_t *red,
                          const std::array<channel_t, 3> &channels) {
  for (int y = first_row; y < end_row; ++y) {
    const auto *source_row = reinterpret_cast<const std::uint32_t *>(
      source + static_cast<std::size_t>(y) * row_pitch);
    const auto row_offset = static_cast<std::size_t>(y) * width;
    for (int x = 0; x < width; ++x) {
      const auto pixel = static_cast<unsigned long>(source_row[x]);
      const auto offset = row_offset + static_cast<std::size_t>(x);
      red[offset] = static_cast<std::uint16_t>(unpack_code(channels[0], pixel));
      green[offset] = static_cast<std::uint16_t>(unpack_code(channels[1], pixel));
      blue[offset] = static_cast<std::uint16_t>(unpack_code(channels[2], pixel));
    }
  }
}

CONNECT_NOINLINE void unpack_identity_single(
    const std::uint8_t *source, int width, int height, int row_pitch,
    std::uint16_t *green, std::uint16_t *blue, std::uint16_t *red,
    const std::array<channel_t, 3> &channels) {
  unpack_identity_rows(source, width, row_pitch, 0, height,
                       green, blue, red, channels);
}

CONNECT_NOINLINE void unpack_identity_parallel(
    const std::uint8_t *source, int width, int height, int row_pitch,
    std::uint16_t *green, std::uint16_t *blue, std::uint16_t *red,
    const std::array<channel_t, 3> &channels, unsigned int thread_count) {
  std::vector<std::thread> workers;
  workers.reserve(thread_count);
  for (unsigned int index = 0; index < thread_count; ++index) {
    const int first_row = static_cast<int>(
      static_cast<std::int64_t>(height) * index / thread_count);
    const int end_row = static_cast<int>(
      static_cast<std::int64_t>(height) * (index + 1U) / thread_count);
    workers.emplace_back(unpack_identity_rows, source, width, row_pitch,
                         first_row, end_row, green, blue, red,
                         std::cref(channels));
  }
  for (auto &worker : workers) {
    worker.join();
  }
}

void benchmark_host_processing(XImage *image,
                               const std::array<channel_t, 3> &channels) {
  constexpr int copy_samples = 20;
  constexpr int unpack_samples = 10;
  const unsigned int parallel_threads = std::min(
    8U, std::max(1U, std::thread::hardware_concurrency()));
  const auto frame_bytes = static_cast<std::size_t>(image->bytes_per_line) *
                           static_cast<std::size_t>(image->height);
  const auto plane_samples = static_cast<std::size_t>(image->width) *
                             static_cast<std::size_t>(image->height);
  std::vector<std::uint8_t> copy_destination(frame_bytes);
  std::vector<std::uint16_t> planar_destination(plane_samples * 3U);
  auto *green = planar_destination.data();
  auto *blue = green + plane_samples;
  auto *red = blue + plane_samples;

  copy_frame(reinterpret_cast<const std::uint8_t *>(image->data),
             copy_destination.data(), frame_bytes);
  unpack_identity_single(reinterpret_cast<const std::uint8_t *>(image->data),
                         image->width, image->height, image->bytes_per_line,
                         green, blue, red, channels);

  std::vector<double> copy_times;
  for (int sample = 0; sample < copy_samples; ++sample) {
    const auto start = clock_type::now();
    copy_frame(reinterpret_cast<const std::uint8_t *>(image->data),
               copy_destination.data(), frame_bytes);
    const auto stop = clock_type::now();
    copy_times.push_back(
      std::chrono::duration<double, std::milli>(stop - start).count());
  }

  std::vector<double> single_times;
  std::vector<double> parallel_times;
  for (int sample = 0; sample < unpack_samples; ++sample) {
    auto start = clock_type::now();
    unpack_identity_single(reinterpret_cast<const std::uint8_t *>(image->data),
                           image->width, image->height, image->bytes_per_line,
                           green, blue, red, channels);
    auto stop = clock_type::now();
    single_times.push_back(
      std::chrono::duration<double, std::milli>(stop - start).count());

    start = clock_type::now();
    unpack_identity_parallel(reinterpret_cast<const std::uint8_t *>(image->data),
                             image->width, image->height, image->bytes_per_line,
                             green, blue, red, channels, parallel_threads);
    stop = clock_type::now();
    parallel_times.push_back(
      std::chrono::duration<double, std::milli>(stop - start).count());
  }

  const auto copy_timing = summarize(copy_times);
  const auto single_timing = summarize(single_times);
  const auto parallel_timing = summarize(parallel_times);
  const std::uint64_t checksum =
    static_cast<std::uint64_t>(copy_destination[frame_bytes / 2U]) +
    green[plane_samples / 2U] + blue[plane_samples / 2U] +
    red[plane_samples / 2U];
  std::cout << "host_memcpy_ms_median=" << copy_timing.median_ms << '\n'
            << "host_memcpy_ms_p95=" << copy_timing.p95_ms << '\n'
            << "host_unpack_single_ms_median=" << single_timing.median_ms << '\n'
            << "host_unpack_single_ms_p95=" << single_timing.p95_ms << '\n'
            << "host_unpack_parallel_threads=" << parallel_threads << '\n'
            << "host_unpack_parallel_ms_median=" << parallel_timing.median_ms << '\n'
            << "host_unpack_parallel_ms_p95=" << parallel_timing.p95_ms << '\n'
            << "host_processing_checksum=" << checksum << '\n';
}

#undef CONNECT_NOINLINE

bool controlled_round_trip(Display *display, Drawable root, Visual *visual,
                           unsigned int depth,
                           const std::array<channel_t, 3> &channels,
                           bool use_shm) {
  constexpr unsigned int width = 1024;
  constexpr unsigned int height = 1;
  Pixmap pixmap = XCreatePixmap(display, root, width, height, depth);
  if (pixmap == 0) {
    throw std::runtime_error("XCreatePixmap failed");
  }
  GC gc = XCreateGC(display, pixmap, 0, nullptr);
  if (gc == nullptr) {
    XFreePixmap(display, pixmap);
    throw std::runtime_error("XCreateGC failed");
  }

  XImage *source = XCreateImage(display, visual, depth, ZPixmap, 0, nullptr,
                                width, height, 32, 0);
  if (source == nullptr) {
    XFreeGC(display, gc);
    XFreePixmap(display, pixmap);
    throw std::runtime_error("XCreateImage failed");
  }
  const auto source_size = static_cast<std::size_t>(source->bytes_per_line) * height;
  source->data = static_cast<char *>(std::calloc(1, source_size));
  if (source->data == nullptr) {
    XDestroyImage(source);
    XFreeGC(display, gc);
    XFreePixmap(display, pixmap);
    throw std::runtime_error("source image allocation failed");
  }

  for (unsigned int code = 0; code < width; ++code) {
    unsigned long pixel = 0;
    for (const auto &channel : channels) {
      pixel |= pack_code(channel, code);
    }
    XPutPixel(source, static_cast<int>(code), 0, pixel);
  }
  XPutImage(display, pixmap, gc, source, 0, 0, 0, 0, width, height);
  XSync(display, False);

  XImage *captured = nullptr;
  shm_image_t *shm = nullptr;
  if (use_shm) {
    shm = new shm_image_t(display, visual, depth, width, height);
    if (!shm->capture(pixmap, 0, 0)) {
      delete shm;
      XDestroyImage(source);
      XFreeGC(display, gc);
      XFreePixmap(display, pixmap);
      throw std::runtime_error("controlled XShmGetImage failed");
    }
    captured = shm->get();
  } else {
    captured = XGetImage(display, pixmap, 0, 0, width, height,
                         AllPlanes, ZPixmap);
    if (captured == nullptr) {
      XDestroyImage(source);
      XFreeGC(display, gc);
      XFreePixmap(display, pixmap);
      throw std::runtime_error("controlled XGetImage failed");
    }
  }

  bool exact = true;
  for (unsigned int code = 0; code < width && exact; ++code) {
    const unsigned long pixel = XGetPixel(captured, static_cast<int>(code), 0);
    for (const auto &channel : channels) {
      if (unpack_code(channel, pixel) != code) {
        exact = false;
        break;
      }
    }
  }

  if (shm != nullptr) {
    delete shm;
  } else {
    XDestroyImage(captured);
  }
  XDestroyImage(source);
  XFreeGC(display, gc);
  XFreePixmap(display, pixmap);
  return exact;
}

struct visible_round_trip_t {
  bool xgetimage_exact;
  bool xshm_exact;
};

visible_round_trip_t visible_drawable_round_trip(
    Display *display, Window root, Drawable capture_drawable,
    Visual *capture_visual, unsigned int capture_depth,
    const std::array<channel_t, 3> &channels) {
  constexpr int x_offset = 0;
  constexpr int y_offset = 0;
  constexpr unsigned int width = 1024;
  constexpr unsigned int height = 32;

  Window window = XCreateSimpleWindow(display, root, x_offset, y_offset,
                                      width, height, 0, 0, 0);
  if (window == 0) {
    throw std::runtime_error("XCreateSimpleWindow failed");
  }
  XSetWindowAttributes window_attributes {};
  window_attributes.override_redirect = True;
  XChangeWindowAttributes(display, window, CWOverrideRedirect,
                          &window_attributes);
  GC gc = XCreateGC(display, window, 0, nullptr);
  if (gc == nullptr) {
    XDestroyWindow(display, window);
    throw std::runtime_error("visible-window XCreateGC failed");
  }
  XWindowAttributes root_attributes {};
  if (!XGetWindowAttributes(display, root, &root_attributes)) {
    XFreeGC(display, gc);
    XDestroyWindow(display, window);
    throw std::runtime_error("visible-window root attributes failed");
  }
  XImage *source = XCreateImage(display, root_attributes.visual,
                                root_attributes.depth, ZPixmap, 0, nullptr,
                                width, height, 32, 0);
  if (source == nullptr) {
    XFreeGC(display, gc);
    XDestroyWindow(display, window);
    throw std::runtime_error("visible-window XCreateImage failed");
  }
  const auto source_size = static_cast<std::size_t>(source->bytes_per_line) * height;
  source->data = static_cast<char *>(std::calloc(1, source_size));
  if (source->data == nullptr) {
    XDestroyImage(source);
    XFreeGC(display, gc);
    XDestroyWindow(display, window);
    throw std::runtime_error("visible-window image allocation failed");
  }

  for (unsigned int y = 0; y < height; ++y) {
    for (unsigned int code = 0; code < width; ++code) {
      unsigned long pixel = 0;
      for (const auto &channel : channels) {
        pixel |= pack_code(channel, code);
      }
      XPutPixel(source, static_cast<int>(code), static_cast<int>(y), pixel);
    }
  }
  XMapRaised(display, window);
  XPutImage(display, window, gc, source, 0, 0, 0, 0, width, height);
  XSync(display, False);
  // XSync only confirms the client requests reached Xorg. Give the compositor
  // one refresh interval to place the redirected window into its overlay.
  std::this_thread::sleep_for(std::chrono::milliseconds(50));

  XImage *get_image = XGetImage(display, capture_drawable, x_offset, y_offset,
                                width, height, AllPlanes, ZPixmap);
  if (get_image == nullptr) {
    XDestroyImage(source);
    XFreeGC(display, gc);
    XDestroyWindow(display, window);
    throw std::runtime_error("visible-root XGetImage failed");
  }
  shm_image_t shm_image(display, capture_visual, capture_depth, width, height);
  if (!shm_image.capture(capture_drawable, x_offset, y_offset)) {
    XDestroyImage(get_image);
    XDestroyImage(source);
    XFreeGC(display, gc);
    XDestroyWindow(display, window);
    throw std::runtime_error("visible-root XShmGetImage failed");
  }

  const auto exact = [&channels](XImage *captured) {
    constexpr int sample_y = 16;
    for (unsigned int code = 0; code < 1024; ++code) {
      const unsigned long pixel = XGetPixel(captured, static_cast<int>(code), sample_y);
      for (const auto &channel : channels) {
        if (unpack_code(channel, pixel) != code) {
          return false;
        }
      }
    }
    return true;
  };
  const visible_round_trip_t result {
    exact(get_image),
    exact(shm_image.get()),
  };

  XDestroyImage(get_image);
  XDestroyImage(source);
  XFreeGC(display, gc);
  XDestroyWindow(display, window);
  XSync(display, False);
  return result;
}

int parse_frames(int argc, char **argv, const char *name, int default_value) {
  for (int index = 1; index + 1 < argc; ++index) {
    if (std::string(argv[index]) == name) {
      const int value = std::stoi(argv[index + 1]);
      if (value <= 0 || value > 1000) {
        throw std::runtime_error(std::string(name) + " must be between 1 and 1000");
      }
      return value;
    }
  }
  return default_value;
}

std::optional<Drawable> parse_drawable(int argc, char **argv) {
  for (int index = 1; index + 1 < argc; ++index) {
    if (std::string(argv[index]) == "--drawable") {
      std::size_t consumed = 0;
      const auto value = std::stoul(argv[index + 1], &consumed, 0);
      if (consumed != std::strlen(argv[index + 1]) || value == 0) {
        throw std::runtime_error("--drawable must be a nonzero X11 window ID");
      }
      return static_cast<Drawable>(value);
    }
  }
  return std::nullopt;
}

bool has_flag(int argc, char **argv, const char *name) {
  for (int index = 1; index < argc; ++index) {
    if (std::string(argv[index]) == name) {
      return true;
    }
  }
  return false;
}

}  // namespace

int main(int argc, char **argv) {
  try {
    const int shm_frames = parse_frames(argc, argv, "--shm-frames", 20);
    const int get_frames = parse_frames(argc, argv, "--get-frames", 3);
    const int capture_fps = parse_frames(argc, argv, "--fps", 0);
    const auto requested_drawable = parse_drawable(argc, argv);
    const bool force_composite = has_flag(argc, argv, "--force-composite");
    std::unique_ptr<Display, decltype(&XCloseDisplay)> display_handle(
      XOpenDisplay(nullptr), &XCloseDisplay);
    if (!display_handle) {
      throw std::runtime_error("XOpenDisplay failed");
    }
    Display *display = display_handle.get();

    const int screen = DefaultScreen(display);
    const Window root = RootWindow(display, screen);
    XWindowAttributes attributes {};
    if (!XGetWindowAttributes(display, root, &attributes)) {
      throw std::runtime_error("XGetWindowAttributes failed");
    }

    const std::array<channel_t, 3> channels {
      make_channel("red", attributes.visual->red_mask),
      make_channel("green", attributes.visual->green_mask),
      make_channel("blue", attributes.visual->blue_mask),
    };
    const bool masks_are_10_bit = std::all_of(
      channels.begin(), channels.end(), [](const channel_t &channel) {
        return channel.bits == 10;
      });
    const bool masks_overlap =
      ((channels[0].mask & channels[1].mask) != 0) ||
      ((channels[0].mask & channels[2].mask) != 0) ||
      ((channels[1].mask & channels[2].mask) != 0);

    std::cout << std::fixed << std::setprecision(3)
              << "display=" << DisplayString(display) << '\n'
              << "root_width=" << attributes.width << '\n'
              << "root_height=" << attributes.height << '\n'
              << "root_depth=" << attributes.depth << '\n'
              << "server_image_byte_order=" << byte_order_name(ImageByteOrder(display)) << '\n';
    for (const auto &channel : channels) {
      std::cout << channel.name << "_mask=0x" << std::hex << channel.mask << std::dec << '\n'
                << channel.name << "_shift=" << channel.shift << '\n'
                << channel.name << "_bits=" << channel.bits << '\n';
    }
    std::cout << "masks_overlap=" << (masks_overlap ? "yes" : "no") << '\n'
              << "mit_shm_available=" << (XShmQueryExtension(display) ? "yes" : "no") << '\n';

    if (attributes.depth != 30 || !masks_are_10_bit || masks_overlap) {
      std::cerr << "result=fail (root is not a non-overlapping RGB 10:10:10 drawable)\n";
      return 2;
    }
    if (!XShmQueryExtension(display)) {
      std::cerr << "result=fail (MIT-SHM is unavailable)\n";
      return 2;
    }
    int composite_event_base = 0;
    int composite_error_base = 0;
    if (!XCompositeQueryExtension(display, &composite_event_base,
                                  &composite_error_base)) {
      std::cerr << "result=fail (XComposite is unavailable)\n";
      return 2;
    }
    const Window overlay = XCompositeGetOverlayWindow(display, root);
    XWindowAttributes overlay_attributes {};
    if (overlay == 0 ||
        !XGetWindowAttributes(display, overlay, &overlay_attributes)) {
      throw std::runtime_error("XComposite overlay discovery failed");
    }
    const std::array<channel_t, 3> overlay_channels {
      make_channel("red", overlay_attributes.visual->red_mask),
      make_channel("green", overlay_attributes.visual->green_mask),
      make_channel("blue", overlay_attributes.visual->blue_mask),
    };
    std::cout << "xcomposite_available=yes\n"
              << "overlay_width=" << overlay_attributes.width << '\n'
              << "overlay_height=" << overlay_attributes.height << '\n'
              << "overlay_depth=" << overlay_attributes.depth << '\n';
    for (const auto &channel : overlay_channels) {
      std::cout << "overlay_" << channel.name << "_mask=0x" << std::hex
                << channel.mask << std::dec << '\n'
                << "overlay_" << channel.name << "_bits=" << channel.bits << '\n';
    }
    const bool overlay_is_native_10_bit = overlay_attributes.depth == 30 &&
      std::equal(channels.begin(), channels.end(), overlay_channels.begin(),
                 [](const channel_t &left, const channel_t &right) {
                   return left.mask == right.mask && left.bits == right.bits;
                 });
    if (!overlay_is_native_10_bit ||
        overlay_attributes.width != attributes.width ||
        overlay_attributes.height != attributes.height) {
      std::cerr << "result=fail (XComposite overlay is not a matching depth-30 canvas)\n";
      return 2;
    }
    Window compositor_keepalive = 0;
    if (force_composite) {
      compositor_keepalive = XCreateSimpleWindow(
        display, root, 0, 0, 2, 2, 0, 0, 0xffffffffUL);
      if (compositor_keepalive == 0) {
        throw std::runtime_error("compositor keepalive window creation failed");
      }
      XSetWindowAttributes keepalive_attributes {};
      keepalive_attributes.override_redirect = True;
      XChangeWindowAttributes(display, compositor_keepalive,
                              CWOverrideRedirect, &keepalive_attributes);
      const Atom opacity_atom = XInternAtom(
        display, "_NET_WM_WINDOW_OPACITY", False);
      const unsigned long opacity = 0;
      XChangeProperty(display, compositor_keepalive, opacity_atom,
                      XA_CARDINAL, 32, PropModeReplace,
                      reinterpret_cast<const unsigned char *>(&opacity), 1);
      XMapRaised(display, compositor_keepalive);
      XSync(display, False);
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    const Drawable capture_drawable = requested_drawable.value_or(overlay);
    XWindowAttributes capture_attributes = overlay_attributes;
    if (requested_drawable &&
        !XGetWindowAttributes(display, capture_drawable, &capture_attributes)) {
      throw std::runtime_error("explicit capture drawable attributes failed");
    }
    const std::array<channel_t, 3> capture_channels {
      make_channel("red", capture_attributes.visual->red_mask),
      make_channel("green", capture_attributes.visual->green_mask),
      make_channel("blue", capture_attributes.visual->blue_mask),
    };
    const bool capture_is_native_10_bit = capture_attributes.depth == 30 &&
      std::equal(channels.begin(), channels.end(), capture_channels.begin(),
                 [](const channel_t &left, const channel_t &right) {
                   return left.mask == right.mask && left.bits == right.bits;
                 });
    std::cout << "capture_target="
              << (requested_drawable ? "explicit-window" : "xcomposite-overlay") << '\n'
              << "capture_drawable=0x" << std::hex << capture_drawable << std::dec << '\n'
              << "capture_width=" << capture_attributes.width << '\n'
              << "capture_height=" << capture_attributes.height << '\n'
              << "capture_depth=" << capture_attributes.depth << '\n';
    std::cout << "compositor_keepalive="
              << (force_composite ? "mapped" : "disabled") << '\n';
    if (!capture_is_native_10_bit) {
      std::cerr << "result=fail (capture drawable is not native RGB 10:10:10)\n";
      return 2;
    }

    const bool get_round_trip = controlled_round_trip(
      display, root, attributes.visual, attributes.depth, channels, false);
    const bool shm_round_trip = controlled_round_trip(
      display, root, attributes.visual, attributes.depth, channels, true);
    visible_round_trip_t visible_root_round_trip {false, false};
    visible_round_trip_t visible_overlay_round_trip {false, false};
    if (!requested_drawable) {
      visible_root_round_trip = visible_drawable_round_trip(
        display, root, root, attributes.visual, attributes.depth, channels);
      visible_overlay_round_trip = visible_drawable_round_trip(
        display, root, overlay, overlay_attributes.visual,
        overlay_attributes.depth, overlay_channels);
    }
    std::cout << "xgetimage_1024_code_round_trip=" << (get_round_trip ? "exact" : "failed") << '\n'
              << "xshm_1024_code_round_trip=" << (shm_round_trip ? "exact" : "failed") << '\n'
              << "visible_root_xgetimage_1024_code_round_trip="
              << (requested_drawable ? "skipped" :
                  visible_root_round_trip.xgetimage_exact ? "exact" : "altered") << '\n'
              << "visible_root_xshm_1024_code_round_trip="
              << (requested_drawable ? "skipped" :
                  visible_root_round_trip.xshm_exact ? "exact" : "altered") << '\n'
              << "visible_overlay_xgetimage_1024_code_round_trip="
              << (requested_drawable ? "skipped" :
                  visible_overlay_round_trip.xgetimage_exact ? "exact" : "altered") << '\n'
              << "visible_overlay_xshm_1024_code_round_trip="
              << (requested_drawable ? "skipped" :
                  visible_overlay_round_trip.xshm_exact ? "exact" : "altered") << '\n';

    shm_image_t root_shm(display, capture_attributes.visual,
                         capture_attributes.depth,
                         static_cast<unsigned int>(capture_attributes.width),
                         static_cast<unsigned int>(capture_attributes.height));
    std::vector<double> shm_times;
    std::set<std::uint64_t> frame_fingerprints;
    std::uint64_t previous_fingerprint = 0;
    int changed_frames = 0;
    shm_times.reserve(static_cast<std::size_t>(shm_frames));
    auto next_capture = clock_type::now();
    for (int frame = 0; frame < shm_frames; ++frame) {
      if (capture_fps > 0) {
        std::this_thread::sleep_until(next_capture);
        next_capture += std::chrono::nanoseconds(1000000000LL / capture_fps);
      }
      const auto start = clock_type::now();
      if (!root_shm.capture(capture_drawable, 0, 0)) {
        throw std::runtime_error("capture drawable XShmGetImage failed");
      }
      const auto stop = clock_type::now();
      shm_times.push_back(std::chrono::duration<double, std::milli>(stop - start).count());
      const auto fingerprint = sample_fingerprint(root_shm.get());
      frame_fingerprints.insert(fingerprint);
      if (frame != 0 && fingerprint != previous_fingerprint) {
        ++changed_frames;
      }
      previous_fingerprint = fingerprint;
    }

    XImage *root_get_image = nullptr;
    std::vector<double> get_times;
    get_times.reserve(static_cast<std::size_t>(get_frames));
    for (int frame = 0; frame < get_frames; ++frame) {
      const auto start = clock_type::now();
      XImage *image = XGetImage(display, capture_drawable, 0, 0,
                               static_cast<unsigned int>(capture_attributes.width),
                               static_cast<unsigned int>(capture_attributes.height),
                               AllPlanes, ZPixmap);
      const auto stop = clock_type::now();
      if (image == nullptr) {
        throw std::runtime_error("capture drawable XGetImage failed");
      }
      if (root_get_image != nullptr) {
        XDestroyImage(root_get_image);
      }
      root_get_image = image;
      get_times.push_back(std::chrono::duration<double, std::milli>(stop - start).count());
    }

    XImage *shm_image = root_shm.get();
    const auto frame_bytes = static_cast<std::size_t>(shm_image->bytes_per_line) *
                             static_cast<std::size_t>(shm_image->height);
    std::cout << "captured_depth=" << shm_image->depth << '\n'
              << "captured_bits_per_pixel=" << shm_image->bits_per_pixel << '\n'
              << "captured_bytes_per_line=" << shm_image->bytes_per_line << '\n'
              << "captured_frame_bytes=" << frame_bytes << '\n'
              << "captured_byte_order=" << byte_order_name(shm_image->byte_order) << '\n';
    print_timing("xshm", summarize(shm_times), frame_bytes, shm_frames);
    std::cout << "xshm_requested_fps=" << capture_fps << '\n';
    std::cout << "xshm_distinct_sampled_frames=" << frame_fingerprints.size() << '\n'
              << "xshm_sampled_frame_transitions=" << changed_frames << '\n';
    print_timing("xgetimage", summarize(get_times), frame_bytes, get_frames);
    analyze_capture_image(shm_image, capture_channels);
    benchmark_host_processing(shm_image, capture_channels);

    if (root_get_image != nullptr) {
      XDestroyImage(root_get_image);
    }
    if (compositor_keepalive != 0) {
      XDestroyWindow(display, compositor_keepalive);
      XSync(display, False);
    }
    const bool visible_gate = requested_drawable ||
      (visible_overlay_round_trip.xgetimage_exact &&
       visible_overlay_round_trip.xshm_exact);
    const bool pass = get_round_trip && shm_round_trip && visible_gate &&
                      shm_image->depth == 30 && shm_image->bits_per_pixel == 32;
    std::cout << "result=" << (pass ? "pass" : "fail") << '\n';
    return pass ? 0 : 2;
  } catch (const std::exception &error) {
    std::cerr << "result=error\nerror=" << error.what() << '\n';
    return 1;
  }
}
