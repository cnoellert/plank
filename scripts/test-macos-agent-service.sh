#!/bin/bash
# Temporary system Mach service + actual graphical agent. No capture or input.
set -euo pipefail
if [[ $# != 4 || $(id -u) != 0 || $(uname -s) != Darwin || $1 != /* || $2 != /* ||
      ! $3 =~ ^[[:xdigit:]]{64}$ || ! $4 =~ ^[1-9][0-9]*$ ]]; then
    echo "Usage (root, dedicated Mac): $0 SOURCE_ROOT BINARY SHA256 ALLOWED_DESKTOP_UID" >&2; exit 2
fi
source_root=$1
binary=$2
expected=$3
allowed_uid=$4
console_uid=$(stat -f '%u' /dev/console)
if [[ $console_uid == 0 ]]; then
    domain=loginwindow; session_type=LoginWindow
elif [[ $console_uid == "$allowed_uid" ]]; then
    domain="gui/$console_uid"; session_type=Aqua
else
    echo "Console is outside the operator-designated scope." >&2; exit 2
fi
stage=$(mktemp -d /private/tmp/plank-agent-service.XXXXXX)
chmod 0755 "$stage"
label="la.instinctual.PLANK.agent-qualification.$(uuidgen)"
cleanup() {
    launchctl bootout "$domain/$label.agent" >/dev/null 2>&1 || true
    launchctl bootout "system/$label" >/dev/null 2>&1 || true
    rm -f "$stage/agent-peer" "$stage/service.plist" "$stage/agent.plist" \
        "$stage/service.stdout" "$stage/service.stderr" "$stage/agent.stdout" "$stage/agent.stderr"
    rmdir "$stage"
}
trap cleanup EXIT
install -m 0755 "$binary" "$stage/agent-peer"
actual=$(shasum -a 256 "$stage/agent-peer"); actual=${actual%% *}
[[ $actual == "$expected" ]] || { echo "Copied executable hash mismatch." >&2; exit 2; }
codesign --verify --strict "$stage/agent-peer"
install -m 0600 "$source_root/tests/auth/macos-agent-service.plist" "$stage/service.plist"
install -m 0600 "$source_root/probes/macos/probe-agent.plist" "$stage/agent.plist"
for role in service agent; do
    install -m 0600 /dev/null "$stage/$role.stdout"
    install -m 0600 /dev/null "$stage/$role.stderr"
    /usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $stage/agent-peer" "$stage/$role.plist"
    /usr/libexec/PlistBuddy -c "Set :StandardOutPath $stage/$role.stdout" "$stage/$role.plist"
    /usr/libexec/PlistBuddy -c "Set :StandardErrorPath $stage/$role.stderr" "$stage/$role.plist"
done
/usr/libexec/PlistBuddy -c "Set :Label $label" "$stage/service.plist"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:2 $label" "$stage/service.plist"
/usr/libexec/PlistBuddy -c "Add :MachServices:$label bool true" "$stage/service.plist"
/usr/libexec/PlistBuddy -c "Set :Label $label.agent" "$stage/agent.plist"
/usr/libexec/PlistBuddy -c "Set :LimitLoadToSessionType $session_type" "$stage/agent.plist"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:1 string --agent" "$stage/agent.plist"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:2 string $label" "$stage/agent.plist"
chown "$console_uid" "$stage/agent.stdout" "$stage/agent.stderr"
plutil -lint "$stage/service.plist" "$stage/agent.plist"
launchctl bootstrap system "$stage/service.plist"
"$stage/agent-peer" --background-peer "$label"
grep -q 'agent_service_scope_denied=1' "$stage/service.stdout"
[[ $(stat -f '%u' /dev/console) == "$console_uid" ]] || { echo "Console changed; refusing launch." >&2; exit 2; }
launchctl bootstrap "$domain" "$stage/agent.plist"
exit_code=""
pattern='last exit code = ([0-9]+)'
for ((attempt=0; attempt<25; attempt++)); do
    status=$(launchctl print "$domain/$label.agent")
    if [[ $status =~ $pattern ]]; then exit_code=${BASH_REMATCH[1]}; break; fi
    sleep 1
done
cat "$stage/service.stdout" "$stage/service.stderr" "$stage/agent.stdout" "$stage/agent.stderr"
[[ $exit_code == 0 ]]
grep -q 'agent_service_attached=1 cross_process=1' "$stage/service.stdout"
grep -q 'agent_service_admission=1 synthetic_verification=1' "$stage/service.stdout"
grep -q 'agent_service_admission_revoked=1' "$stage/service.stdout"
grep -q 'graphical_agent_bound_scope=1' "$stage/agent.stdout"
grep -q 'agent_service_empty_cleanup=1' "$stage/service.stdout"
grep -q 'graphical_agent_complete=1 background_rejected=0' "$stage/agent.stdout"
echo "agent_service_cross_process_pass=1 persistent_install=0 media=0 input=0"
