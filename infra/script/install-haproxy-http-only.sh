#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

require_cmd ssh
require_cmd scp

# --- derive IPs/hostnames from config.sh ---
read -r _ LB_HOSTNAME LB_OCTET <<<"${LB[*]}"
# Prefer explicit lb_ip from terraform.tfvars (loaded by common.sh) when set.
LB_IP="${LB_IP:-${NETWORK_PREFIX}.${LB_OCTET}}"

filer_servers=""
s3_servers=""
idx=0
for x in "${FILERS[@]}"; do
  idx=$((idx+1))
  oc="$(echo "${x}" | awk '{print $3}')"
  ip="${NETWORK_PREFIX}.${oc}"
  filer_servers+="    server filer${idx} ${ip}:${FILER_PORT} check"$'\n'
  s3_servers+="    server s3_${idx} ${ip}:${S3_PORT} check"$'\n'
done

mkdir -p scripts/generated

echo "==> Installing HAProxy on ${LB_HOSTNAME} (${LB_IP})"
ssh_exec "${LB_IP}" "sudo bash -s" <<'EOF'
set -euo pipefail
apt-get update -y
apt-get install -y haproxy
EOF

echo "==> Generating HAProxy config (HTTP-only): scripts/generated/haproxy.cfg"
cat > scripts/generated/haproxy.cfg <<EOF
# Managed by seaweedfs scripts. Do not edit on the VM.

global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 4096

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5s
    timeout client  60s
    timeout server  60s

# Public entrypoint (HTTP only)
frontend http_in
    bind *:80
    mode http

    # normalize host
    http-request set-header Host %[req.hdr(Host),lower]

    # Host routing
    acl host_s3      hdr(host) -i ${DOMAIN_S3}
    acl host_storage hdr(host) -i ${DOMAIN_STORAGE}

    use_backend s3_nodes    if host_s3
    use_backend filer_nodes if host_storage

    default_backend default_404

backend default_404
    http-request return status 404 content-type "text/plain" lf-string "Not Found\n"

# SeaweedFS Filer
backend filer_nodes
    balance roundrobin
    option httpchk
    http-check send meth HEAD uri /
    http-check expect status 200
${filer_servers}

# SeaweedFS S3 Gateway
backend s3_nodes
    balance roundrobin
    option httpchk GET /
    # Seaweed S3 root usually returns 403 when healthy
    http-check expect status 403
${s3_servers}

listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 5s
EOF

echo "==> Uploading config to ${LB_HOSTNAME} and restarting HAProxy"
scp_to "${LB_IP}" "scripts/generated/haproxy.cfg" "/tmp/haproxy.cfg"
ssh_exec "${LB_IP}" "sudo bash -s" <<'EOF'
set -euo pipefail
install -m 0644 /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg

# Validate config before restart
haproxy -c -f /etc/haproxy/haproxy.cfg

systemctl restart haproxy
systemctl --no-pager --full status haproxy | head -n 20 || true

echo
echo "Listening ports:"
ss -lntp | egrep ':(80|8404)\b' || true
EOF

echo
echo "==> DONE"
echo "LB:    ${LB_IP}"
echo "Stats: http://${LB_IP}:8404/stats"
echo
echo "Test without DNS (replace LB_IP if needed):"
echo "  curl -I --resolve ${DOMAIN_STORAGE}:80:${LB_IP} http://${DOMAIN_STORAGE}/"
echo "  curl -I --resolve ${DOMAIN_S3}:80:${LB_IP} http://${DOMAIN_S3}/"
