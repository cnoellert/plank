/**
 * @file tests/session/test-session-policy.cpp
 * @brief Standalone tests for host graphical-session selection policy.
 */
#include "session/session_context.h"

#include <iostream>

namespace session = stationconnect::session;

namespace {
  session::descriptor_t valid_session() {
    return {"c7", 1000, "seat0", "x11", "user", "active", true, false};
  }

  bool rejected(session::descriptor_t descriptor) {
    return !session::eligible_graphical_session(descriptor);
  }

  session::update_t valid_update() {
    return {
      2,
      valid_session(),
      {":0", "/run/user/1000/gdm/Xauthority", "/run/user/1000",
       "unix:path=/run/user/1000/bus", "unix:/run/user/1000/pulse/native",
       "/home/test/.config/pulse/cookie"},
    };
  }
}  // namespace

int main() {
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
  const auto update = valid_update();
  const auto message = session::session_update_message(update);
  const auto parsed = session::parse_session_update(message);
  if (!parsed || parsed->generation != update.generation ||
      parsed->session.id != update.session.id ||
      parsed->environment.pulse_cookie != update.environment.pulse_cookie) {
    std::cerr << "session update did not round trip\n";
    return 8;
  }
  if (session::parse_session_update(message.substr(0, message.size() - 1)) ||
      session::parse_session_update(std::string_view {"SC-SESSION-2\0bad", 16})) {
    std::cerr << "malformed session update was accepted\n";
    return 9;
  }
  const session::display_request_t display_request {
    "dual-horizontal", "4096x2160", "1024x2160"
  };
  const auto display_message = session::display_request_message(display_request);
  const auto parsed_display = session::parse_display_request(display_message);
  if (!parsed_display || parsed_display->layout != display_request.layout ||
      parsed_display->mode_1 != display_request.mode_1 ||
      parsed_display->mode_2 != display_request.mode_2) {
    std::cerr << "display request did not round trip\n";
    return 11;
  }
  if (!session::display_request_message({"single", "5120x2160", {}}).empty() ||
      session::parse_display_request(display_message.substr(0, display_message.size() - 1))) {
    std::cerr << "malformed display request was accepted\n";
    return 12;
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

  auto invalid_update = valid_update();
  invalid_update.session.remote = true;
  if (!session::session_update_message(invalid_update).empty()) return 10;
  return 0;
}
