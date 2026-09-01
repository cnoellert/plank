#include <array>
#include <cerrno>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <iostream>
#include <linux/input.h>
#include <string>
#include <sys/ioctl.h>
#include <unistd.h>
#include <vector>

namespace {

constexpr std::size_t bits_per_word = sizeof(unsigned long) * 8U;

bool bit_is_set(const std::vector<unsigned long>& bits, unsigned int bit) {
  return bit / bits_per_word < bits.size() &&
         (bits[bit / bits_per_word] & (1UL << (bit % bits_per_word))) != 0UL;
}

std::vector<unsigned long> get_bits(int fd, unsigned int event_type,
                                    unsigned int maximum) {
  std::vector<unsigned long> bits(maximum / bits_per_word + 1U);
  if (ioctl(fd, EVIOCGBIT(event_type, bits.size() * sizeof(unsigned long)),
            bits.data()) < 0) {
    bits.clear();
  }
  return bits;
}

void print_absolute_axis(int fd, const std::vector<unsigned long>& absolute_bits,
                         unsigned int axis, const char* name) {
  if (!bit_is_set(absolute_bits, axis)) {
    return;
  }
  input_absinfo information{};
  if (ioctl(fd, EVIOCGABS(axis), &information) == 0) {
    std::cout << "    " << name << "=yes range=" << information.minimum << ':'
              << information.maximum << " resolution=" << information.resolution
              << '\n';
  }
}

}  // namespace

int main() {
  DIR* input_directory = opendir("/dev/input");
  if (input_directory == nullptr) {
    std::cerr << "cannot open /dev/input: " << std::strerror(errno) << '\n';
    return 2;
  }

  int matching_devices = 0;
  while (const dirent* entry = readdir(input_directory)) {
    const std::string filename = entry->d_name;
    if (filename.rfind("event", 0) != 0) {
      continue;
    }
    const std::string path = "/dev/input/" + filename;
    const int fd = open(path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
      continue;
    }

    std::array<char, 256> name{};
    input_id identifier{};
    if (ioctl(fd, EVIOCGNAME(name.size()), name.data()) < 0 ||
        ioctl(fd, EVIOCGID, &identifier) < 0) {
      close(fd);
      continue;
    }
    const std::string device_name = name.data();
    const bool is_wacom = identifier.vendor == 0x056aU ||
                          device_name.find("Wacom") != std::string::npos;
    if (!is_wacom) {
      close(fd);
      continue;
    }

    ++matching_devices;
    std::cout << "  device=" << path << " name=\"" << device_name << "\""
              << " bus=0x" << std::hex << identifier.bustype << " vendor=0x"
              << identifier.vendor << " product=0x" << identifier.product
              << " version=0x" << identifier.version << std::dec << '\n';

    const std::vector<unsigned long> event_bits = get_bits(fd, 0, EV_MAX);
    const std::vector<unsigned long> key_bits = get_bits(fd, EV_KEY, KEY_MAX);
    const std::vector<unsigned long> absolute_bits =
        get_bits(fd, EV_ABS, ABS_MAX);
    std::cout << "    tablet_tool="
              << (bit_is_set(key_bits, BTN_TOOL_PEN) ? "yes" : "no")
              << " eraser="
              << (bit_is_set(key_bits, BTN_TOOL_RUBBER) ? "yes" : "no")
              << " touch="
              << (bit_is_set(key_bits, BTN_TOOL_FINGER) ? "yes" : "no")
              << " keys=" << (bit_is_set(event_bits, EV_KEY) ? "yes" : "no")
              << " absolute="
              << (bit_is_set(event_bits, EV_ABS) ? "yes" : "no") << '\n';
    print_absolute_axis(fd, absolute_bits, ABS_X, "x");
    print_absolute_axis(fd, absolute_bits, ABS_Y, "y");
    print_absolute_axis(fd, absolute_bits, ABS_PRESSURE, "pressure");
    print_absolute_axis(fd, absolute_bits, ABS_DISTANCE, "distance");
    print_absolute_axis(fd, absolute_bits, ABS_TILT_X, "tilt_x");
    print_absolute_axis(fd, absolute_bits, ABS_TILT_Y, "tilt_y");
    print_absolute_axis(fd, absolute_bits, ABS_WHEEL, "wheel");
    close(fd);
  }
  closedir(input_directory);
  std::cout << "wacom_event_devices=" << matching_devices << '\n';
  return matching_devices > 0 ? 0 : 3;
}

