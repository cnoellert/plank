# PAM Qualification

The candidate PAM policy is installed as `/etc/pam.d/remote-desktop`. It denies
root and users outside `remote-desktop-users` before delegating authentication,
account, password, and session handling to Rocky's authselect-managed
`system-auth` stack. Do not edit `system-auth` directly.

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
sudo ./build/qualification/connect-probe-pam --account-only root
sudo ./build/qualification/connect-probe-pam --account-only operator
```

Expected results are rejection for root and success for an authorized active
account. A complete Phase 0 result also requires an interactive success and
failure test for one local account and one SSSD/FreeIPA account.

## Phase 2 Live Integration Status

On 2026-08-20, the PAM broker ran as the sandboxed system service on hardware-test-host with
an exposure score of 3.9 (`OK`). Its socket was `root:stationconnect-auth` mode
`0660`; Sunshine ran unprivileged. TLS 1.2, pairing, root authentication, and
unauthenticated application-list access were rejected. Restarting the broker
during a live password challenge returned a protocol denial, completed PAM
cleanup, and left Sunshine running. The focused authentication suite passed 10
tests; the broader non-hardware host suite passed 391 with two expected skips.

The live lifecycle gate passed on the dedicated NUC. A manual login created
logind session `c5` with service `remote-desktop`; its leader was the broker's
short-lived worker rather than the persistent broker. Moonlight consumed its
one-use token immediately after the successful Desktop launch. Ending the
stream removed the worker and `c5` within two seconds, and restarting Moonlight
required a new login. An empty-password denial likewise left no worker or
logind session. Real passwords remain manual-only and must not be automated.

The development host now listens on wildcard IPv4/IPv6 addresses to survive
interface changes. Firewalld is disabled on hardware-test-host, so this is permitted only
on its isolated qualification network. Production packaging must expose those
listeners only in the approved VPN interface's firewalld zone.
