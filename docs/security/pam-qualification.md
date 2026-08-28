# PAM Qualification

The StationConnect PAM policy is installed as `/etc/pam.d/stationconnect-host`.
The broker denies root by default through `security.allow_root_login = false`
before delegating authentication, account authorization, credential, and
session handling to Rocky's authselect-managed `system-auth` stack. SSSD and
FreeIPA HBAC remain the administrator-owned account-authorization layer;
StationConnect has no application-specific user allowlist. Do not edit
`system-auth` directly.

Run the full probe from a local or SSH terminal so PAM can perform challenge and
response without exposing credentials in process arguments or logs:

```bash
sudo ./build/qualification/connect-probe-pam operator
```

The probe reads prompts only from `/dev/tty` with echo disabled where requested,
then exercises authentication, account management, credentials, session open,
session close, credential deletion, and `pam_end()`. Never provide a password
through chat, shell redirection, an environment variable, or automation.

Account-policy checks do not require a password:

```bash
sudo ./build/qualification/connect-probe-pam --account-only operator
./scripts/probe-pam-policy.sh
```

Expected results are a valid configured root policy and success for an
authorized active account. Root is denied when the setting is absent or false;
`true` is reported as an administrator override rather than a failed gate.
StationConnect does not invent an unauthorized account: that decision
belongs to the administrator's PAM/SSSD/FreeIPA HBAC policy. To qualify a host
whose external policy has a known denied identity, name it explicitly:

```bash
CONNECT_PAM_EXPECTED_DENIED_USER=denied-user \
  ./scripts/probe-pam-policy.sh
```

Without that variable, the external-policy denial line is reported as
non-blocking rather than assuming a service account such as `gdm` must be
denied. A complete Phase 0 result also requires an interactive success and
failure test for one local account and one SSSD/FreeIPA account. Local service
accounts should keep locked passwords; FreeIPA HBAC does not govern local
identities.

The broker reads the setting once at startup. After changing it, run
`sudo systemctl restart stationconnect-pam-broker.service`; an invalid value or
an unsafe configuration-file owner/mode prevents the broker from starting.

## Phase 2 Live Integration Status

On 2026-08-20, the PAM broker ran as the sandboxed system service on hardware-test-host with
an exposure score of 3.9 (`OK`). TLS 1.2, pairing, root authentication, and
unauthenticated application-list access were rejected. Restarting the broker
during a live password challenge returned a protocol denial, completed PAM
cleanup, and left Sunshine running. The focused authentication suite passed 10
tests; the broader non-hardware host suite passed 391 with two expected skips.

The live lifecycle gate passed on the dedicated NUC. A manual login created a
logind session whose leader was the broker's
short-lived worker rather than the persistent broker. Moonlight consumed its
one-use token immediately after the successful Desktop launch. Ending the
stream removed the worker and `c5` within two seconds, and restarting Moonlight
required a new login. An empty-password denial likewise left no worker or
logind session. The client now supports direct launch with a host and username
in argv while reading the password from standard input with terminal echo
disabled. Passwords remain forbidden in argv, environment variables, URLs,
service definitions, persistent files, and logs.

The development host now listens on wildcard IPv4/IPv6 addresses to survive
interface changes. Firewalld is disabled on hardware-test-host, so this is permitted only
on its isolated qualification network. Production packaging must expose those
listeners only in the approved VPN interface's firewalld zone.

Stage A stream admission now retains the authenticated account on its
peer-bound token, resolves it through NSS/SSSD, and requires its UID to match
the unprivileged Sunshine user before launch or resume can configure a display.
A mismatch cancels the PAM session and fails closed. On hardware-test-host, both the running
host and `operator` resolve to UID `540600009`. The focused authentication suite
passes 5 tests, and the non-hardware host matrix passes 399 with two expected
platform skips. This user-service check must be replaced by explicit selected
logind-session ownership before the Phase 8 system-service design is enabled.

The live post-restart gate passed on 2026-08-21. Sunshine, the authenticated
`operator` account, and active StationConnect PAM session `c9` all resolved to
UID `540600009` before the scaled-span stream started. Sunshine then recorded
the matching session's stereo loopback source, and the NUC passed the decoded
audio delivery gate. A cross-user live attempt remains prohibited on the
shared qualification workstation; the mismatch path is covered by the focused
host tests.

The packaged 0.3 A/V baseline ended through a controlled client-service stop
after 22 minutes. The `c10` StationConnect PAM session, broker child, and
Sunshine audio source-output all disappeared; the persistent Sunshine user
service and PAM broker remained active. Both machines were then upgraded to
matching 0.4 packages and their stale development unit overrides were retired,
so the next login exercises only the packaged launch path.
