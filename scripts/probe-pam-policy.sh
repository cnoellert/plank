#!/usr/bin/env bash

set -uo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=${CONNECT_BUILD_DIR:-"${repo_dir}/build/qualification"}
authorized_user=${CONNECT_PAM_AUTHORIZED_USER:?Set STATIONCONNECT_PAM_AUTHORIZED_USER for your test environment}
unauthorized_user=${CONNECT_PAM_UNAUTHORIZED_USER:-gdm}
result=0

echo "sssd=$(systemctl is-active sssd.service 2>&1)"
if sudo -n "${build_dir}/connect-probe-pam" --account-only root; then
  echo 'root_rejection=fail (account was accepted)'
  result=1
else
  echo 'root_rejection=pass'
fi

if sudo -n "${build_dir}/connect-probe-pam" --account-only "${authorized_user}"; then
  echo "authorized_account=${authorized_user} result=pass"
else
  echo "authorized_account=${authorized_user} result=fail"
  result=1
fi

if sudo -n "${build_dir}/connect-probe-pam" --account-only "${unauthorized_user}"; then
  echo "unauthorized_account=${unauthorized_user} result=fail (account was accepted)"
  result=1
else
  echo "unauthorized_account=${unauthorized_user} result=pass"
fi

exit "${result}"
