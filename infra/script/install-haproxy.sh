#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

require_cmd ssh
require_cmd scp

if [ "${#LB[@]}" -eq 0 ]; then
  echo "ERROR: No LB nodes found in inventory."
  exit 1
fi

filer_servers=""
s3_servers=""
idx=0
for x in "${FILERS[@]}"; do
  idx=$((idx + 1))
  oc="$(echo "${x}" | awk '{print $3}')"
  ip="${NETWORK_PREFIX}.${oc}"
  filer_servers+="    server filer${idx} ${ip}:${FILER_PORT} check"$'\n'
  s3_servers+="    server s3_${idx} ${ip}:${S3_PORT} check"$'\n'
done

mkdir -p scripts/generated

for i in "${!LB[@]}"; do
  read -r _ LB_HOSTNAME LB_OCTET <<<"${LB[$i]}"
  if [ -n "${LB_IP:-}" ] && [ "${#LB[@]}" -eq 1 ]; then
    LB_IP_EFFECTIVE="${LB_IP}"
  else
    LB_IP_EFFECTIVE="${NETWORK_PREFIX}.${LB_OCTET}"
  fi
  if [ -n "${TARGET_LB_IP:-}" ] && [ "${TARGET_LB_IP}" != "${LB_IP_EFFECTIVE}" ]; then
    continue
  fi

  echo "==> Installing HAProxy on ${LB_HOSTNAME} (${LB_IP_EFFECTIVE})"
  ssh_exec "${LB_IP_EFFECTIVE}" "sudo bash -s" <<'EOF2'
set -euo pipefail
apt-get update -y
apt-get install -y haproxy ca-certificates
mkdir -p /etc/haproxy/certs
EOF2

  CERTS_AVAILABLE="no"
  if ssh_exec "${LB_IP_EFFECTIVE}" "ls /etc/haproxy/certs/*.pem >/dev/null 2>&1"; then
    CERTS_AVAILABLE="yes"
  fi

  echo "==> Generating HAProxy config: scripts/generated/haproxy.cfg"
  cat > scripts/generated/haproxy.cfg <<EOF2
# Managed by seaweedfs scripts. Do not edit on the VM.

global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 4096
    tune.ssl.default-dh-param 2048

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5s
    timeout client  60s
    timeout server  60s

frontend http_in
    bind *:80
    http-request set-header Host %[req.hdr(Host),lower]

    acl host_s3      hdr(host) -i ${DOMAIN_S3}
    acl host_storage hdr(host) -i ${DOMAIN_STORAGE}

    use_backend s3_nodes    if host_s3
    use_backend filer_nodes if host_storage
    default_backend default_404
backend default_404
    http-request return status 404 content-type "text/plain" lf-string "Not Found\n"

backend filer_nodes
    balance roundrobin
    option httpchk
    http-check send meth GET uri /
    http-check expect status 200
${filer_servers}
backend s3_nodes
    balance roundrobin
    option httpchk GET /
    # Seaweed S3 may return 200 or 403 at root depending on config
    http-check expect rstatus (200|403)
${s3_servers}
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 5s
EOF2

  if [ "${CERTS_AVAILABLE}" = "yes" ]; then
    cat >> scripts/generated/haproxy.cfg <<EOF2

frontend https_in
    bind *:443 ssl crt /etc/haproxy/certs/
    mode http
    http-request set-header Host %[req.hdr(Host),lower]

    acl host_s3      hdr(host) -i ${DOMAIN_S3}
    acl host_storage hdr(host) -i ${DOMAIN_STORAGE}

    use_backend s3_nodes    if host_s3
    use_backend filer_nodes if host_storage
    default_backend default_404
EOF2
  else
    echo "==> No SSL certs found in /etc/haproxy/certs; HTTPS frontend will be skipped."
    echo "==> After running ./install-certbot.sh, re-run ./install-haproxy.sh to enable HTTPS."
  fi

  echo "==> Uploading config to ${LB_HOSTNAME} and restarting HAProxy"
  scp_to "${LB_IP_EFFECTIVE}" "scripts/generated/haproxy.cfg" "/tmp/haproxy.cfg"
  ssh_exec "${LB_IP_EFFECTIVE}" "sudo bash -s" <<'EOF2'
set -euo pipefail
install -m 0644 /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg

# Validate config before restart
haproxy -c -f /etc/haproxy/haproxy.cfg

systemctl restart haproxy
systemctl --no-pager --full status haproxy | head -n 20 || true

echo
echo "Listening ports:"
ss -lntp | egrep ':(80|443|8404)\b' || true
EOF2

  echo
  echo "==> DONE"
  echo "LB:        ${LB_IP_EFFECTIVE}"
  echo "Stats:     http://${LB_IP_EFFECTIVE}:8404/stats"
  echo "Storage:   https://${DOMAIN_STORAGE}/"
  echo "S3:        https://${DOMAIN_S3}/"
  echo
  echo "NOTE: for real HTTPS, place certificates under /etc/haproxy/certs/ on the LB node."
  echo "      Example: /etc/haproxy/certs/${DOMAIN_STORAGE}.pem containing fullchain and private key."

done
