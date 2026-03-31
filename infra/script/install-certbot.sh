#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

require_cmd ssh

CF_TOKEN="${CF_TOKEN:-}"
LE_EMAIL="${LE_EMAIL:-ops@example.com}"
LE_STAGING="${LE_STAGING:-false}"
if [ "${LE_STAGING}" = "true" ] || [ "${LE_STAGING}" = "1" ]; then
  STAGING_FLAG="--staging"
else
  STAGING_FLAG=""
fi

if [ -z "${CF_TOKEN}" ]; then
  echo "ERROR: CF_TOKEN is not set. Export CF_TOKEN with Cloudflare API token."
  exit 1
fi

if [ "${#LB[@]}" -eq 0 ]; then
  echo "ERROR: No LB nodes found in inventory."
  exit 1
fi

# Primary LB for issuing certs
read -r _ PRIMARY_LB_HOSTNAME PRIMARY_LB_OCTET <<<"${LB[0]}"
if [ -n "${LB_IP:-}" ] && [ "${#LB[@]}" -eq 1 ]; then
  PRIMARY_LB_IP="${LB_IP}"
else
  PRIMARY_LB_IP="${NETWORK_PREFIX}.${PRIMARY_LB_OCTET}"
fi

if [ -z "${DOMAIN_STORAGE}" ] || [ -z "${DOMAIN_S3}" ]; then
  echo "ERROR: DOMAIN_STORAGE and DOMAIN_S3 must be set in config.sh"
  exit 1
fi

echo "==> Installing certbot on ${PRIMARY_LB_HOSTNAME} (${PRIMARY_LB_IP})"
CERT_EXISTS="no"
if ssh_exec "${PRIMARY_LB_IP}" "test -s /etc/haproxy/certs/${DOMAIN_STORAGE}.pem"; then
  CERT_EXISTS="yes"
fi

if [ "${CERT_EXISTS}" = "no" ]; then
  ssh_exec "${PRIMARY_LB_IP}" "sudo bash -s" <<EOF
set -euo pipefail
apt-get update -y
apt-get install -y certbot python3-certbot-dns-cloudflare
install -d -m 0700 /root/.secrets
cat > /root/.secrets/cf.ini <<'CFINI'
dns_cloudflare_api_token = ${CF_TOKEN}
CFINI
chmod 600 /root/.secrets/cf.ini
install -d -m 0755 /etc/haproxy/certs
certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cf.ini \
  --dns-cloudflare-propagation-seconds 30 \
  -d ${DOMAIN_STORAGE} -d ${DOMAIN_S3} \
  --agree-tos --email ${LE_EMAIL} --non-interactive ${STAGING_FLAG}
cat /etc/letsencrypt/live/${DOMAIN_STORAGE}/fullchain.pem \
    /etc/letsencrypt/live/${DOMAIN_STORAGE}/privkey.pem \
    > /etc/haproxy/certs/${DOMAIN_STORAGE}.pem
chmod 600 /etc/haproxy/certs/${DOMAIN_STORAGE}.pem
test -s /etc/haproxy/certs/${DOMAIN_STORAGE}.pem
EOF
fi

echo "==> Certificate ready on primary LB"

# Distribute cert to other LBs if any
if [ "${#LB[@]}" -gt 1 ]; then
  echo "==> Distributing certificate to other LBs"
  cert_b64="$(ssh_exec "${PRIMARY_LB_IP}" "base64 -w0 /etc/haproxy/certs/${DOMAIN_STORAGE}.pem")"
  for i in "${!LB[@]}"; do
    if [ "$i" -eq 0 ]; then
      continue
    fi
    read -r _ LB_HOSTNAME LB_OCTET <<<"${LB[$i]}"
    LB_IP_EFFECTIVE="${NETWORK_PREFIX}.${LB_OCTET}"
    echo "==> Copying cert to ${LB_HOSTNAME} (${LB_IP_EFFECTIVE})"
    ssh_exec "${LB_IP_EFFECTIVE}" "sudo bash -s" <<EOF
set -euo pipefail
install -d -m 0755 /etc/haproxy/certs
echo '${cert_b64}' | base64 -d > /etc/haproxy/certs/${DOMAIN_STORAGE}.pem
chmod 600 /etc/haproxy/certs/${DOMAIN_STORAGE}.pem
EOF
  done
fi

echo "==> Certificate installed: /etc/haproxy/certs/${DOMAIN_STORAGE}.pem"
