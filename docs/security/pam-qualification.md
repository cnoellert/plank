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
`0660`; Sunshine ran unprivileged and bound all product listeners to the
explicit development address. TLS 1.2, pairing, root authentication, and
unauthenticated application-list access were rejected. Restarting the broker
during a live password challenge returned a protocol denial, completed PAM
cleanup, and left Sunshine running. The focused authentication suite passed 10
tests; the broader non-hardware host suite passed 391 with two expected skips.

The remaining live gate is deliberately manual: enter a real account password
in the NUC UI, launch Desktop, end the stream, and confirm that the PAM session
and token disappear. Do not automate that credential.
