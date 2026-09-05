// Exercise the real fatal-I/O callback from a child worker thread. No X server,
// GPU, credentials, or running product service is needed for this test.
#include "platform/linux/x11_worker_exit.h"

#include <X11/Xlib.h>
#include <chrono>
#include <cstdio>
#include <poll.h>
#include <signal.h>
#include <sys/wait.h>
#include <thread>

namespace {
  int exit_marker = -1;

  void mark_exit_handler() {
    const char marker = 'X';
    (void) write(exit_marker, &marker, 1);
  }

  struct destructor_marker {
    ~destructor_marker() { mark_exit_handler(); }
  };

  bool exercise_exit() {
    int descriptors[2];
    if (pipe(descriptors) != 0) return false;
    const auto child = fork();
    if (child == 0) {
      close(descriptors[0]);
      exit_marker = descriptors[1];
      static destructor_marker static_object;
      (void) static_object;
      if (std::atexit(mark_exit_handler) != 0) std::_Exit(90);
      XSetIOErrorHandler(platf::x11::retire_failed_x11_worker);
      const auto installed = XSetIOErrorHandler(platf::x11::retire_failed_x11_worker);
      if (installed != platf::x11::retire_failed_x11_worker) std::_Exit(91);
      std::thread observer([installed] {
        destructor_marker stack_object;
        (void) stack_object;
        installed(nullptr);
      });
      observer.join();
      std::_Exit(92);
    }
    close(descriptors[1]);
    if (child < 0) {
      close(descriptors[0]);
      return false;
    }
    pollfd ready {descriptors[0], POLLIN | POLLHUP, 0};
    const int result = poll(&ready, 1, 2000);
    if (result <= 0) kill(child, SIGKILL);
    int status = 0;
    const auto reaped = waitpid(child, &status, 0);
    char marker = 0;
    const auto bytes = read(descriptors[0], &marker, 1);
    close(descriptors[0]);
    // EOF proves inherited descriptors closed. Any marker means unwanted
    // atexit/destructor execution, including the observing thread's stack.
    return result == 1 && reaped == child && bytes == 0 &&
           WIFEXITED(status) && WEXITSTATUS(status) == platf::x11::lost_display_exit_status;
  }
}

int main() {
  for (int repeat = 0; repeat < 3; ++repeat) {
    if (!exercise_exit()) {
      std::fputs("X11 worker retirement: FAIL\n", stderr);
      return 1;
    }
  }
  std::puts("X11 worker retirement: PASS (no exit handlers, parent survives, descriptors close)");
}
