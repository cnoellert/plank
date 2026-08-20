#include <array>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <linux/uhid.h>
#include <poll.h>
#include <string>
#include <string_view>
#include <unistd.h>
#include <vector>

namespace {

bool write_event(int fd, const uhid_event& event) {
  const ssize_t written = write(fd, &event, sizeof(event));
  if (written != static_cast<ssize_t>(sizeof(event))) {
    std::cerr << "UHID write failed: " << std::strerror(errno) << '\n';
    return false;
  }
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  bool generic_descriptor = false;
  std::vector<const char*> descriptor_paths;
  std::uint32_t requested_product = 0x0317;
  for (int index = 1; index < argc; ++index) {
    const std::string_view argument = argv[index];
    if (argument == "--generic") {
      generic_descriptor = true;
    } else if (argument == "--product" && index + 1 < argc) {
      char* end = nullptr;
      const unsigned long value = std::strtoul(argv[++index], &end, 16);
      if (end == argv[index] || *end != '\0' || value > 0xffff) {
        std::cerr << "invalid hexadecimal product ID\n";
        return 2;
      }
      requested_product = static_cast<std::uint32_t>(value);
    } else if (argument == "--self-test-mouse" ||
               argument.rfind("--", 0) != 0) {
      descriptor_paths.push_back(argv[index]);
    } else {
      std::cerr << "unknown option: " << argument << '\n';
      return 2;
    }
  }
  if (descriptor_paths.empty() ||
      (std::string_view(descriptor_paths.front()) == "--self-test-mouse" &&
       descriptor_paths.size() != 1)) {
    std::cerr << "usage: " << argv[0]
              << " [--generic] [--product HEX] "
                 "REPORT_DESCRIPTOR...|--self-test-mouse\n";
    return 2;
  }
  std::vector<std::vector<std::uint8_t>> descriptors;
  std::string name = "StationConnect Virtual Wacom Tablet";
  std::uint32_t vendor = 0x056a;
  std::uint32_t product = requested_product;
  if (std::string_view(descriptor_paths.front()) == "--self-test-mouse") {
    descriptors.push_back(
        {0x05, 0x01, 0x09, 0x02, 0xa1, 0x01, 0x09, 0x01, 0xa1,
         0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x03, 0x15, 0x00,
         0x25, 0x01, 0x95, 0x03, 0x75, 0x01, 0x81, 0x02, 0x95,
         0x01, 0x75, 0x05, 0x81, 0x01, 0x05, 0x01, 0x09, 0x30,
         0x09, 0x31, 0x15, 0x81, 0x25, 0x7f, 0x75, 0x08, 0x95,
         0x02, 0x81, 0x06, 0xc0, 0xc0});
    name = "StationConnect UHID Self-Test Mouse";
    vendor = 0x15d9;
    product = 0x0a37;
  } else {
    for (const char* descriptor_path : descriptor_paths) {
      std::ifstream descriptor_stream(descriptor_path, std::ios::binary);
      std::vector<std::uint8_t> descriptor{
          std::istreambuf_iterator<char>(descriptor_stream),
          std::istreambuf_iterator<char>()};
      if (descriptor_stream.bad() || descriptor.empty() ||
          descriptor.size() > HID_MAX_DESCRIPTOR_SIZE) {
        std::cerr << "invalid or unreadable HID report descriptor: "
                  << descriptor_path << '\n';
        return 3;
      }
      descriptors.push_back(std::move(descriptor));
    }
    if (generic_descriptor) {
      name = "StationConnect Generic HID Tablet";
      vendor = 0x1209;
      product = 0x5343;
    }
  }

  std::vector<int> devices;
  const std::string physical = "stationconnect/uhid0";
  for (std::size_t index = 0; index < descriptors.size(); ++index) {
    const int fd = open("/dev/uhid", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
      std::cerr << "cannot open /dev/uhid: " << std::strerror(errno) << '\n';
      return 4;
    }
    devices.push_back(fd);

    uhid_event create{};
    create.type = UHID_CREATE2;
    std::memcpy(create.u.create2.name, name.data(), name.size());
    std::memcpy(create.u.create2.phys, physical.data(), physical.size());
    create.u.create2.rd_size =
        static_cast<std::uint16_t>(descriptors[index].size());
    create.u.create2.bus = BUS_USB;
    create.u.create2.vendor = vendor;
    create.u.create2.product = product;
    create.u.create2.version = 0x0110;
    std::memcpy(create.u.create2.rd_data, descriptors[index].data(),
                descriptors[index].size());
    if (!write_event(fd, create)) {
      return 5;
    }
    std::cout << "uhid_create=pass interface=" << index
              << " descriptor_bytes=" << descriptors[index].size() << '\n';
  }

  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(8);
  int start_events = 0;
  int report_requests = 0;
  std::vector<pollfd> descriptor_polls;
  for (int fd : devices) {
    descriptor_polls.push_back({fd, POLLIN, 0});
  }
  while (std::chrono::steady_clock::now() < deadline) {
    const int poll_result = poll(descriptor_polls.data(),
                                 descriptor_polls.size(), 250);
    if (poll_result <= 0) {
      continue;
    }
    for (std::size_t index = 0; index < descriptor_polls.size(); ++index) {
      if ((descriptor_polls[index].revents & POLLIN) == 0) {
        continue;
      }
      uhid_event event{};
      const ssize_t bytes = read(devices[index], &event, sizeof(event));
      if (bytes < static_cast<ssize_t>(sizeof(event.type))) {
        continue;
      }
      switch (event.type) {
        case UHID_START:
          ++start_events;
          std::cout << "uhid_start=received interface=" << index
                    << " flags=0x" << std::hex << event.u.start.dev_flags
                    << std::dec << '\n';
          break;
        case UHID_OPEN:
          std::cout << "uhid_open=received interface=" << index << '\n';
          break;
        case UHID_CLOSE:
          std::cout << "uhid_close=received interface=" << index << '\n';
          break;
        case UHID_OUTPUT:
          std::cout << "uhid_output=received interface=" << index
                    << " size=" << event.u.output.size << '\n';
          break;
        case UHID_GET_REPORT: {
          ++report_requests;
          uhid_event reply{};
          reply.type = UHID_GET_REPORT_REPLY;
          reply.u.get_report_reply.id = event.u.get_report.id;
          reply.u.get_report_reply.err = EIO;
          write_event(devices[index], reply);
          std::cout << "uhid_get_report=declined interface=" << index
                    << " report="
                    << static_cast<unsigned int>(event.u.get_report.rnum)
                    << '\n';
          break;
        }
        case UHID_SET_REPORT: {
          ++report_requests;
          uhid_event reply{};
          reply.type = UHID_SET_REPORT_REPLY;
          reply.u.set_report_reply.id = event.u.set_report.id;
          reply.u.set_report_reply.err = EIO;
          write_event(devices[index], reply);
          std::cout << "uhid_set_report=declined interface=" << index
                    << " report="
                    << static_cast<unsigned int>(event.u.set_report.rnum)
                    << '\n';
          break;
        }
        default:
          break;
      }
    }
  }

  uhid_event destroy{};
  destroy.type = UHID_DESTROY;
  bool destroyed = true;
  for (std::size_t index = 0; index < devices.size(); ++index) {
    const bool interface_destroyed = write_event(devices[index], destroy);
    close(devices[index]);
    destroyed = interface_destroyed && destroyed;
    std::cout << "uhid_destroy="
              << (interface_destroyed ? "pass" : "fail")
              << " interface=" << index << '\n';
  }
  std::cout << "uhid_start_events=" << start_events
            << " report_requests=" << report_requests << '\n';
  return destroyed && start_events == static_cast<int>(devices.size()) ? 0 : 6;
}
