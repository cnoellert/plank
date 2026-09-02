#!/usr/bin/env bash

# Load the public PLANK SemVer and its package-manager-specific metadata.
# Callers must pass the repository root containing packaging/VERSION.
plank_load_package_version() {
  if (($# != 1)); then
    echo "usage: plank_load_package_version REPOSITORY_ROOT" >&2
    return 2
  fi

  local repository_root=$1
  local version_file="${repository_root}/packaging/VERSION"
  [[ -f $version_file ]] || {
    echo "PLANK version file is unavailable: ${version_file}" >&2
    return 1
  }

  PLANK_PACKAGE_VERSION=$(<"$version_file")
  [[ $PLANK_PACKAGE_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "invalid shared package version: ${PLANK_PACKAGE_VERSION}" >&2
    return 1
  }

  # RPM requires a Release even though it is not part of PLANK's displayed
  # product version. A new PLANK SemVer always starts at packaging release 1.
  PLANK_RPM_VERSION=$PLANK_PACKAGE_VERSION
  PLANK_RPM_RELEASE=1
}
