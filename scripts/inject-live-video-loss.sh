#!/usr/bin/env bash

set -euo pipefail

if (($# < 1 || $# > 5)); then
  echo "usage: $0 CLIENT_IP [LOSS_PERCENT] [DURATION_SECONDS] [INTERFACE] [VIDEO_PORT]" >&2
  exit 2
fi

client_ip=$1
loss_percent=${2:-5}
duration_seconds=${3:-60}
network_interface=${4:-$(ip route get "${client_ip}" | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')}
video_port=${5:-47998}
table_name=stationconnect_qualification

if [[ ! ${loss_percent} =~ ^[0-9]+$ ]] || ((loss_percent < 1 || loss_percent > 100)); then
  echo "loss percent must be an integer from 1 through 100" >&2
  exit 2
fi
if [[ ! ${duration_seconds} =~ ^[0-9]+$ ]] || ((duration_seconds < 1)); then
  echo "duration must be a positive integer" >&2
  exit 2
fi
if [[ ! ${video_port} =~ ^[0-9]+$ ]] || ((video_port < 1 || video_port > 65535)); then
  echo "video port must be an integer from 1 through 65535" >&2
  exit 2
fi
if [[ -z ${network_interface} ]] || [[ ! -d /sys/class/net/${network_interface} ]]; then
  echo "unable to resolve a valid network interface for ${client_ip}" >&2
  exit 2
fi

for command_name in awk grep ip nft pgrep sudo tr; do
  command -v "${command_name}" >/dev/null || {
    echo "required command is unavailable: ${command_name}" >&2
    exit 2
  }
done
sudo -n true

qualification_gso_mode=false
while IFS= read -r sunshine_pid; do
  if sudo -n tr '\0' '\n' <"/proc/${sunshine_pid}/environ" 2>/dev/null |
      grep -qx 'SUNSHINE_QUALIFICATION_DISABLE_UDP_GSO=1'; then
    qualification_gso_mode=true
    break
  fi
done < <(pgrep -x sunshine || true)
if [[ ${qualification_gso_mode} != true ]]; then
  echo "Sunshine must run with SUNSHINE_QUALIFICATION_DISABLE_UDP_GSO=1" >&2
  exit 2
fi

if sudo -n nft list table netdev "${table_name}" >/dev/null 2>&1; then
  echo "refusing to replace existing netdev table ${table_name}" >&2
  exit 2
fi

cleanup() {
  sudo -n nft delete table netdev "${table_name}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

threshold=$((loss_percent * 10))
sudo -n nft add table netdev "${table_name}"
sudo -n nft "add chain netdev ${table_name} egress { type filter hook egress device \"${network_interface}\" priority 0; policy accept; }"
sudo -n nft "add rule netdev ${table_name} egress ip daddr ${client_ip} udp sport ${video_port} numgen random mod 1000 < ${threshold} counter drop"

echo "Injecting ${loss_percent}% random video-datagram loss to ${client_ip}:${video_port} on ${network_interface} for ${duration_seconds}s"
sleep "${duration_seconds}"
sudo -n nft list table netdev "${table_name}"
