#!/usr/bin/env bash

set -uo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work_root=${PLANK_WORK_ROOT:-"${XDG_CACHE_HOME:-${HOME}/.cache}/plank-build/work"}
build_dir=${PLANK_BUILD_DIR:-"${work_root}/qualification"}
authorized_user=${PLANK_PAM_AUTHORIZED_USER:?Set PLANK_PAM_AUTHORIZED_USER for your test environment}
expected_denied_user=${PLANK_PAM_EXPECTED_DENIED_USER:-}
broker_binary=${PLANK_PAM_BROKER_BINARY:-/usr/libexec/plank/plank-pam-broker}
config_file=${PLANK_HOST_CONFIG:-/etc/plank/host.conf}
result=0

echo "sssd=$(systemctl is-active sssd.service 2>&1)"
root_policy=$(sudo -n "${broker_binary}" --config "${config_file}" --check-config 2>&1)
case $root_policy in
  allow_root_login=false)
    echo 'root_login_policy=deny result=pass'
    ;;
  allow_root_login=true)
    echo 'root_login_policy=allow result=pass (administrator override)'
    ;;
  *)
    echo "root_login_policy=invalid result=fail (${root_policy})"
    result=1
    ;;
esac

if sudo -n "${build_dir}/plank-probe-pam" --account-only "${authorized_user}"; then
  echo "authorized_account=${authorized_user} result=pass"
else
  echo "authorized_account=${authorized_user} result=fail"
  result=1
fi

if [[ -n $expected_denied_user ]]; then
  if sudo -n "${build_dir}/plank-probe-pam" --account-only "${expected_denied_user}"; then
    echo "external_policy_denial=${expected_denied_user} result=fail (account was accepted)"
    result=1
  else
    echo "external_policy_denial=${expected_denied_user} result=pass"
  fi
else
  echo 'external_policy_denial=not-configured (non-blocking; authorization is delegated to PAM/SSSD/HBAC)'
fi

exit "${result}"
