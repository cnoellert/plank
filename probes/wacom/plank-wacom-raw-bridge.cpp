#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <linux/hidraw.h>
#include <linux/input.h>
#include <linux/uhid.h>
#include <netdb.h>
#include <optional>
#include <poll.h>
#include <string>
#include <string_view>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>
#include <vector>

namespace {

constexpr std::uint32_t kMagic = 0x504c5748;
constexpr std::uint16_t kVersion = 1;
constexpr std::size_t kMaximumPayload = UHID_DATA_MAX + 64;

enum class MessageType : std::uint16_t {
  device = 1,
  descriptor = 2,
  input = 3,
  get_report = 4,
  get_report_reply = 5,
  set_report = 6,
  set_report_reply = 7,
  output = 8,
  detach = 9,
};

#pragma pack(push, 1)
struct WireHeader {
  std::uint32_t magic;
  std::uint16_t version;
  std::uint16_t type;
  std::uint16_t interface;
  std::uint16_t reserved;
  std::uint32_t transaction;
  std::uint32_t size;
};

struct DeviceMessage {
  std::uint16_t interface_count;
  std::uint16_t bus;
  std::uint32_t vendor;
  std::uint32_t product;
  std::uint32_t version;
  std::uint32_t country;
  char name[128];
  char physical[64];
  char unique[64];
};
#pragma pack(pop)

struct Frame {
  MessageType type{};
  std::uint16_t interface = 0;
  std::uint32_t transaction = 0;
  std::vector<std::uint8_t> payload;
};

bool write_all(int fd, const void* data, std::size_t size) {
  const auto* bytes = static_cast<const std::uint8_t*>(data);
  while (size > 0) {
    const ssize_t written = send(fd, bytes, size, MSG_NOSIGNAL);
    if (written < 0 && errno == EINTR) {
      continue;
    }
    if (written <= 0) {
      return false;
    }
    bytes += written;
    size -= static_cast<std::size_t>(written);
  }
  return true;
}

bool read_all(int fd, void* data, std::size_t size) {
  auto* bytes = static_cast<std::uint8_t*>(data);
  while (size > 0) {
    const ssize_t received = recv(fd, bytes, size, 0);
    if (received < 0 && errno == EINTR) {
      continue;
    }
    if (received <= 0) {
      return false;
    }
    bytes += received;
    size -= static_cast<std::size_t>(received);
  }
  return true;
}

bool send_frame(int fd, MessageType type, std::uint16_t interface,
                std::uint32_t transaction, const void* payload,
                std::size_t size) {
  if (size > kMaximumPayload) {
    return false;
  }
  const WireHeader header{
      kMagic, kVersion, static_cast<std::uint16_t>(type), interface, 0,
      transaction, static_cast<std::uint32_t>(size)};
  return write_all(fd, &header, sizeof(header)) &&
         (size == 0 || write_all(fd, payload, size));
}

bool receive_frame(int fd, Frame& frame) {
  WireHeader header{};
  if (!read_all(fd, &header, sizeof(header))) {
    return false;
  }
  if (header.magic != kMagic || header.version != kVersion ||
      header.size > kMaximumPayload) {
    std::cerr << "invalid bridge frame\n";
    return false;
  }
  frame.type = static_cast<MessageType>(header.type);
  frame.interface = header.interface;
  frame.transaction = header.transaction;
  frame.payload.resize(header.size);
  return header.size == 0 || read_all(fd, frame.payload.data(), header.size);
}

int connect_tcp(const char* host, const char* service) {
  addrinfo hints{};
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  addrinfo* addresses = nullptr;
  if (getaddrinfo(host, service, &hints, &addresses) != 0) {
    return -1;
  }
  int result = -1;
  for (addrinfo* address = addresses; address != nullptr;
       address = address->ai_next) {
    const int fd = socket(address->ai_family, address->ai_socktype,
                          address->ai_protocol);
    if (fd >= 0 && connect(fd, address->ai_addr, address->ai_addrlen) == 0) {
      result = fd;
      break;
    }
    if (fd >= 0) {
      close(fd);
    }
  }
  freeaddrinfo(addresses);
  return result;
}

int listen_tcp(const char* host, const char* service) {
  addrinfo hints{};
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_PASSIVE;
  addrinfo* addresses = nullptr;
  if (getaddrinfo(host, service, &hints, &addresses) != 0) {
    return -1;
  }
  int result = -1;
  for (addrinfo* address = addresses; address != nullptr;
       address = address->ai_next) {
    const int fd = socket(address->ai_family, address->ai_socktype,
                          address->ai_protocol);
    const int enabled = 1;
    if (fd >= 0) {
      setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof(enabled));
    }
    if (fd >= 0 && bind(fd, address->ai_addr, address->ai_addrlen) == 0 &&
        listen(fd, 1) == 0) {
      result = fd;
      break;
    }
    if (fd >= 0) {
      close(fd);
    }
  }
  freeaddrinfo(addresses);
  return result;
}

template <std::size_t Size>
void copy_ioctl_string(int fd, unsigned long request, char (&destination)[Size]) {
  std::array<char, Size> value{};
  if (ioctl(fd, request, value.data()) >= 0) {
    std::memcpy(destination, value.data(), Size);
    destination[Size - 1] = '\0';
  }
}

std::string physical_group(std::string_view physical) {
  const std::size_t input_suffix = physical.rfind("/input");
  return std::string{physical.substr(0, input_suffix)};
}

std::optional<std::uint32_t> read_input_version(
    const std::string& hidraw_path) {
  const std::filesystem::path input_root =
      std::filesystem::path{"/sys/class/hidraw"} /
      std::filesystem::path{hidraw_path}.filename() / "device/input";
  std::error_code error;
  for (std::filesystem::directory_iterator entry{input_root, error};
       !error && entry != std::filesystem::directory_iterator{};
       entry.increment(error)) {
    std::ifstream version_stream{entry->path() / "id/version"};
    std::string version;
    if (version_stream >> version) {
      char* end = nullptr;
      const unsigned long value = std::strtoul(version.c_str(), &end, 16);
      if (end != version.c_str() && *end == '\0' && value <= 0xffffffffUL) {
        return static_cast<std::uint32_t>(value);
      }
    }
  }
  return std::nullopt;
}

bool write_uhid_event(int fd, const uhid_event& event) {
  const ssize_t written = write(fd, &event, sizeof(event));
  if (written != static_cast<ssize_t>(sizeof(event))) {
    std::cerr << "UHID write failed: " << std::strerror(errno) << '\n';
    return false;
  }
  return true;
}

unsigned long get_report_ioctl(std::uint8_t type, std::size_t size) {
  switch (type) {
    case UHID_FEATURE_REPORT:
      return HIDIOCGFEATURE(size);
    case UHID_OUTPUT_REPORT:
      return HIDIOCGOUTPUT(size);
    case UHID_INPUT_REPORT:
      return HIDIOCGINPUT(size);
    default:
      return 0;
  }
}

unsigned long set_report_ioctl(std::uint8_t type, std::size_t size) {
  switch (type) {
    case UHID_FEATURE_REPORT:
      return HIDIOCSFEATURE(size);
    case UHID_OUTPUT_REPORT:
      return HIDIOCSOUTPUT(size);
    case UHID_INPUT_REPORT:
      return HIDIOCSINPUT(size);
    default:
      return 0;
  }
}

int run_client(const char* host, const char* service,
               const std::vector<std::string>& hidraw_paths,
               const std::vector<std::string>& grab_paths) {
  std::vector<int> hidraw_fds;
  std::vector<std::vector<std::uint8_t>> descriptors;
  DeviceMessage device{};
  device.interface_count = static_cast<std::uint16_t>(hidraw_paths.size());
  std::string expected_physical_group;
  std::string expected_unique;

  for (const std::string& path : hidraw_paths) {
    const int fd = open(path.c_str(), O_RDWR | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) {
      std::cerr << "cannot open " << path << ": " << std::strerror(errno)
                << '\n';
      return 3;
    }
    hidraw_fds.push_back(fd);
    hidraw_devinfo info{};
    if (ioctl(fd, HIDIOCGRAWINFO, &info) < 0) {
      std::cerr << "cannot read HID identity from " << path << '\n';
      return 3;
    }
    std::array<char, 64> interface_physical{};
    std::array<char, 64> interface_unique{};
    ioctl(fd, HIDIOCGRAWPHYS(interface_physical.size()),
          interface_physical.data());
    ioctl(fd, HIDIOCGRAWUNIQ(interface_unique.size()), interface_unique.data());
    interface_physical.back() = '\0';
    interface_unique.back() = '\0';
    const std::string current_physical_group =
        physical_group(interface_physical.data());
    const std::string current_unique = interface_unique.data();
    if (hidraw_fds.size() == 1) {
      device.bus = info.bustype;
      device.vendor = static_cast<std::uint16_t>(info.vendor);
      device.product = static_cast<std::uint16_t>(info.product);
      device.version = read_input_version(path).value_or(0);
      copy_ioctl_string(fd, HIDIOCGRAWNAME(sizeof(device.name)), device.name);
      copy_ioctl_string(fd, HIDIOCGRAWPHYS(sizeof(device.physical)),
                        device.physical);
      copy_ioctl_string(fd, HIDIOCGRAWUNIQ(sizeof(device.unique)), device.unique);
      expected_physical_group = current_physical_group;
      expected_unique = current_unique;
    } else if (device.bus != info.bustype ||
               device.vendor != static_cast<std::uint16_t>(info.vendor) ||
               device.product != static_cast<std::uint16_t>(info.product) ||
               current_physical_group != expected_physical_group ||
               (!expected_unique.empty() && current_unique != expected_unique)) {
      std::cerr << "all HID interfaces must belong to the same physical USB "
                   "tablet\n";
      return 3;
    }

    int descriptor_size = 0;
    if (ioctl(fd, HIDIOCGRDESCSIZE, &descriptor_size) < 0 ||
        descriptor_size <= 0 || descriptor_size > HID_MAX_DESCRIPTOR_SIZE) {
      std::cerr << "cannot read descriptor size from " << path << '\n';
      return 3;
    }
    hidraw_report_descriptor descriptor{};
    descriptor.size = descriptor_size;
    if (ioctl(fd, HIDIOCGRDESC, &descriptor) < 0) {
      std::cerr << "cannot read descriptor from " << path << '\n';
      return 3;
    }
    descriptors.emplace_back(descriptor.value,
                             descriptor.value + descriptor.size);
  }

  std::vector<int> grab_fds;
  for (const std::string& path : grab_paths) {
    const int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NONBLOCK);
    const int enabled = 1;
    if (fd < 0 || ioctl(fd, EVIOCGRAB, enabled) < 0) {
      std::cerr << "cannot exclusively grab " << path << ": "
                << std::strerror(errno) << '\n';
      return 3;
    }
    grab_fds.push_back(fd);
  }

  const int socket_fd = connect_tcp(host, service);
  if (socket_fd < 0) {
    std::cerr << "cannot connect to bridge host\n";
    return 4;
  }
  if (!send_frame(socket_fd, MessageType::device, 0, 0, &device,
                  sizeof(device))) {
    return 5;
  }
  for (std::size_t index = 0; index < descriptors.size(); ++index) {
    if (!send_frame(socket_fd, MessageType::descriptor,
                    static_cast<std::uint16_t>(index), 0,
                    descriptors[index].data(), descriptors[index].size())) {
      return 5;
    }
  }
  std::cout << "client_attached model=" << device.name
            << " interfaces=" << descriptors.size() << '\n';

  std::vector<pollfd> poll_fds{{socket_fd, POLLIN, 0}};
  for (int fd : hidraw_fds) {
    poll_fds.push_back({fd, POLLIN, 0});
  }
  std::array<std::uint8_t, UHID_DATA_MAX> report{};
  while (poll(poll_fds.data(), poll_fds.size(), -1) >= 0) {
    if ((poll_fds[0].revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
      break;
    }
    if ((poll_fds[0].revents & POLLIN) != 0) {
      Frame frame;
      if (!receive_frame(socket_fd, frame) ||
          frame.interface >= hidraw_fds.size()) {
        break;
      }
      const int hidraw_fd = hidraw_fds[frame.interface];
      if (frame.type == MessageType::get_report && frame.payload.size() == 2) {
        report.fill(0);
        report[0] = frame.payload[0];
        const unsigned long request =
            get_report_ioctl(frame.payload[1], report.size());
        errno = 0;
        const int result = request == 0 ? -1
                                        : ioctl(hidraw_fd, request, report.data());
        const std::int32_t error = result < 0 ? (request == 0 ? EINVAL : errno) : 0;
        std::vector<std::uint8_t> reply(sizeof(error) +
                                        std::max(result, 0));
        std::memcpy(reply.data(), &error, sizeof(error));
        if (result > 0) {
          std::memcpy(reply.data() + sizeof(error), report.data(), result);
        }
        if (!send_frame(socket_fd, MessageType::get_report_reply,
                        frame.interface, frame.transaction, reply.data(),
                        reply.size())) {
          break;
        }
      } else if ((frame.type == MessageType::set_report ||
                  frame.type == MessageType::output) &&
                 frame.payload.size() >= 2) {
        const unsigned long request = set_report_ioctl(
            frame.payload[0], frame.payload.size() - 1);
        errno = 0;
        const int result =
            request == 0
                ? -1
                : ioctl(hidraw_fd, request, frame.payload.data() + 1);
        if (frame.type == MessageType::set_report) {
          const std::int32_t error =
              result < 0 ? (request == 0 ? EINVAL : errno) : 0;
          if (!send_frame(socket_fd, MessageType::set_report_reply,
                          frame.interface, frame.transaction, &error,
                          sizeof(error))) {
            break;
          }
        }
      }
    }
    for (std::size_t index = 0; index < hidraw_fds.size(); ++index) {
      if ((poll_fds[index + 1].revents & POLLIN) == 0) {
        continue;
      }
      const ssize_t bytes = read(hidraw_fds[index], report.data(), report.size());
      if (bytes > 0 &&
          !send_frame(socket_fd, MessageType::input,
                      static_cast<std::uint16_t>(index), 0, report.data(),
                      static_cast<std::size_t>(bytes))) {
        break;
      }
    }
  }
  send_frame(socket_fd, MessageType::detach, 0, 0, nullptr, 0);
  for (int fd : grab_fds) {
    const int disabled = 0;
    ioctl(fd, EVIOCGRAB, disabled);
    close(fd);
  }
  for (int fd : hidraw_fds) {
    close(fd);
  }
  close(socket_fd);
  return 0;
}

int run_host(const char* address, const char* service) {
  const int listen_fd = listen_tcp(address, service);
  if (listen_fd < 0) {
    std::cerr << "cannot listen for bridge client\n";
    return 4;
  }
  std::cerr << "qualification-only plaintext bridge listening on " << address
            << ':' << service << '\n';
  const int socket_fd = accept4(listen_fd, nullptr, nullptr, SOCK_CLOEXEC);
  close(listen_fd);
  if (socket_fd < 0) {
    return 4;
  }

  Frame frame;
  if (!receive_frame(socket_fd, frame) || frame.type != MessageType::device ||
      frame.payload.size() != sizeof(DeviceMessage)) {
    std::cerr << "missing device metadata\n";
    return 5;
  }
  DeviceMessage device{};
  std::memcpy(&device, frame.payload.data(), sizeof(device));
  device.name[sizeof(device.name) - 1] = '\0';
  device.physical[sizeof(device.physical) - 1] = '\0';
  device.unique[sizeof(device.unique) - 1] = '\0';
  if (device.interface_count == 0 || device.interface_count > 16) {
    return 5;
  }
  std::vector<std::vector<std::uint8_t>> descriptors(device.interface_count);
  for (std::size_t count = 0; count < descriptors.size(); ++count) {
    if (!receive_frame(socket_fd, frame) ||
        frame.type != MessageType::descriptor ||
        frame.interface >= descriptors.size() || frame.payload.empty() ||
        frame.payload.size() > HID_MAX_DESCRIPTOR_SIZE) {
      return 5;
    }
    descriptors[frame.interface] = std::move(frame.payload);
  }

  std::vector<int> uhid_fds;
  for (std::size_t index = 0; index < descriptors.size(); ++index) {
    if (descriptors[index].empty()) {
      return 5;
    }
    const int fd = open("/dev/uhid", O_RDWR | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) {
      std::cerr << "cannot open /dev/uhid: " << std::strerror(errno) << '\n';
      return 6;
    }
    uhid_fds.push_back(fd);
    uhid_event create{};
    create.type = UHID_CREATE2;
    std::memcpy(create.u.create2.name, device.name, sizeof(device.name));
    const std::string physical = "plank/raw-wacom";
    std::memcpy(create.u.create2.phys, physical.data(), physical.size());
    std::memcpy(create.u.create2.uniq, device.unique, sizeof(device.unique));
    create.u.create2.rd_size =
        static_cast<std::uint16_t>(descriptors[index].size());
    create.u.create2.bus = device.bus;
    create.u.create2.vendor = device.vendor;
    create.u.create2.product = device.product;
    create.u.create2.version = device.version;
    create.u.create2.country = device.country;
    std::memcpy(create.u.create2.rd_data, descriptors[index].data(),
                descriptors[index].size());
    if (!write_uhid_event(fd, create)) {
      return 6;
    }
  }
  std::cout << "host_created model=" << device.name
            << " interfaces=" << descriptors.size() << '\n';

  std::vector<pollfd> poll_fds{{socket_fd, POLLIN, 0}};
  for (int fd : uhid_fds) {
    poll_fds.push_back({fd, POLLIN, 0});
  }
  bool running = true;
  while (running && poll(poll_fds.data(), poll_fds.size(), -1) >= 0) {
    if ((poll_fds[0].revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
      break;
    }
    if ((poll_fds[0].revents & POLLIN) != 0) {
      if (!receive_frame(socket_fd, frame)) {
        break;
      }
      if (frame.type == MessageType::detach) {
        running = false;
      } else if (frame.interface >= uhid_fds.size()) {
        break;
      } else if (frame.type == MessageType::input) {
        uhid_event input{};
        input.type = UHID_INPUT2;
        input.u.input2.size = static_cast<std::uint16_t>(frame.payload.size());
        std::memcpy(input.u.input2.data, frame.payload.data(),
                    frame.payload.size());
        write_uhid_event(uhid_fds[frame.interface], input);
      } else if (frame.type == MessageType::get_report_reply &&
                 frame.payload.size() >= sizeof(std::int32_t)) {
        std::int32_t error = EIO;
        std::memcpy(&error, frame.payload.data(), sizeof(error));
        uhid_event reply{};
        reply.type = UHID_GET_REPORT_REPLY;
        reply.u.get_report_reply.id = frame.transaction;
        reply.u.get_report_reply.err = static_cast<std::uint16_t>(error);
        reply.u.get_report_reply.size = static_cast<std::uint16_t>(
            frame.payload.size() - sizeof(error));
        std::memcpy(reply.u.get_report_reply.data,
                    frame.payload.data() + sizeof(error),
                    frame.payload.size() - sizeof(error));
        write_uhid_event(uhid_fds[frame.interface], reply);
      } else if (frame.type == MessageType::set_report_reply &&
                 frame.payload.size() == sizeof(std::int32_t)) {
        std::int32_t error = EIO;
        std::memcpy(&error, frame.payload.data(), sizeof(error));
        uhid_event reply{};
        reply.type = UHID_SET_REPORT_REPLY;
        reply.u.set_report_reply.id = frame.transaction;
        reply.u.set_report_reply.err = static_cast<std::uint16_t>(error);
        write_uhid_event(uhid_fds[frame.interface], reply);
      }
    }
    for (std::size_t index = 0; index < uhid_fds.size(); ++index) {
      if ((poll_fds[index + 1].revents & POLLIN) == 0) {
        continue;
      }
      uhid_event event{};
      const ssize_t bytes = read(uhid_fds[index], &event, sizeof(event));
      if (bytes < static_cast<ssize_t>(sizeof(event.type))) {
        continue;
      }
      if (event.type == UHID_START) {
        std::cout << "uhid_started interface=" << index << '\n';
      } else if (event.type == UHID_GET_REPORT) {
        const std::array<std::uint8_t, 2> request{
            event.u.get_report.rnum, event.u.get_report.rtype};
        send_frame(socket_fd, MessageType::get_report,
                   static_cast<std::uint16_t>(index), event.u.get_report.id,
                   request.data(), request.size());
      } else if (event.type == UHID_SET_REPORT) {
        std::vector<std::uint8_t> request{event.u.set_report.rtype};
        request.insert(request.end(), event.u.set_report.data,
                       event.u.set_report.data + event.u.set_report.size);
        send_frame(socket_fd, MessageType::set_report,
                   static_cast<std::uint16_t>(index), event.u.set_report.id,
                   request.data(), request.size());
      } else if (event.type == UHID_OUTPUT) {
        std::vector<std::uint8_t> output{event.u.output.rtype};
        output.insert(output.end(), event.u.output.data,
                      event.u.output.data + event.u.output.size);
        send_frame(socket_fd, MessageType::output,
                   static_cast<std::uint16_t>(index), 0, output.data(),
                   output.size());
      }
    }
  }

  uhid_event destroy{};
  destroy.type = UHID_DESTROY;
  for (int fd : uhid_fds) {
    write_uhid_event(fd, destroy);
    close(fd);
  }
  close(socket_fd);
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc == 5 && std::string_view(argv[1]) == "--listen" &&
      std::string_view(argv[4]) == "--allow-insecure-qualification") {
    return run_host(argv[2], argv[3]);
  }
  if (argc >= 7 && std::string_view(argv[1]) == "--connect") {
    std::vector<std::string> hidraw_paths;
    std::vector<std::string> grab_paths;
    for (int index = 4; index < argc; ++index) {
      const std::string_view argument = argv[index];
      if (argument == "--hidraw" && index + 1 < argc) {
        hidraw_paths.emplace_back(argv[++index]);
      } else if (argument == "--grab" && index + 1 < argc) {
        grab_paths.emplace_back(argv[++index]);
      } else {
        std::cerr << "unknown client option: " << argument << '\n';
        return 2;
      }
    }
    if (hidraw_paths.empty()) {
      return 2;
    }
    return run_client(argv[2], argv[3], hidraw_paths, grab_paths);
  }
  std::cerr
      << "usage:\n  " << argv[0]
      << " --listen ADDRESS PORT --allow-insecure-qualification\n  "
      << argv[0]
      << " --connect HOST PORT --hidraw DEVICE... [--grab EVENT]...\n";
  return 2;
}
