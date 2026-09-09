#!/bin/bash
# Non-mutating lifecycle tests. --filesystem adds an isolated root-owned fixture.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
source "$root/packaging/macos/pkg-common.sh"
checks=0
ok() { checks=$((checks+1)); }
reject() { if ( "$@" ) >/dev/null 2>&1; then fail "Expected rejection: $*"; fi; ok; }
for script in pkg-common.sh pkg-preinstall pkg-postinstall pkg-uninstall; do
    /bin/bash -n "$root/packaging/macos/$script"; ok
done
missing_job system/example 'Could not find service "example" in domain for system'; ok
missing_job gui/501/example 'Could not find domain for'; ok
reject missing_job system/example 'Could not find service "unrelated"'
reject missing_job system/example 'Operation not permitted'
reject preflight /Volumes/Other

# Test actual job_state failure handling; never invoke launchctl.
(
    launchctl_cmd() { echo 'Operation not permitted'; return 1; }
    reject job_state system/example
)
ok
(
    launchctl_cmd() { echo 'Could not find service "example"'; return 1; }
    if job_state system/example; then fail 'Missing job accepted as present'; fi
)
ok

(
    step=0; bootouts=0; sleeps=0
    launchctl_cmd() { [[ $1 = bootout ]]; bootouts=$((bootouts+1)); }
    pause_drain() { sleeps=$((sleeps+1)); }
    # launchd has removed the job, but its process is still retiring.
    job_state() {
        step=$((step+1)); job_output=' pid = 12345'
        [[ $step = 1 ]]
    }
    process_alive() { [[ $1 = 12345 && $step -lt 5 ]]; }
    stop_job system/example
    [[ $step = 5 && $bootouts = 1 && $sleeps = 3 ]]
)
ok
(
    job_state() { job_output=' pid = 12345'; return 0; }
    launchctl_cmd() { :; }
    process_alive() { return 0; }
    pause_drain() { :; }
    reject stop_job system/example
)
ok
(
    job_state() { return 1; }
    launchctl_cmd() { fail 'Absent job should not be stopped'; }
    stop_job system/example
)
ok
(
    gui_domains() { echo gui/501; echo gui/502; }
    console_uid() { echo 501; }
    calls=''
    launchctl_cmd() { calls="$calls|$*"; }
    start_roles
    [[ $calls = "|bootstrap system /Library/LaunchDaemons/$machine.plist|bootstrap gui/501 /Library/LaunchAgents/$desktop.plist|bootstrap gui/502 /Library/LaunchAgents/$desktop.plist" ]]
)
ok
(
    gui_domains() { :; }
    console_uid() { echo 0; }
    calls=''
    launchctl_cmd() { calls="$calls|$*"; }
    start_roles
    [[ $calls = "|bootstrap system /Library/LaunchDaemons/$machine.plist|bootstrap loginwindow /Library/LaunchAgents/$signin.plist" ]]
)
ok

if [[ $(uname -s) = Darwin ]]; then
    for role in machine desktop sign-in; do
        plist="$root/packaging/macos/la.instinctual.PLANK.Host.$role.plist"
        /usr/bin/plutil -lint "$plist" >/dev/null
        [[ $(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist") = "$executable" ]]
        ok
    done
fi

if [[ ${1:-} = --filesystem ]]; then
    [[ $(uname -s) = Darwin && $(id -u) = 0 ]] || fail 'Filesystem fixture requires root on the development Mac'
    fixture=$(/usr/bin/mktemp -d '/Library/Application Support/PLANKPackageTest.XXXXXX')
    cleanup() {
        case $fixture in '/Library/Application Support/PLANKPackageTest.'*) /bin/rm -rf "$fixture";; esac
    }
    trap cleanup EXIT
    state="$fixture/state"; logs="$fixture/logs"
    initialize_state
    [[ $(/usr/libexec/PlistBuddy -c 'Print :Address' "$state/host.plist") = 0.0.0.0 ]]; ok
    [[ $(/usr/libexec/PlistBuddy -c 'Print :Port' "$state/host.plist") = 28989 ]]; ok
    /usr/bin/plutil -replace Port -integer 29999 "$state/host.plist"
    before=$(/usr/bin/shasum -a 256 "$state/host.plist" "$state/SignIn/"* "$logs/"*)
    initialize_state
    after=$(/usr/bin/shasum -a 256 "$state/host.plist" "$state/SignIn/"* "$logs/"*)
    [[ $before = "$after" ]]; ok
    /bin/ln -s "$state/host.plist" "$fixture/symlink"
    reject safe_file "$fixture/symlink" 644
    /bin/ln "$state/host.plist" "$fixture/hardlink"
    reject safe_file "$state/host.plist" 644
    /bin/rm "$fixture/hardlink"
    /bin/chmod 666 "$state/host.plist"
    reject check_configuration
    /bin/chmod 644 "$state/host.plist"
    /bin/ln -s "$state" "$fixture/directory-link"
    reject safe_directory "$fixture/directory-link"
    /bin/chmod 777 "$logs"
    reject initialize_state
    /bin/chmod 700 "$logs"
    /bin/rm "$logs/host-machine.log"
    /bin/ln -s "$fixture/not-a-log" "$logs/host-machine.log"
    reject initialize_state
    [[ ! -e $fixture/not-a-log ]]; ok
fi
echo "macos_pkg_scripts_checks=$checks pass; no product services changed"
