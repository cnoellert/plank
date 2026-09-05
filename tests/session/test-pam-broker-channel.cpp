/**
 * @file tests/session/test-pam-broker-channel.cpp
 * @brief Real Unix descriptor-transfer and privilege-boundary regression tests.
 */
#include "auth/pam_broker_channel.h"

#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#include <grp.h>
#include <pwd.h>
#include <sys/prctl.h>
#include <sys/wait.h>

namespace channel = plank::auth::broker_channel;

namespace {
  /** @brief Assert a test invariant without NDEBUG-dependent behavior. */
  void require(bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
  }

  /** @brief Own two sockets for one test, closing them on failure as well. */
  struct sockets_t {
    int fd[2] {-1, -1};  ///< Owned connected descriptors.
    explicit sockets_t(int type = SOCK_SEQPACKET) {
      require(socketpair(AF_UNIX, type | SOCK_CLOEXEC, 0, fd) == 0, "socketpair");
    }
    ~sockets_t() {
      close(fd[0]);
      close(fd[1]);
    }
    sockets_t(const sockets_t &) = delete;
    sockets_t &operator=(const sockets_t &) = delete;
  };

  /** @brief Count process descriptors to detect ancillary-data rejection leaks. */
  std::size_t descriptors() {
    std::size_t count = 0;
    for ([[maybe_unused]] const auto &entry : std::filesystem::directory_iterator("/proc/self/fd")) ++count;
    return count;
  }

  /** @brief Construct a deliberately malformed response with multiple descriptors. */
  void send_extra_fds(int socket, int fd, std::size_t count) {
    std::vector<int> fds(count, fd);
    alignas(cmsghdr) std::array<char, CMSG_SPACE(sizeof(int) * 16)> ancillary {};
    char response = 'O';
    iovec data {&response, 1};
    msghdr message {};
    message.msg_iov = &data;
    message.msg_iovlen = 1;
    message.msg_control = ancillary.data();
    message.msg_controllen = CMSG_SPACE(sizeof(int) * count);
    auto *header = CMSG_FIRSTHDR(&message);
    header->cmsg_level = SOL_SOCKET;
    header->cmsg_type = SCM_RIGHTS;
    header->cmsg_len = CMSG_LEN(sizeof(int) * count);
    std::memcpy(CMSG_DATA(header), fds.data(), sizeof(int) * count);
    require(sendmsg(socket, &message, MSG_NOSIGNAL) == 1, "send malformed ancillary");
  }

  /** @brief Exercise real transfer, denial, malformed messages, truncation and EOF. */
  void records() {
    sockets_t control;
    sockets_t broker(SOCK_STREAM);
    int received = -1;
    require(channel::send_connection(control.fd[0], broker.fd[0]), "send descriptor");
    require(channel::receive_record(control.fd[1], 'O', true, received), "receive descriptor");
    require(received >= 0 && (fcntl(received, F_GETFD) & FD_CLOEXEC), "received CLOEXEC");
    require(send(received, "test", 4, MSG_NOSIGNAL) == 4, "delegated socket write");
    char reply[4] {};
    require(recv(broker.fd[1], reply, sizeof(reply), 0) == 4 &&
            std::string_view(reply, 4) == "test", "direct broker exchange");
    close(received);
    require(channel::send_connection(control.fd[0], -1), "send refusal");
    require(channel::receive_record(control.fd[1], 'O', true, received) && received == -1,
            "explicit refusal is a valid record");
    for (const char *invalid : {"", "O", "NO", "OVERSIZED"}) {
      const auto size = std::strlen(invalid);
      require(send(control.fd[0], invalid, size, MSG_NOSIGNAL) == static_cast<ssize_t>(size), "send invalid");
      require(!channel::receive_record(control.fd[1], 'O', true, received) && received == -1,
              "reject missing FD or invalid/truncated record");
    }
    for (std::size_t count : {2U, 16U}) {
      const auto before = descriptors();
      send_extra_fds(control.fd[0], broker.fd[0], count);
      require(!channel::receive_record(control.fd[1], 'O', true, received) && received == -1,
              "reject excess/truncated descriptors");
      require(descriptors() == before, "rejected descriptors leaked");
    }
    const auto before = descriptors();
    require(channel::send_connection(control.fd[0], broker.fd[0]), "send FD on request path");
    require(!channel::receive_record(control.fd[1], 'P', false, received), "reject FD on request");
    require(descriptors() == before, "request FD leaked");
    require(send(control.fd[0], &channel::request_byte, 1, MSG_NOSIGNAL) == 1, "send request");
    require(channel::receive_record(control.fd[1], 'P', false, received), "valid empty request");
    require(!channel::trusted_peer(broker.fd[0], SOCK_SEQPACKET), "reject wrong socket type");
    require(!channel::trusted_peer(-1, SOCK_STREAM), "reject invalid peer");
    if (geteuid() != 0) require(!channel::trusted_peer(broker.fd[0], SOCK_STREAM), "reject nonroot broker");
    shutdown(control.fd[0], SHUT_RDWR);
    require(!channel::receive_record(control.fd[1], 'O', true, received), "reject EOF");
  }

  /** @brief Verify environment forgery cannot enable filesystem or socket fallback. */
  void invalid_environment() {
    for (const char *value : {"", "0", "-1", "3junk", "9999999999999999999999"}) {
      setenv(channel::environment_name, value, 1);
      require(channel::request_connection() == -1, "invalid channel environment accepted");
    }
    unsetenv(channel::environment_name);
    require(channel::request_connection() == -1, "missing channel accepted");
  }

  /**
   * @brief Optionally prove root-to-unprivileged delegation using a synthetic broker.
   * No production PAM socket, credentials, input devices or service are touched.
   */
  void dropped_identity() {
    if (geteuid() != 0) {
      std::cout << "root-to-unprivileged delegation: SKIP (requires root probe)\n";
      return;
    }
    const auto *account = getpwnam("nobody");
    require(account && account->pw_uid != 0 && account->pw_gid != 0, "missing probe account");
    const uid_t uid = account->pw_uid;
    const gid_t gid = account->pw_gid;
    sockets_t control;
    sockets_t broker(SOCK_STREAM);
    const pid_t child = fork();
    require(child >= 0, "fork");
    if (child == 0) {
      close(control.fd[0]);
      close(broker.fd[0]);
      close(broker.fd[1]);
      if (setgroups(0, nullptr) || setresgid(gid, gid, gid) ||
          setresuid(uid, uid, uid) || prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) _exit(2);
      setenv(channel::environment_name, std::to_string(control.fd[1]).c_str(), 1);
      const int delegated = channel::request_connection();
      if (delegated < 0 || send(delegated, "test", 4, MSG_NOSIGNAL) != 4) _exit(3);
      close(delegated);
      // A normal refusal must not poison the channel for the next attempt.
      if (channel::request_connection() != -1) _exit(4);
      const int again = channel::request_connection();
      if (again < 0) _exit(5);
      close(again);
      _exit(0);
    }
    close(control.fd[1]);
    control.fd[1] = -1;
    bool served = true;
    for (int attempt = 0; attempt < 3; ++attempt) {
      pollfd ready {control.fd[0], POLLIN, 0};
      int unused = -1;
      if (poll(&ready, 1, 4000) != 1 ||
          !channel::receive_record(control.fd[0], 'P', false, unused) ||
          !channel::send_connection(control.fd[0], attempt == 1 ? -1 : broker.fd[0])) {
        served = false;
        break;
      }
    }
    int status = 0;
    require(waitpid(child, &status, 0) == child, "wait for probe child");
    require(served && WIFEXITED(status) && WEXITSTATUS(status) == 0, "unprivileged delegation failed");
    char reply[4] {};
    require(recv(broker.fd[1], reply, sizeof(reply), MSG_DONTWAIT) == 4 &&
            std::string_view(reply, 4) == "test", "delegation did not reach broker");
    std::cout << "root-to-unprivileged delegation: PASS\n";
  }
}

int main() {
  try {
    records();
    invalid_environment();
    dropped_identity();
    std::cout << "PAM private channel tests: PASS\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
