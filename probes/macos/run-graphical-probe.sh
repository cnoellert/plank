#!/bin/bash
# Temporary, bounded qualification on an explicitly authorized development Mac.
set -euo pipefail
if [[ $# -lt 3 || $# -gt 4 || ! -f $2 || ! -f $3 ]]; then
    echo "Usage: bash $0 loginwindow|gui/UID /absolute/probe-binary /absolute/probe-agent.plist [MODE]; see probes/macos/README.md for signed-app modes and standalone --select-mode" >&2
    exit 2
fi
probe_mode=${4:---capture}
probe_deadline=40
case $probe_mode in
    --pattern-hevc-2160-mixed|--pattern-hevc-2160-mixed-speed) probe_deadline=210 ;;
esac
case $probe_mode in
    --encode-hevc-full-range|--encode-hevc-full-range-444|--pattern-hevc-full-range) ;;
    --cursor|--login-pointer|--cadence-60|--cadence-native) ;;
    --pattern-hevc-2160-mixed|--pattern-hevc-2160-mixed-speed) ;;
    --audio|--capture|--capture-virtual|--input|--pointer|--pointer-session|--encode-h264|--encode-hevc|--encode-h264-owned|--encode-hevc-owned|--encode-owned-replace|--encode-owned-crash|--encode-session|--encode-session-revoke|--pattern-h264|--pattern-hevc|--pattern-h264-2160|--pattern-hevc-2160|--pattern-hevc-2160-speed|--select-mode|--restore-mode|--descriptor-comparison|--hidpi-comparison) ;;
    *) echo "Unsupported probe mode." >&2; exit 2 ;;
esac
if [[ $probe_mode == --descriptor-comparison || $probe_mode == --hidpi-comparison ]]; then
    [[ ${2##*/} == display-initial-mode ]] || { echo "Descriptor comparison requires the standalone initial-mode probe." >&2; exit 2; }
elif [[ $probe_mode == --select-mode || $probe_mode == --restore-mode ]]; then
    [[ ${2##*/} == display-mode-lifecycle ]] || { echo "Mode selection requires the standalone display lifecycle probe." >&2; exit 2; }
elif [[ $# == 4 && $2 != '/Applications/PLANK Host Probe.app/Contents/MacOS/plank-host-probe' ]]; then
    echo "Explicit modes require the installed signed application." >&2
    exit 2
fi
probe_domain=$1
if [[ $probe_mode == --login-pointer && $probe_domain != loginwindow ]]; then
    echo "The login pointer test requires the actual LoginWindow session." >&2; exit 2
fi
if [[ $probe_mode == --cursor && $probe_domain == loginwindow ]]; then
    echo "The owned-window cursor test requires an unlocked Aqua desktop." >&2; exit 2
fi
if [[ $probe_mode == --cadence-* && $probe_domain == loginwindow ]]; then
    echo "Capture cadence requires the existing Aqua desktop." >&2; exit 2
fi
probe_session=Aqua
if [[ $probe_domain == loginwindow && $(id -u) == 0 ]]; then
    probe_session=LoginWindow
elif [[ $probe_domain != "gui/$(id -u)" || $(id -u) == 0 ]]; then
    echo "Run LoginWindow as root, or Aqua as that desktop's user." >&2
    exit 2
fi
launchctl print "$probe_domain" >/dev/null
probe_stage=$(mktemp -d /private/tmp/plank-graphical-probe.XXXXXX)
probe_label=la.instinctual.PLANK.feasibility-probe
cleanup() {
    launchctl bootout "$probe_domain/$probe_label" >/dev/null 2>&1 || true
    # Only remove this invocation's root-owned, generated staging directory.
    if [[ $probe_stage == /private/tmp/plank-graphical-probe.* ]]; then
        rm -f "$probe_stage/probe" "$probe_stage/agent.plist" \
            "$probe_stage/stdout" "$probe_stage/stderr"
        rmdir "$probe_stage"
    fi
}
if launchctl print "$probe_domain/$probe_label" >/dev/null 2>&1; then
    rmdir "$probe_stage"
    echo "A feasibility probe is already registered; refusing to replace it." >&2
    exit 2
fi
trap cleanup EXIT
probe_executable="$probe_stage/probe"
if [[ $2 == '/Applications/PLANK Host Probe.app/Contents/MacOS/plank-host-probe' ]]; then
    # Retain the installed bundle identity for TCC; this is a development runner,
    # not a privileged product endpoint accepting untrusted requests.
    [[ $(stat -f '%u' "$2") == 0 ]]
    [[ $(stat -f '%Lp' "$2") == 755 ]]
    probe_executable=$2
else
    install -m 0755 "$2" "$probe_executable"
fi
install -m 0600 "$3" "$probe_stage/agent.plist"
/usr/libexec/PlistBuddy -c "Set :LimitLoadToSessionType $probe_session" "$probe_stage/agent.plist"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $probe_executable" "$probe_stage/agent.plist"
if [[ $probe_executable == /Applications/* || $probe_mode == --select-mode || $probe_mode == --restore-mode || $probe_mode == --descriptor-comparison || $probe_mode == --hidpi-comparison ]]; then
    /usr/libexec/PlistBuddy -c "Add :ProgramArguments:1 string $probe_mode" "$probe_stage/agent.plist"
fi
/usr/libexec/PlistBuddy -c "Set :StandardOutPath $probe_stage/stdout" "$probe_stage/agent.plist"
/usr/libexec/PlistBuddy -c "Set :StandardErrorPath $probe_stage/stderr" "$probe_stage/agent.plist"
plutil -lint "$probe_stage/agent.plist"
launchctl bootstrap "$probe_domain" "$probe_stage/agent.plist"
probe_status=""
exit_pattern='last exit code = ([0-9]+)'
probe_exit=""
for ((attempt=0; attempt<probe_deadline; attempt++)); do
    probe_status=$(launchctl print "$probe_domain/$probe_label")
    if [[ $probe_status =~ $exit_pattern ]]; then
        probe_exit=${BASH_REMATCH[1]}
        break
    fi
    sleep 1
done
[[ ! -f $probe_stage/stdout ]] || cat "$probe_stage/stdout"
[[ ! -f $probe_stage/stderr ]] || cat "$probe_stage/stderr" >&2
printf '%s\n' "$probe_status" | /usr/bin/grep -E 'state =|last exit code =|pid ='
if [[ -z $probe_exit ]]; then
    echo "Probe exceeded its $probe_deadline-second deadline; terminating its temporary agent." >&2
    exit 1
elif [[ $probe_exit != 0 ]]; then
    echo "Probe exited with qualification failure code $probe_exit (not a watchdog timeout)." >&2
    exit 1
fi
