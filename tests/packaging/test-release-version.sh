#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
source "${repo_dir}/scripts/package-version.sh"
plank_load_package_version "$repo_dir"

version=$PLANK_PACKAGE_VERSION
test "$PLANK_RPM_VERSION" = "$version"
test "$PLANK_RPM_RELEASE" = 1
rg -Fxq "project(plank_qualification VERSION ${version} LANGUAGES C CXX)" \
  "${repo_dir}/CMakeLists.txt"
rg -Fxq "version = \"${version}\"" \
  "${repo_dir}/protocol/plank-transport/Cargo.toml"
rg -Fxq "__version__ = \"${version}\"" \
  "${repo_dir}/plank-relay/plank_relay/__init__.py"
rg -Fxq 'Version: @VERSION@' \
  "${repo_dir}/plank-relay/packaging/control"
rg -Fxq '%{!?plank_version:%{error:plank_version must be defined by the package builder}}' \
  "${repo_dir}/packaging/rpm/plank-host.spec"
rg -Fxq '%{!?plank_release:%{error:plank_release must be defined by the package builder}}' \
  "${repo_dir}/packaging/rpm/plank-host.spec"

echo "release_version_contract=pass"
