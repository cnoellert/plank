// Socket-only regression: EOF must not masquerade as a malformed request or
// leave a readable descriptor spinning until the child is reaped.
#include "session/worker_control.h"

#include <array>
#include <cstdio>
#include <cstring>
#include <poll.h>

int main() {
  int sockets[2];
  if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, sockets) != 0) return 1;
  std::array<char, 8> buffer {};
  auto read_record = [&] {
    return plank::session::receive_worker_control(sockets[0], buffer.data(), buffer.size());
  };
  // Spurious readiness must not block or retire a healthy channel.
  if (read_record() != -1 || sockets[0] < 0) return 2;
  if (send(sockets[1], "valid", 5, MSG_NOSIGNAL) != 5) return 3;
  if (read_record() != 5 || std::memcmp(buffer.data(), "valid", 5) != 0) return 4;
  // Oversized input must not be silently truncated into a valid prefix.
  if (send(sockets[1], "oversized", 9, MSG_NOSIGNAL) != 9) return 5;
  if (read_record() != 9 || sockets[0] < 0) return 6;
  // A queued final record is delivered before EOF, even with POLLHUP.
  if (send(sockets[1], "last", 4, MSG_NOSIGNAL) != 4) return 7;
  close(sockets[1]);
  if (read_record() != 4 || std::memcmp(buffer.data(), "last", 4) != 0) return 8;
  if (read_record() != -1 || sockets[0] != -1) return 9;
  pollfd retired {sockets[0], POLLIN, 0};
  if (poll(&retired, 1, 0) != 0 || read_record() != -1) return 10;
  // A permanent recv error is retired too, rather than remaining in poll.
  int pipes[2];
  if (pipe(pipes) != 0) return 11;
  if (plank::session::receive_worker_control(pipes[0], buffer.data(), buffer.size()) != -1 ||
      pipes[0] != -1) return 12;
  close(pipes[1]);
  std::puts("Worker control EOF/idle/truncation/queued-record/error tests: PASS");
}
