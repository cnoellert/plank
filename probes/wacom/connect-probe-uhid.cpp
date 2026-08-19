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
  if (argc != 2) {
    std::cerr << "usage: " << argv[0]
              << " REPORT_DESCRIPTOR|--self-test-mouse\n";
    return 2;
  }
  std::vector<std::uint8_t> descriptor;
  std::string name = "StationConnect Virtual Intuos Pro L";
  std::uint32_t vendor = 0x056a;
  std::uint32_t product = 0x0317;
  if (std::string(argv[1]) == "--self-test-mouse") {
    descriptor = {0x05, 0x01, 0x09, 0x02, 0xa1, 0x01, 0x09, 0x01, 0xa1,
                  0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x03, 0x15, 0x00,
                  0x25, 0x01, 0x95, 0x03, 0x75, 0x01, 0x81, 0x02, 0x95,
                  0x01, 0x75, 0x05, 0x81, 0x01, 0x05, 0x01, 0x09, 0x30,
                  0x09, 0x31, 0x15, 0x81, 0x25, 0x7f, 0x75, 0x08, 0x95,
                  0x02, 0x81, 0x06, 0xc0, 0xc0};
    name = "StationConnect UHID Self-Test Mouse";
    vendor = 0x15d9;
    product = 0x0a37;
  } else {
    std::ifstream descriptor_stream(argv[1], std::ios::binary);
    descriptor.assign(std::istreambuf_iterator<char>(descriptor_stream),
                      std::istreambuf_iterator<char>());
    if (descriptor_stream.bad() || descriptor.empty() ||
        descriptor.size() > HID_MAX_DESCRIPTOR_SIZE) {
      std::cerr << "invalid or unreadable HID report descriptor\n";
      return 3;
    }
  }

  const int fd = open("/dev/uhid", O_RDWR | O_CLOEXEC);
  if (fd < 0) {
    std::cerr << "cannot open /dev/uhid: " << std::strerror(errno) << '\n';
    return 4;
  }

  uhid_event create{};
  create.type = UHID_CREATE2;
  const std::string physical = "stationconnect/uhid0";
  std::memcpy(create.u.create2.name, name.data(), name.size());
  std::memcpy(create.u.create2.phys, physical.data(), physical.size());
  create.u.create2.rd_size = static_cast<std::uint16_t>(descriptor.size());
  create.u.create2.bus = BUS_USB;
  create.u.create2.vendor = vendor;
  create.u.create2.product = product;
  create.u.create2.version = 0x0110;
  std::memcpy(create.u.create2.rd_data, descriptor.data(), descriptor.size());
  if (!write_event(fd, create)) {
    close(fd);
    return 5;
  }
  std::cout << "uhid_create=pass descriptor_bytes=" << descriptor.size() << '\n';

  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(8);
  int start_events = 0;
  int report_requests = 0;
  while (std::chrono::steady_clock::now() < deadline) {
    pollfd descriptor_poll{fd, POLLIN, 0};
    const int poll_result = poll(&descriptor_poll, 1, 250);
    if (poll_result <= 0 || (descriptor_poll.revents & POLLIN) == 0) {
      continue;
    }
    uhid_event event{};
    const ssize_t bytes = read(fd, &event, sizeof(event));
    if (bytes < static_cast<ssize_t>(sizeof(event.type))) {
      continue;
    }
    switch (event.type) {
      case UHID_START:
        ++start_events;
        std::cout << "uhid_start=received flags=0x" << std::hex
                  << event.u.start.dev_flags << std::dec << '\n';
        break;
      case UHID_OPEN:
        std::cout << "uhid_open=received\n";
        break;
      case UHID_CLOSE:
        std::cout << "uhid_close=received\n";
        break;
      case UHID_OUTPUT:
        std::cout << "uhid_output=received size=" << event.u.output.size << '\n';
        break;
      case UHID_GET_REPORT: {
        ++report_requests;
        uhid_event reply{};
        reply.type = UHID_GET_REPORT_REPLY;
        reply.u.get_report_reply.id = event.u.get_report.id;
        reply.u.get_report_reply.err = EIO;
        write_event(fd, reply);
        std::cout << "uhid_get_report=declined report="
                  << static_cast<unsigned int>(event.u.get_report.rnum) << '\n';
        break;
      }
      case UHID_SET_REPORT: {
        ++report_requests;
        uhid_event reply{};
        reply.type = UHID_SET_REPORT_REPLY;
        reply.u.set_report_reply.id = event.u.set_report.id;
        reply.u.set_report_reply.err = EIO;
        write_event(fd, reply);
        std::cout << "uhid_set_report=declined report="
                  << static_cast<unsigned int>(event.u.set_report.rnum) << '\n';
        break;
      }
      default:
        break;
    }
  }

  uhid_event destroy{};
  destroy.type = UHID_DESTROY;
  const bool destroyed = write_event(fd, destroy);
  close(fd);
  std::cout << "uhid_destroy=" << (destroyed ? "pass" : "fail") << '\n';
  std::cout << "uhid_start_events=" << start_events
            << " report_requests=" << report_requests << '\n';
  return destroyed && start_events > 0 ? 0 : 6;
}
