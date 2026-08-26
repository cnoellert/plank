#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
host_http="${repo_dir}/host/sunshine-fork/src/nvhttp.cpp"
client_computer="${repo_dir}/client/moonlight-qt-fork/app/backend/nvcomputer.cpp"
client_model="${repo_dir}/client/moonlight-qt-fork/app/gui/computermodel.cpp"
client_view="${repo_dir}/client/moonlight-qt-fork/app/gui/PcView.qml"
host_builder="${repo_dir}/scripts/build-host-package-binaries.sh"

rg -Fq 'tree.put("root.StationConnectHostVersion", PROJECT_VERSION);' \
  "$host_http"
rg -Fq 'tree.put("root.StationConnectHostMetadataVersion", stationconnect_host_metadata_version);' \
  "$host_http"
rg -Fq 'NvHTTP::getXmlString(serverInfo, "StationConnectHostMetadataVersion").toInt()' \
  "$client_computer"
rg -Fq 'NvHTTP::getXmlString(serverInfo, "StationConnectHostVersion")' \
  "$client_computer"
rg -Fq 'names[StationConnectHostVersionRole] = "stationConnectHostVersion";' \
  "$client_model"
rg -Fq 'model.stationConnectHostVersion' "$client_view"
rg -Fq 'BUILD_VERSION="$package_version"' "$host_builder"

echo 'host_version_discovery=pass'
