/**
 * @file tests/display/virtual-display-transition.cpp
 * @brief Production virtual-layout rollback tests without an X server or display mutation.
 */
#include "session/virtual_display_transition.h"

#include <functional>
#include <iostream>
#include <stdexcept>

namespace display = plank::session::virtual_display;
namespace {
  int checks = 0;
  void check(bool condition, const char *message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
  }

  std::string edid(char value) {
    std::string text = "\tEDID:\n";
    for (int i = 0; i < 24; ++i) text += "\t\t" + std::string(32, value) + "\n";
    return text;
  }

  std::string fixture(bool dual = false, bool right = false) {
    const std::string first_mode = right ? "1280x2160" : "1920x1080";
    const std::string second_mode = right ? "1920x1080" : "1280x2160";
    return std::string {"Screen 0: minimum 8 x 8, current "} + (dual ? "3200 x 2160" : "1920 x 1080") +
      ", maximum 32767 x 32767\nDP-0 connected primary " + first_mode +
      (right ? "+1920+0" : "+0+0") + " (normal left inverted right x axis y axis) 160mm x 90mm\n" +
      edid('a') + "\tnon-desktop: 0 \n   " + first_mode + "     60.00*+  59.94\n" +
      "DP-1 disconnected (normal left inverted right x axis y axis)\n\tnon-desktop: 0\n" +
      (dual ? "DP-2 connected " + second_mode + (right ? "+0+0" : "+1920+0") : "DP-2 disconnected") +
      " (normal left inverted right x axis y axis)\n" + edid('b') +
      (dual ? "\tnon-desktop: 0\n   " + second_mode + "     60.00*\n" :
              "\tnon-desktop: 1\n   1920x1080     60.00 +\n") +
      "DP-3 disconnected (normal left inverted right x axis y axis)\n\tnon-desktop: 0\n";
  }

  display::snapshot_t parsed(std::string input) {
    const auto result = display::parse(input);
    check(result.has_value(), "valid RandR fixture must parse");
    return *result;
  }

  std::string replace(std::string value, std::string_view before, std::string_view after) {
    const auto pos = value.find(before);
    check(pos != value.npos, "fixture replacement must exist");
    value.replace(pos, before.size(), after);
    return value;
  }

  display::snapshot_t blank(display::snapshot_t state) {
    state.width = 8192; state.height = 2160;
    for (auto &out : state.outputs) {
      out.width = out.height = out.x = out.y = 0;
      out.mode.clear(); out.rate.clear();
    }
    return state;
  }

  struct rig_t {
    display::snapshot_t original = parsed(fixture());
    std::optional<display::snapshot_t> state = original;
    display::snapshot_t target = parsed(fixture(true));
    bool owner = true, apply_ok = true, restore_ok = true, restore_geometry = true;
    int applies = 0, restores = 0, observations = 0;
    std::function<void(rig_t &)> during_apply;
    std::function<void(rig_t &)> during_observe;
    std::function<void(rig_t &)> during_restore;
    std::vector<std::string> restored_argv;

    display::result_t run() {
      return display::transition(
        [&] { return owner; },
        [&] {
          ++observations;
          if (during_observe) during_observe(*this);
          return state;
        },
        [&] {
          ++applies; state = target;
          if (during_apply) during_apply(*this);
          return apply_ok;
        },
        [](const auto &snapshot) {
          return display::matches_request(snapshot, "dual-horizontal", "1920x1080", "1280x2160", -1);
        },
        [&](const auto &argv) {
          ++restores; restored_argv = argv;
          if (restore_geometry) state = original;
          if (during_restore) during_restore(*this);
          return restore_ok;
        }
      );
    }
  };

  void parser_tests() {
    const auto single = parsed(fixture()), dual = parsed(fixture(true)), right = parsed(fixture(true, true));
    check(display::usable(single) && display::usable(dual) && display::usable(right), "single and both dual orders restorable");
    check(display::matches_request(single, "single", "1920x1080", "", -1), "single request matches");
    check(display::matches_request(right, "dual-horizontal", "1920x1080", "1280x2160", 1), "right primary request matches");
    check(!display::matches_request(right, "dual-horizontal", "1920x1080", "1280x2160", 0), "wrong primary side rejected");
    check(!display::matches_request(single, "single", "1920x1080", "", 1), "invalid primary index rejected");
    check(!display::matches_request(single, "physical", "1920x1080", "", -1), "physical request rejected");
    auto rate = single; rate.outputs[0].rate = "59.94";
    check(display::usable(rate) && !display::matches_request(rate, "single", "1920x1080", "", -1), "saved refresh differs from requested60");
    const auto restored = display::restore_arguments(rate);
    check(std::find(restored.begin(), restored.end(), "59.94") != restored.end(), "rollback preserves exact saved refresh");
    const std::vector<std::string> expected {"--fb", "1920x1080", "--output", "DP-0", "--mode", "1920x1080", "--rate", "60.00", "--pos", "0x0", "--primary", "--set", "non-desktop", "0", "--output", "DP-2", "--off", "--set", "non-desktop", "1"};
    check(display::restore_arguments(single) == expected, "rollback argv preserves single geometry/primary/visibility");
    check(!display::restore_arguments(right).empty(), "right primary layout produces restoration");
    check(display::restore_arguments(blank(single)).empty(), "empty desktop cannot become recovery snapshot");
    const auto inactive = parsed(replace(replace(fixture(), "primary 1920x1080+0+0", "primary"), "   1920x1080     60.00*+  59.94", "   1920x1080     60.00 + 59.94"));
    check(!display::usable(inactive) && display::same_scope(single, inactive), "NULL output remains observable with same identities");
    for (const auto &invalid : {
      std::string {}, std::string(65537, 'x'),
      std::string(2049, 'x'),
      replace(fixture(), "\tEDID:", "\tEDID:\n\tEDID:"),
      replace(fixture(), std::string(32, 'a'), std::string(31, 'a') + "z"),
      replace(fixture(), "1920 x 1080,", "99999999999999999999999 x 1080,"),
      replace(fixture(), "primary 1920x1080+0+0", "primary 1920x1080-1+0"),
      replace(fixture(), "primary 1920x1080+0+0 (normal", "primary 1920x1080+0+0 (left"),
      replace(fixture(), "DP-1 disconnected", "DP-0 disconnected"),
      replace(fixture(), "60.00*+  59.94", "nan*"),
      replace(fixture(), "60.00*+  59.94", "60.00* 59.94*"),
      replace(fixture(), "non-desktop: 1", "non-desktop: 2"),
      replace(fixture(), "non-desktop: 1", "non-desktop: 1\n\tnon-desktop: 1"),
      replace(fixture(), "60.00*+  59.94", "60.00 59.94")
    }) check(!display::parse(invalid), "malformed response rejected");
    auto unknown = single;
    unknown.outputs[0].name = "HDMI-0";
    check(!display::usable(unknown), "unrelated active connector refused");
    unknown = single; unknown.outputs[0].mode = "arbitrary-mode";
    check(!display::usable(unknown), "nonqualified mode refused");
    unknown = single; unknown.outputs[0].edid.resize(32);
    check(!display::usable(unknown), "partial EDID refused");
    unknown = single; unknown.outputs[0].non_desktop.reset();
    check(!display::usable(unknown), "missing visibility property refused");
    unknown = dual; unknown.outputs[2].x = 0;
    check(!display::usable(unknown), "overlapping layout refused");
    unknown = single; unknown.width = 8192;
    check(display::usable(unknown), "configured framebuffer larger than active mode is preserved");
    check(!display::matches_request(unknown, "single", "1920x1080", "", -1),
          "requested framebuffer must still match exactly");
    unknown.width = 8193;
    check(!display::usable(unknown), "framebuffer beyond qualified virtual canvas refused");
  }

  void transaction_tests() {
    using result = display::result_t;
    {
      rig_t rig;
      check(rig.run() == result::applied && rig.applies == 1 && rig.restores == 0, "successful change verified without rollback");
    }
    for (const bool command_success : {false, true}) {
      rig_t rig; rig.apply_ok = command_success;
      rig.during_apply = [](auto &r) { r.state = blank(r.original); };
      check(rig.run() == result::restored, "failed/false-success change that blanks all monitors rolls back");
      check(rig.state == rig.original && rig.applies == 1 && rig.restores == 1, "exact snapshot restored once");
      check(rig.restored_argv == display::restore_arguments(rig.original), "rollback uses captured state");
    }
    for (const bool right : {false, true}) {
      rig_t rig; rig.original = parsed(fixture(true, right)); rig.state = rig.original;
      rig.during_apply = [](auto &r) { r.state = blank(r.original); };
      check(rig.run() == result::restored && rig.state == rig.original,
            "both dual-primary orders recover their saved layout");
    }
    {
      rig_t rig; rig.original.width = 8192; rig.original.height = 2160; rig.state = rig.original;
      rig.apply_ok = false;
      check(rig.run() == result::restored && rig.state == rig.original,
            "rollback preserves larger preexisting virtual framebuffer exactly");
    }
    {
      rig_t rig; rig.apply_ok = false;
      check(rig.run() == result::restored, "failed command with apparently correct geometry still restored");
    }
    for (const bool changes_geometry : {false, true}) {
      rig_t rig; rig.apply_ok = false; rig.restore_geometry = changes_geometry; rig.restore_ok = !changes_geometry;
      check(rig.run() == result::restore_failed && rig.restores == 1, "rollback status and resulting geometry both required");
    }
    {
      rig_t rig; rig.apply_ok = false;
      rig.during_restore = [](auto &r) { r.state->outputs[0].primary = false; };
      check(rig.run() == result::restore_failed, "rollback verifies primary property");
    }
    {
      rig_t rig; rig.apply_ok = false;
      rig.during_restore = [](auto &r) { r.owner = false; };
      check(rig.run() == result::ownership_changed && rig.observations == 2,
            "ownership loss during rollback cannot be reported as recovery");
    }
    {
      rig_t rig; rig.state = blank(rig.original);
      check(rig.run() == result::no_snapshot && rig.applies == 0, "no usable initial layout means no mutation");
    }
    {
      rig_t rig; rig.state.reset();
      check(rig.run() == result::no_snapshot && rig.applies == 0, "initial observation failure means no mutation");
    }
    {
      rig_t rig; rig.owner = false;
      check(rig.run() == result::ownership_changed && rig.observations == 0, "wrong owner cannot start");
    }
    {
      rig_t rig; rig.during_apply = [](auto &r) { r.owner = false; };
      check(rig.run() == result::ownership_changed && rig.restores == 0, "new login/server is never restored over");
    }
    for (int observation = 1; observation <= 3; ++observation) {
      rig_t rig; rig.apply_ok = false;
      rig.during_observe = [observation](auto &r) { if (r.observations == observation) r.owner = false; };
      check(rig.run() == result::ownership_changed, "ownership checked after every observation");
      check(rig.restores == (observation == 3 ? 1 : 0), "no mutation after observed ownership loss");
    }
    {
      rig_t rig; rig.during_apply = [](auto &r) { r.state.reset(); };
      check(rig.run() == result::restore_failed && rig.restores == 0, "unreadable identities never permit blind rollback");
    }
    for (int change = 0; change < 4; ++change) {
      rig_t rig;
      rig.during_apply = [change](auto &r) {
        if (change == 0) r.state->outputs[0].edid[0] = 'f';
        if (change == 1) {
          display::output_t added;
          added.name = "new-output";
          r.state->outputs.push_back(added);
        }
        if (change == 2) r.state->outputs[1].connected = true;
        if (change == 3) r.state->outputs[0].connected = false;
      };
      check(rig.run() == result::scope_changed && rig.restores == 0, "replaced/hotplugged output refuses stale rollback");
    }
    {
      rig_t rig; rig.apply_ok = false;
      rig.during_restore = [](auto &r) { r.state->outputs[0].edid[0] = 'f'; };
      check(rig.run() == result::scope_changed, "post-rollback identity change not accepted");
    }
    {
      rig_t rig; rig.apply_ok = false;
      rig.during_restore = [](auto &r) { r.state.reset(); };
      check(rig.run() == result::restore_failed, "unobservable rollback not accepted");
    }
  }
}

int main() {
  try { parser_tests(); transaction_tests(); }
  catch (const std::exception &error) {
    std::cerr << "Virtual display rollback FAIL: " << error.what() << '\n'; return 1;
  }
  std::cout << "Virtual display rollback PASS: " << checks << " checks\n";
}
