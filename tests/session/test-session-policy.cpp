/**
 * @file tests/session/test-session-policy.cpp
 * @brief Standalone tests for host graphical-session selection policy.
 */
#include "session/session_context.h"

#include <cstdlib>
#include <iostream>

#include <unistd.h>

namespace session = stationconnect::session;

namespace {
  session::descriptor_t valid_session() {
    return {"c7", 1000, "seat0", "x11", "user", "active", true, false};
  }

  bool rejected(session::descriptor_t descriptor) {
    return !session::eligible_graphical_session(descriptor);
  }
}  // namespace

int main() {
  if (getenv("STATIONCONNECT_SESSION_ATTESTATION_FD") != nullptr) {
    const bool accepted = session::supervisor_attests_account_for_active_seat0(getuid());
    std::cout << "session_attestation=" << (accepted ? "accepted" : "rejected") << '\n';
    return accepted ? 0 : 9;
  }

  auto descriptor = valid_session();
  if (!session::eligible_graphical_session(descriptor)) {
    std::cerr << "active local seat0 X11 user was rejected\n";
    return 1;
  }
  descriptor.session_class = "greeter";
  if (!session::eligible_graphical_session(descriptor)) {
    std::cerr << "active local seat0 X11 greeter was rejected\n";
    return 1;
  }
  if (session::session_attestation_message(descriptor) !=
      "SC-SESSION-1\nc7\n1000") {
    std::cerr << "eligible session attestation was malformed\n";
    return 8;
  }

  descriptor = valid_session();
  descriptor.active = false;
  if (!rejected(descriptor)) return 2;
  descriptor = valid_session();
  descriptor.remote = true;
  if (!rejected(descriptor)) return 3;
  descriptor = valid_session();
  descriptor.seat = "seat1";
  if (!rejected(descriptor)) return 4;
  descriptor = valid_session();
  descriptor.type = "wayland";
  if (!rejected(descriptor)) return 5;
  descriptor = valid_session();
  descriptor.session_class = "lock-screen";
  if (!rejected(descriptor)) return 6;
  descriptor = valid_session();
  descriptor.state = "closing";
  if (!rejected(descriptor)) return 7;
  return 0;
}
