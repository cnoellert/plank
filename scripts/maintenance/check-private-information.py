#!/usr/bin/env python3
"""Check new Git content without printing matched secrets or source excerpts.

This is prevention, not certification of existing history, binary artifacts or
submodule object databases. See docs/security/private-information.md.
"""
import argparse
import base64
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile

POLICY_ROOT = Path(__file__).resolve().parents[2]
GENERIC_VALUES = {b'password', b'administrator', b'admin', b'root', b'test', b'username'}
DOC_SUFFIXES = {'.md', '.plan', '.rst', '.txt'}
IPV4 = re.compile(rb'(?<![\w.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?!\w|\.[0-9])')
DOCUMENTATION_NETS = tuple(ipaddress.ip_network(n) for n in (
    '192.0.2.0/24', '198.51.100.0/24', '203.0.113.0/24'))
# These canonical network definitions are useful documentation, not deployment
# destinations. Other real address literals belong in private operational notes.
NETWORK_CONSTANTS = {'10.0.0.0', '172.16.0.0', '192.168.0.0', '169.254.0.0', '255.255.255.255'}
PRIVATE_PATH = re.compile(rb'/(?:home|Users)/[A-Za-z0-9_.-]+(?:/|\b)')
LOCAL_DOMAIN = re.compile(rb'(?i)\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:local|internal|lan)\b')
MACHINE_NAME = re.compile(rb'(?i)(?<![\w-])(?:ws|mac|plank)\d{2,3}(?![\w-]|,\d)')
FORBIDDEN_NAMES = re.compile(r'(?i)^(?:passwords?[_-]audit(?:\..*)?|id_(?:rsa|ed25519|ecdsa)(?:\.pub)?|credentials\.json|authentication\.json)$')


def git(*args, data=None, check=True):
    result = subprocess.run(['git', *args], input=data, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    if check and result.returncode:
        raise RuntimeError('Git query failed; no source content was printed.')
    return result


def read_denylist(root):
    configured = git('config', '--path', '--get', 'plank.privateDenylist', check=False)
    if configured.returncode == 1:
        return []
    if configured.returncode:
        raise RuntimeError('Cannot read the private denylist configuration.')
    path = Path(os.fsdecode(configured.stdout).strip()).expanduser().resolve()
    try:
        path.relative_to(root)
    except ValueError:
        pass
    else:
        raise RuntimeError('The private denylist must be outside the repository.')
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RuntimeError('The private denylist must be owner-only (0600).')
    outside_env = dict(os.environ)
    for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR'):
        outside_env.pop(key, None)
    other_checkout = subprocess.run(['git', '-C', str(path.parent), 'rev-parse', '--show-toplevel'],
                                    env=outside_env, capture_output=True)
    if other_checkout.returncode == 0:
        raise RuntimeError('The private denylist must be outside every Git checkout.')
    values = []
    for line in path.read_bytes().splitlines():
        value = line.strip()
        if value and not value.startswith(b'#') and len(value) >= 4 and value.lower() not in GENERIC_VALUES:
            values.append(value)
            if len(value) >= 8:
                values.extend((base64.b64encode(value), value.hex().encode('ascii')))
    return values


def content_findings(data, documentation, denylist):
    found = set()
    if any(value in data for value in denylist):
        found.add('private-denylist')
    if documentation:
        if PRIVATE_PATH.search(data):
            found.add('personal-home-path')
        if LOCAL_DOMAIN.search(data):
            found.add('internal-domain')
        if MACHINE_NAME.search(data):
            found.add('deployment-machine-name')
        for match in IPV4.finditer(data):
            line_start = data.rfind(b'\n', 0, match.start()) + 1
            preceding = data[line_start:match.start()]
            # Four-part NVIDIA codec-header versions are not network addresses.
            # Require the version context on the same line, not a global IP allowlist.
            if re.search(rb'(?i)(?:nv-codec-headers|headers\s+`[0-9a-f]{7,40}`)\s*\(?$', preceding):
                continue
            try:
                value = match.group().decode('ascii')
                address = ipaddress.ip_address(value)
            except ValueError:
                continue
            if (address.is_loopback or address.is_unspecified or address.is_multicast
                    or value in NETWORK_CONSTANTS
                    or any(address in net for net in DOCUMENTATION_NETS)):
                continue
            found.add('non-example-ipv4')
    return sorted(found)


def path_findings(path):
    parts = Path(path).parts
    name = Path(path).name
    if (FORBIDDEN_NAMES.fullmatch(name) or 'private-notes' in parts or 'private-audit' in parts
            or name == '.env' or (name.startswith('.env.') and not name.endswith(('.example', '.sample')))
            or Path(name).suffix.lower() in ('.p12', '.pfx', '.key')):
        return ['private-file-name']
    return []


def safe_label(label, denylist):
    data = os.fsencode(label)
    if any(value in data for value in denylist):
        return '[private filename]'
    # JSON escaping prevents terminal control characters/newlines in paths.
    return json.dumps(label, ensure_ascii=True)


def check_diff(diff_args, denylist):
    problems = []
    names = git('diff', '--name-only', '-z', '--no-renames', '--diff-filter=ACMR', *diff_args).stdout
    for raw in names.split(b'\0'):
        if not raw:
            continue
        path = os.fsdecode(raw)
        for rule in path_findings(path) + content_findings(raw, False, denylist):
            problems.append((path, rule))
        if diff_args == ['--cached']:
            entry = git('ls-files', '--stage', '-z', '--', path).stdout.split(b'\0')[0]
            fields = entry.split(b'\t', 1)[0].split()
            mode, oid = fields[:2]
        else:
            entry = git('ls-tree', '-z', diff_args[-1], '--', path).stdout.split(b'\0')[0]
            mode, _, oid = entry.split(b'\t', 1)[0].split()
        if mode in (b'100644', b'100755', b'120000'):
            blob = git('cat-file', 'blob', oid.decode('ascii')).stdout
            for rule in content_findings(blob, False, denylist):
                problems.append((path, rule))
        # Review only added lines for deployment examples, so a new guard does
        # not silently pretend to sanitize an existing file's entire history.
        patch = git('diff', '--no-ext-diff', '--no-textconv', '--no-renames',
                    '--unified=0', *diff_args, '--', path).stdout
        added = b'\n'.join(line[1:] for line in patch.splitlines()
                            if line.startswith(b'+') and not line.startswith(b'+++'))
        for rule in content_findings(added, Path(path).suffix in DOC_SUFFIXES, denylist):
            problems.append((path, rule))
    return problems


def gitleaks(mode, refs, denylist, message=None):
    executable = shutil.which('gitleaks')
    if not executable:
        raise RuntimeError('Install Gitleaks before committing; see docs/security/private-information.md.')
    with tempfile.TemporaryDirectory(prefix='plank-private-check-') as temporary:
        report = Path(temporary) / 'report.json'
        ignore = Path(temporary) / 'ignore'
        ignore.touch(mode=0o600)
        command = [executable, mode, '--config', str(POLICY_ROOT / '.gitleaks.toml'),
                   '--redact=100', '--no-banner', '--no-color', '--log-level=error',
                   '--ignore-gitleaks-allow', '--gitleaks-ignore-path', str(ignore),
                   '--report-format=json', '--report-path', str(report)]
        if mode == 'git':
            command += ['--staged'] if refs is None else ['--log-opts=' + refs + ' --full-history -m']
        result = subprocess.run(command, input=message, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode not in (0, 1):
            raise RuntimeError('Gitleaks failed; commit blocked. Check scanner installation/configuration.')
        findings = json.loads(report.read_text()) if report.exists() else []
        if result.returncode == 1 and not findings:
            raise RuntimeError('Gitleaks reported a failure without readable findings; commit blocked.')
        # Tool reports can contain unredacted commit text even with --redact;
        # only rule IDs and sanitized file locations leave this private temp dir.
        return [(str(f.get('File') or 'commit message'), str(f.get('RuleID', 'secret')))
                for f in findings]


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--staged', action='store_true')
    mode.add_argument('--commit-msg', type=Path)
    mode.add_argument('--range', nargs=2, metavar=('BASE', 'HEAD'))
    args = parser.parse_args()
    root = Path(os.fsdecode(git('rev-parse', '--show-toplevel').stdout).strip()).resolve()
    denylist = read_denylist(root)
    if args.staged:
        problems = check_diff(['--cached'], denylist)
        problems += gitleaks('git', None, denylist)
    elif args.commit_msg:
        message = args.commit_msg.read_bytes()
        problems = [('commit message', rule) for rule in content_findings(message, True, denylist)]
        problems += gitleaks('stdin', None, denylist, message)
    else:
        base, head = args.range
        # Resolve expressions first; never pass user-controlled flags to git log.
        head = git('rev-parse', '--verify', '--end-of-options', head + '^{commit}').stdout.decode().strip()
        if set(base) == {'0'}:
            revision = head  # New remote branch: all reachable history, no silent gap.
        else:
            base = git('rev-parse', '--verify', '--end-of-options', base + '^{commit}').stdout.decode().strip()
            revision = base + '..' + head
        problems = []
        commits = git('rev-list', revision).stdout.decode().splitlines()
        messages = []
        for commit in commits:
            lineage = git('rev-list', '--parents', '-n', '1', commit).stdout.decode().split()
            parent = lineage[1] if len(lineage) > 1 else git('hash-object', '-t', 'tree', '--stdin', data=b'').stdout.decode().strip()
            problems += check_diff([parent, commit], denylist)
            message = git('show', '-s', '--format=%B', commit).stdout
            problems += [(commit[:12] + ' message', rule) for rule in content_findings(message, True, denylist)]
            messages.append(message)
        # One scanner process covers every message, including commits whose
        # sensitive content was removed later. Do not start a scanner per commit
        # when a new remote branch requires checking its entire history.
        if messages:
            problems += gitleaks('stdin', None, denylist, b'\n\n'.join(messages))
        problems += gitleaks('git', revision, denylist)
    for label, rule in sorted(set(problems)):
        print('BLOCKED ' + safe_label(label, denylist) + ': ' + rule, file=sys.stderr)
    if problems:
        print('Keep deployment notes and credentials outside Git. No matched values were printed.', file=sys.stderr)
        return 1
    print('private_information_check=pass (new content only; not a history/publication clearance)')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(run())
    except (OSError, RuntimeError, ValueError):
        # Exception messages from file paths/configuration may themselves hold
        # private data. Never print source/tool stderr or configuration values.
        print('Privacy check could not complete. Verify Git, Gitleaks and owner-only external denylist setup; commit blocked.', file=sys.stderr)
        sys.exit(2)
