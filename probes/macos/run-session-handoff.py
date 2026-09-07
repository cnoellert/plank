#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Administrator-run, bounded macOS qualification; not a product service.

Only the installed signed probe and two root-owned sibling helpers are run.
No network listener, credentials, user shell, login action or persistent agent.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import select
import signal
import stat
import subprocess
import tempfile
import time
import uuid

APP = Path('/Applications/PLANK Host Probe.app')
EXECUTABLE = APP / 'Contents/MacOS/plank-host-probe'
LAUNCHCTL = '/bin/launchctl'


def command(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=5)


def protected_file(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
        raise RuntimeError('Expected root-owned non-writable regular tool: ' + path.name)


def parse_snapshot(line, allowed_uid):
    data = json.loads(line)
    if not isinstance(data, dict) or set(data) != {'phase', 'uid'}:
        raise ValueError('Invalid observer record')
    phase, uid = data['phase'], data['uid']
    if type(uid) is not int or not 0 <= uid <= 0xffffffff:
        raise ValueError('Invalid observer UID')
    if phase == 'unavailable':
        return None
    if phase == 'sign-in' and uid == 0:
        return ('sign-in', 0)
    if phase == 'desktop' and uid == allowed_uid:
        return ('desktop', uid)
    raise ValueError('Console is outside the operator-designated user scope')


def report(event, **values):
    print(json.dumps({'event': event, **values}, sort_keys=True), flush=True)


class Controller:
    def __init__(self, args):
        self.args = args
        self.tools = Path(__file__).resolve().parent
        self.stage = None
        self.job = None
        self.generation = 0
        self.completed = 0
        self.completed_phases = set()
        self.media_passed = True
        self.crash_injected = False
        self.stop_requested = False

    def validate_tools(self):
        directory = self.tools.stat()
        if directory.st_uid != 0 or directory.st_mode & 0o022:
            raise RuntimeError('Tool directory must be root-owned and not group/world writable')
        for path in [EXECUTABLE, self.tools / 'session-observer', self.tools / 'desktop-inventory']:
            protected_file(path)
        if hashlib.sha256(EXECUTABLE.read_bytes()).hexdigest() != self.args.app_sha256:
            raise RuntimeError('Installed probe hash differs from this qualification build')
        if command(['/usr/bin/codesign', '--verify', '--strict', str(APP)]).returncode:
            raise RuntimeError('Installed probe signature verification failed')

    @staticmethod
    def parse_inventory(output):
        data = json.loads(output)
        displays = data.get('displays')
        if not isinstance(displays, list) or not 1 <= len(displays) < 32:
            raise RuntimeError('Independent display inventory unavailable or unbounded')
        ids = [item['id'] for item in displays]
        if any(type(value) is not int or value <= 0 for value in ids):
            raise RuntimeError('Invalid independent display identity')
        return set(ids)

    def display_ids(self):
        # A background root process does not share LoginWindow's display list.
        # Bootstrap an independent, read-only observer in the active graphical
        # domain. Never treat an empty background inventory as successful removal.
        uid = os.stat('/dev/console').st_uid
        if uid not in (0, self.args.uid):
            raise RuntimeError('Display verification outside designated user scope')
        domain = 'loginwindow' if uid == 0 else 'gui/' + str(uid)
        label = 'la.instinctual.PLANK.handoff-inventory.' + uuid.uuid4().hex
        folder = self.stage / ('inventory-' + uuid.uuid4().hex)
        folder.mkdir(mode=0o755)
        output = folder / 'stdout'
        fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        os.fchown(fd, uid, -1)
        os.close(fd)
        config = folder / 'agent.plist'
        with config.open('xb') as file:
            plistlib.dump({'Label': label, 'ProgramArguments': [str(self.tools / 'desktop-inventory')],
                          'LimitLoadToSessionType': 'LoginWindow' if uid == 0 else 'Aqua',
                          'RunAtLoad': True, 'ProcessType': 'Interactive',
                          'StandardOutPath': str(output), 'StandardErrorPath': '/dev/null'}, file)
        service = domain + '/' + label
        try:
            if command([LAUNCHCTL, 'bootstrap', domain, str(config)]).returncode:
                raise RuntimeError('Graphical display observer bootstrap failed')
            deadline = time.monotonic() + 3
            while True:
                status = command([LAUNCHCTL, 'print', service])
                match = re.search(r'last exit code = (\d+)', status.stdout)
                if match:
                    if int(match[1]) != 0:
                        raise RuntimeError('Graphical display observer failed')
                    break
                if status.returncode or time.monotonic() >= deadline:
                    raise RuntimeError('Graphical display observer unavailable')
                time.sleep(0.05)
            fd = os.open(output, os.O_RDONLY | os.O_NOFOLLOW)
            try:
                raw = os.read(fd, 16385)
            finally:
                os.close(fd)
            if len(raw) > 16384:
                raise RuntimeError('Unbounded graphical inventory')
            return self.parse_inventory(raw)
        finally:
            command([LAUNCHCTL, 'bootout', service])
            output.unlink()
            config.unlink()
            folder.rmdir()

    def launch(self, target):
        self.validate_tools()
        phase, uid = target
        domain = 'loginwindow' if phase == 'sign-in' else 'gui/' + str(uid)
        if command([LAUNCHCTL, 'print', domain]).returncode:
            return False  # Session announcement can precede launchd readiness.
        self.generation += 1
        folder = self.stage / str(self.generation)
        folder.mkdir(mode=0o755)
        label = 'la.instinctual.PLANK.handoff-probe.' + uuid.uuid4().hex
        paths = [folder / 'stdout', folder / 'stderr']
        for path in paths:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            os.fchown(fd, uid, -1)
            os.close(fd)
        spec = {
            'Label': label,
            'ProgramArguments': [str(EXECUTABLE), '--handoff-session'],
            'LimitLoadToSessionType': 'LoginWindow' if phase == 'sign-in' else 'Aqua',
            'RunAtLoad': True, 'ProcessType': 'Interactive',
            'StandardOutPath': str(paths[0]), 'StandardErrorPath': str(paths[1]),
        }
        if self.args.timing_mode != 'baseline':
            spec['ProgramArguments'].append('--' + self.args.timing_mode)
        config = folder / 'agent.plist'
        with config.open('xb') as output:
            plistlib.dump(spec, output)
        self.job = dict(target=target, domain=domain, label=label, paths=paths,
                        offsets=[0, 0], pending=['', ''], lines=[], display=None,
                        ready=False, started=time.monotonic(), pid=None)
        result = command([LAUNCHCTL, 'bootstrap', domain, str(config)])
        if result.returncode:
            raise RuntimeError('Graphical job bootstrap failed: ' + str(result.returncode))
        report('launch', generation=self.generation, phase=phase, uid=uid)
        return True

    def read_output(self):
        job = self.job
        for index, path in enumerate(job['paths']):
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
            try:
                size = os.fstat(fd).st_size
                if size > 2 * 1024 * 1024 or size < job['offsets'][index]:
                    raise RuntimeError('Unbounded or truncated worker diagnostic output')
                os.lseek(fd, job['offsets'][index], os.SEEK_SET)
                raw = os.read(fd, size - job['offsets'][index])
                job['offsets'][index] += len(raw)
            finally:
                os.close(fd)
            content = job['pending'][index] + raw.decode('utf-8', errors='replace')
            lines = content.split('\n')
            job['pending'][index] = lines.pop()
            for line in lines:
                if not line:
                    continue
                job['lines'].append(line)
                report('worker', generation=self.generation, message=line)
                match = re.fullmatch(r'media_owner_ready=1 display=(\d+) requested=(\d+)x(\d+) parent_verified=1', line)
                if match:
                    expected = ('1920', '1080') if job['target'][0] == 'sign-in' else ('3840', '2160')
                    if match.groups()[1:] != expected:
                        raise RuntimeError('Worker geometry does not match the requested phase')
                    job['display'] = int(match[1])
                    if job['display'] not in self.display_ids():
                        raise RuntimeError('Controller cannot independently see the owned display')
                if line.startswith('first_encoded_frame pixels=') and job['display']:
                    expected = '1920x1080' if job['target'][0] == 'sign-in' else '3840x2160'
                    if line != 'first_encoded_frame pixels=' + expected:
                        raise RuntimeError('Encoded geometry does not match the session phase')
                    job['ready'] = True
                    report('media-ready', generation=self.generation, phase=job['target'][0])

    def status(self):
        job = self.job
        result = command([LAUNCHCTL, 'print', job['domain'] + '/' + job['label']])
        match = re.search(r'^\s*pid = (\d+)\s*$', result.stdout, re.M)
        if match:
            job['pid'] = int(match[1])
            return True
        return False

    def retire(self, transition):
        job = self.job
        if not job:
            return
        report('retire', generation=self.generation, transition=transition)
        service = job['domain'] + '/' + job['label']
        deadline = time.monotonic() + 8
        while True:
            self.read_output()
            running = self.status()
            if not running:
                break
            # Repeated narrow signal also covers startup before its handler exists.
            command([LAUNCHCTL, 'kill', 'SIGUSR1', service])
            if time.monotonic() >= deadline:
                command([LAUNCHCTL, 'kill', 'SIGKILL', service])
                raise RuntimeError('Worker missed orderly retirement deadline')
            time.sleep(0.2)
        command([LAUNCHCTL, 'bootout', service])
        self.read_output()
        if not job['display']:
            raise RuntimeError('No observed display identity; cannot qualify cleanup')
        while job['display'] in self.display_ids():
            if time.monotonic() >= deadline:
                raise RuntimeError('Old virtual display did not disappear')
            time.sleep(0.2)
        if job['pid']:
            try:
                os.kill(job['pid'], 0)  # Read-only liveness; never signal a reused PID.
            except ProcessLookupError:
                pass
            else:
                raise RuntimeError('Old worker PID is still alive')
        normal = any(line.startswith('media_owner_cleanup ') and 'normal_exit=1' in line
                     and 'display_removed=1' in line for line in job['lines'])
        report('old-resources-gone', generation=self.generation, worker_exited=True,
               display_removed=True)
        if not normal and not transition:
            raise RuntimeError('Steady-state shutdown did not report ordered cleanup')
        if not job['ready']:
            raise RuntimeError('Worker retired before its first verified encoded frame')
        media_passed = True
        summary_seen = False
        for line in job['lines']:
            if line.startswith('capture_encode submitted='):
                summary_seen = True
                fields = dict(re.findall(r'(\w+)=([^ ]+)', line))
                if (fields.get('overflow') != '0' or fields.get('dropped') != '0' or
                        fields.get('encoded') != fields.get('submitted') or
                        fields.get('result') not in ('0', '10')):
                    media_passed = False
        # OS session teardown may remove the process before it can print final
        # counters. Keep that media gate unqualified, not silently successful.
        media_passed &= summary_seen
        self.media_passed &= media_passed
        report('retired', generation=self.generation, orderly=normal,
               os_session_reclaimed=not normal, display_removed=True, strict_media_gate=media_passed)
        self.completed += 1
        self.completed_phases.add(job['target'][0])
        self.job = None

    def run(self):
        self.validate_tools()
        self.stage = Path(tempfile.mkdtemp(prefix='plank-handoff.', dir='/private/tmp'))
        self.stage.chmod(0o755)
        watcher = subprocess.Popen([str(self.tools / 'session-observer'), '--machine-watch'],
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        os.set_blocking(watcher.stdout.fileno(), False)
        deadline = time.monotonic() + self.args.seconds
        target = None
        pending = b''
        failed = False
        try:
            while time.monotonic() < deadline and not self.stop_requested:
                if watcher.poll() is not None:
                    raise RuntimeError('Machine session observer exited unexpectedly')
                readable, _, _ = select.select([watcher.stdout], [], [], 0.2)
                if readable:
                    pending += os.read(watcher.stdout.fileno(), 4096)
                    if len(pending) > 8192:
                        raise RuntimeError('Unbounded machine observer output')
                    while b'\n' in pending:
                        line, pending = pending.split(b'\n', 1)
                        target = parse_snapshot(line, self.args.uid)
                        report('console-state', phase=target[0] if target else 'unavailable')
                        if self.job and self.job['target'] != target:
                            self.retire(transition=True)
                if self.job:
                    self.read_output()
                    running = self.status()
                    if self.args.inject_worker_crash and self.job['ready'] and not self.crash_injected:
                        self.crash_injected = True
                        command([LAUNCHCTL, 'kill', 'SIGKILL', self.job['domain'] + '/' + self.job['label']])
                        report('injected-worker-crash', generation=self.generation)
                    age = time.monotonic() - self.job['started']
                    if age > 12 and not self.job['ready']:
                        raise RuntimeError('New graphical worker did not become ready')
                    if age > 2 and not running:
                        raise RuntimeError('Worker exited without a machine session transition')
                elif target:
                    self.launch(target)
            self.retire(transition=False)
            if not self.completed:
                raise RuntimeError('No graphical worker completed qualification')
            report('handoff-probe-complete', generations=self.completed,
                   both_session_phases_observed=len(self.completed_phases) == 2,
                   lifecycle_gate=True, strict_media_gate=self.media_passed)
            if not self.media_passed:
                raise RuntimeError('Lifecycle completed but strict media qualification failed')
        except Exception:
            failed = True
            raise
        finally:
            if failed and self.job:
                try:
                    self.retire(transition=False)
                except Exception as error:
                    report('cleanup-failure', detail=str(error))
                    command([LAUNCHCTL, 'bootout', self.job['domain'] + '/' + self.job['label']])
            watcher.terminate()
            try:
                watcher.wait(timeout=3)
            except subprocess.TimeoutExpired:
                watcher.kill()
                watcher.wait()
            watcher.stdout.close()
            report('diagnostics-retained', path=str(self.stage))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--uid', type=int, required=True, help='Explicit operator-authorized desktop UID')
    parser.add_argument('--app-sha256', required=True)
    parser.add_argument('--seconds', type=int, default=180)
    parser.add_argument('--timing-mode', choices=('baseline', 'retain-sample', 'synthetic-pts', 'relative-pts', 'low-latency', 'encoding-speed'),
                        default='baseline', help='Isolated probe comparison; never product timestamp policy')
    parser.add_argument('--inject-worker-crash', action='store_true',
                        help='Negative test: kill only this controller\'s first ready job and require failure')
    args = parser.parse_args()
    if os.geteuid() != 0 or not 1 <= args.uid < 0xffffffff or not 10 <= args.seconds <= 180:
        parser.error('Requires root, a non-root UID and a 10–180 second bound')
    if not re.fullmatch(r'[0-9a-f]{64}', args.app_sha256):
        parser.error('An exact installed application SHA-256 is required')
    controller = Controller(args)
    def stop(_signal, _frame):
        controller.stop_requested = True
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    try:
        controller.run()
    except Exception as error:
        report('handoff-probe-failed', detail=str(error))
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
