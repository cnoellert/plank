#include <array>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <linux/uhid.h>
#include <map>
#include <poll.h>
#include <string>
#include <string_view>
#include <tuple>
#include <unistd.h>
#include <vector>

namespace {

struct FeatureReplyKey {
  std::size_t interface = 0;
  std::uint8_t report = 0;

  bool operator<(const FeatureReplyKey& other) const {
    return std::tie(interface, report) <
           std::tie(other.interface, other.report);
  }
};

bool parse_feature_reply(
    std::string_view value,
    std::map<FeatureReplyKey, std::vector<std::uint8_t>>& replies) {
  const std::size_t first_colon = value.find(':');
  const std::size_t second_colon = value.find(':', first_colon + 1);
  if (first_colon == std::string_view::npos ||
      second_colon == std::string_view::npos) {
    return false;
  }

  const std::string interface_text{value.substr(0, first_colon)};
  const std::string report_text{
      value.substr(first_colon + 1, second_colon - first_colon - 1)};
  const std::string_view data_text = value.substr(second_colon + 1);
  char* end = nullptr;
  const unsigned long interface =
      std::strtoul(interface_text.c_str(), &end, 10);
  if (end == interface_text.c_str() || *end != '\0') {
    return false;
  }
  end = nullptr;
  const unsigned long report = std::strtoul(report_text.c_str(), &end, 16);
  if (end == report_text.c_str() || *end != '\0' || report > 0xff ||
      data_text.empty() || (data_text.size() % 2) != 0 ||
      data_text.size() / 2 > UHID_DATA_MAX) {
    return false;
  }

  std::vector<std::uint8_t> data;
  data.reserve(data_text.size() / 2);
  for (std::size_t offset = 0; offset < data_text.size(); offset += 2) {
    const std::string byte_text{data_text.substr(offset, 2)};
    end = nullptr;
    const unsigned long byte = std::strtoul(byte_text.c_str(), &end, 16);
    if (end == byte_text.c_str() || *end != '\0' || byte > 0xff) {
      return false;
    }
    data.push_back(static_cast<std::uint8_t>(byte));
  }
  if (data.front() != report) {
    return false;
  }
  replies[{interface, static_cast<std::uint8_t>(report)}] = std::move(data);
  return true;
}

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
  bool accept_set_report = false;
  std::vector<const char*> descriptor_paths;
  std::map<FeatureReplyKey, std::vector<std::uint8_t>> feature_replies;
  std::uint32_t requested_product = 0x0317;
  for (int index = 1; index < argc; ++index) {
    const std::string_view argument = argv[index];
    if (argument == "--generic") {
      generic_descriptor = true;
    } else if (argument == "--accept-set-report") {
      accept_set_report = true;
    } else if (argument == "--feature" && index + 1 < argc) {
      if (!parse_feature_reply(argv[++index], feature_replies)) {
        std::cerr << "invalid feature reply; expected INDEX:HEX_ID:HEX_DATA\n";
        return 2;
      }
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
              << " [--generic] [--product HEX] [--accept-set-report] "
                 "[--feature INDEX:HEX_ID:HEX_DATA]... "
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
                    << " report_type="
                    << static_cast<unsigned int>(event.u.output.rtype)
                    << " size=" << event.u.output.size << " data=";
          for (std::uint16_t byte = 0; byte < event.u.output.size; ++byte) {
            std::cout << std::hex << std::setw(2) << std::setfill('0')
                      << static_cast<unsigned int>(event.u.output.data[byte]);
          }
          std::cout << std::dec << '\n';
          break;
        case UHID_GET_REPORT: {
          ++report_requests;
          uhid_event reply{};
          reply.type = UHID_GET_REPORT_REPLY;
          reply.u.get_report_reply.id = event.u.get_report.id;
          const auto response = feature_replies.find(
              {index, event.u.get_report.rnum});
          const bool found = response != feature_replies.end() &&
                             event.u.get_report.rtype == UHID_FEATURE_REPORT;
          reply.u.get_report_reply.err = found ? 0 : EIO;
          if (found) {
            reply.u.get_report_reply.size =
                static_cast<std::uint16_t>(response->second.size());
            std::memcpy(reply.u.get_report_reply.data,
                        response->second.data(), response->second.size());
          }
          write_event(devices[index], reply);
          std::cout << "uhid_get_report="
                    << (found ? "answered" : "declined")
                    << " interface=" << index
                    << " report="
                    << static_cast<unsigned int>(event.u.get_report.rnum)
                    << " report_type="
                    << static_cast<unsigned int>(event.u.get_report.rtype)
                    << '\n';
          break;
        }
        case UHID_SET_REPORT: {
          ++report_requests;
          uhid_event reply{};
          reply.type = UHID_SET_REPORT_REPLY;
          reply.u.set_report_reply.id = event.u.set_report.id;
          reply.u.set_report_reply.err = accept_set_report ? 0 : EIO;
          write_event(devices[index], reply);
          std::cout << "uhid_set_report="
                    << (accept_set_report ? "accepted" : "declined")
                    << " interface=" << index
                    << " report="
                    << static_cast<unsigned int>(event.u.set_report.rnum)
                    << " report_type="
                    << static_cast<unsigned int>(event.u.set_report.rtype)
                    << " size=" << event.u.set_report.size << " data=";
          for (std::uint16_t byte = 0; byte < event.u.set_report.size; ++byte) {
            std::cout << std::hex << std::setw(2) << std::setfill('0')
                      << static_cast<unsigned int>(event.u.set_report.data[byte]);
          }
          std::cout << std::dec
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
