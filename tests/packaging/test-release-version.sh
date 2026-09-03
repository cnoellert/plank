#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
source "${repo_dir}/scripts/package-version.sh"
plank_load_package_version "$repo_dir"

base_version=$(<"${repo_dir}/packaging/VERSION")
test "$PLANK_BASE_VERSION" = "$base_version"
if test "$PLANK_BUILD_BRANCH_RESOLVED" = main; then
  test "$PLANK_PACKAGE_VERSION" = "$base_version"
  test "$PLANK_RPM_RELEASE" = 1
else
  test "$PLANK_PACKAGE_VERSION" = "${base_version}-${PLANK_BUILD_BRANCH_RESOLVED}"
  test "$PLANK_RPM_RELEASE" = "0.${PLANK_BUILD_BRANCH_RESOLVED//-/_}.1"
fi
test "$PLANK_RPM_VERSION" = "$base_version"
rg -Fxq 'Version: @VERSION@' \
  "${repo_dir}/plank-relay/packaging/control"
rg -Fxq '%{!?plank_version:%{error:plank_version must be defined by the package builder}}' \
  "${repo_dir}/packaging/rpm/plank-host.spec"
rg -Fxq '%{!?plank_release:%{error:plank_release must be defined by the package builder}}' \
  "${repo_dir}/packaging/rpm/plank-host.spec"

echo "release_version_contract=pass"
