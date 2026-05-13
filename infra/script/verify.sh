#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/common.sh"

MASTER_IP="${NETWORK_PREFIX}.$(echo "${MASTERS[0]}" | awk '{print $3}')"
FILER_IP="${NETWORK_PREFIX}.$(echo "${FILERS[0]}" | awk '{print $3}')"
if [ "${#LB[@]:-0}" -gt 0 ]; then
  LB_IP="${LB_IP:-${NETWORK_PREFIX}.$(echo "${LB[0]}" | awk '{print $3}')}"
else
  LB_IP="${LB_IP:-}"
fi

echo "==> Master cluster status:"
curl --connect-timeout 5 --max-time 20 -s "http://${MASTER_IP}:${MASTER_PORT}/cluster/status" | head -c 2000; echo
echo

echo "==> Volume status (Free/Max):"
curl --connect-timeout 5 --max-time 20 -s "http://${MASTER_IP}:${MASTER_PORT}/vol/status" | jq '.Volumes.Free,.Volumes.Max'
echo

echo "==> Filer reachable:"
curl --connect-timeout 5 --max-time 20 -s -I "http://${FILER_IP}:${FILER_PORT}/" | head -n 5
echo

echo "==> S3 reachable (HEAD / gives 405, GET / gives 403 when healthy):"
curl --connect-timeout 5 --max-time 20 -s -I "http://${FILER_IP}:${S3_PORT}/" | head -n 5
curl --connect-timeout 5 --max-time 20 -s -I "http://${FILER_IP}:${S3_PORT}/" -X GET | head -n 5
echo

echo "==> Upload test via Filer:"
tmp="$(mktemp)"
echo "hello seaweed $(date -Is)" > "$tmp"
curl --connect-timeout 5 --max-time 20 -s -F "file=@${tmp}" "http://${FILER_IP}:${FILER_PORT}/uploads/test-$(date +%s).txt" >/dev/null
echo "OK"
rm -f "$tmp"
echo

echo "==> HAProxy stats (if installed):"
curl --connect-timeout 5 --max-time 20 -s "http://${LB_IP}:8404/stats" | head -n 5 || true
