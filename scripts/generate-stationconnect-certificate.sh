#!/usr/bin/env bash

set -euo pipefail

if (($# < 1 || $# > 2)); then
  echo "usage: $0 OUTPUT_DIRECTORY [DNS_HOSTNAME]" >&2
  exit 2
fi

output_dir=$1
dns_hostname=${2:-$(hostname --fqdn)}

if [[ ! ${dns_hostname} =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] ||
    [[ ${dns_hostname} != *.* ]] || [[ ${dns_hostname} == *..* ]]; then
  echo "DNS_HOSTNAME must be a valid FQDN" >&2
  exit 2
fi

certificate=${output_dir}/stationconnect-cert.pem
private_key=${output_dir}/stationconnect-key.pem
if [[ -e ${certificate} || -e ${private_key} ]]; then
  echo "refusing to overwrite an existing StationConnect certificate or key" >&2
  exit 3
fi

umask 077
install -d -m 700 -- "${output_dir}"
temporary_dir=$(mktemp -d -- "${output_dir}/.certificate.XXXXXX")
cleanup() {
  rm -rf -- "${temporary_dir}"
}
trap cleanup EXIT

openssl req -new -x509 -newkey rsa:3072 -sha256 -nodes -days 825 \
  -subj "/CN=${dns_hostname}" \
  -addext "subjectAltName=DNS:${dns_hostname}" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign" \
  -addext "extendedKeyUsage=serverAuth" \
  -keyout "${temporary_dir}/key.pem" \
  -out "${temporary_dir}/cert.pem"

openssl x509 -in "${temporary_dir}/cert.pem" -noout -checkhost "${dns_hostname}" >/dev/null
install -m 600 -- "${temporary_dir}/key.pem" "${private_key}"
install -m 644 -- "${temporary_dir}/cert.pem" "${certificate}"

echo "certificate=${certificate}"
echo "private_key=${private_key}"
