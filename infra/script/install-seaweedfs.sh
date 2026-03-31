#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/common.sh"

require_cmd ssh
require_cmd scp
require_cmd curl

TARGET_IP="${TARGET_IP:-}"
TARGET_ROLE="${TARGET_ROLE:-}"

should_target() {
  local ip="$1" role="$2"
  if [ -n "${TARGET_ROLE}" ] && [ "${TARGET_ROLE}" != "${role}" ]; then
    return 1
  fi
  if [ -n "${TARGET_IP}" ] && [ "${TARGET_IP}" != "${ip}" ]; then
    return 1
  fi
  return 0
}

MASTER_PEERS=""
for x in "${MASTERS[@]}"; do
  read -r _ _ oc <<<"$x"
  MASTER_PEERS+="$(ip_from_octet "$NETWORK_PREFIX" "$oc"):${MASTER_PORT},"
done
MASTER_PEERS="${MASTER_PEERS%,}"

HOSTS_BLOCK="$(build_hosts_block "${SCRIPT_DIR}/config.sh")"

update_hosts_remote() {
  local ip="$1"
  ssh_exec "$ip" "sudo bash -s" <<EOF2
set -e
cat > /etc/cloud/cloud.cfg.d/99-disable-etc-hosts.cfg <<'CFG'
manage_etc_hosts: false
CFG
tmp=\$(mktemp)
awk '
  BEGIN {skip=0}
  /^# seaweedfs cluster\$/ {skip=1; next}
  /^# end seaweedfs cluster\$/ {skip=0; next}
  skip==0 {print}
' /etc/hosts > "\$tmp"
cat >> "\$tmp" <<'BLOCK'
${HOSTS_BLOCK}
BLOCK
cat "\$tmp" > /etc/hosts
rm -f "\$tmp"
EOF2
}

install_weed_binary() {
  local ip="$1"
  ssh_exec "$ip" "sudo bash -s" <<EOF2
set -euo pipefail
apt-get update -y
apt-get install -y curl tar jq ca-certificates
tmp=\$(mktemp -d)
trap 'rm -rf "\$tmp"' EXIT
curl -L "${WEED_URL}" -o "\$tmp/seaweed.tar.gz"
tar -xzf "\$tmp/seaweed.tar.gz" -C "\$tmp"
install -m 0755 "\$tmp/weed" /usr/local/bin/weed
weed version || true
mkdir -p /etc/seaweedfs
EOF2
}

setup_master_service() {
  local ip="$1" hostname="$2"
  ssh_exec "$ip" "sudo bash -s" <<EOF2
set -euo pipefail
mkdir -p "${MASTER_MDIR}"
cat > /etc/systemd/system/seaweed-master.service <<UNIT
[Unit]
Description=SeaweedFS Master
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/weed master \\
  -ip=${ip} \\
  -ip.bind=${ip} \\
  -port=${MASTER_PORT} \\
  -mdir=${MASTER_MDIR} \\
  -peers=${MASTER_PEERS} \\
  -defaultReplication=${MASTER_DEFAULT_REPL}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now seaweed-master.service
systemctl --no-pager --full status seaweed-master.service | head -n 20 || true
EOF2
}

setup_volume_disk_and_service() {
  local ip="$1" hostname="$2" rack="$3"
  ssh_exec "$ip" "sudo bash -s" <<EOF2
set -euo pipefail

root_src="\$(findmnt -no SOURCE /)"
root_pk="\$(lsblk -no PKNAME "\$root_src" 2>/dev/null || true)"
if [ -z "\$root_pk" ]; then
  root_pk="\$(basename "\$root_src")"
fi
extra="\$(lsblk -dn -o NAME,TYPE | awk '\$2=="disk"{print \$1}' | grep -v -x "\$root_pk" | head -n 1)"
if [ -z "\$extra" ]; then
  disk_list="\$(lsblk -dn -o NAME,TYPE | awk '\$2=="disk"{print \$1}')"
  echo "ERROR: could not find an extra data disk. Disks: \${disk_list}"
  exit 1
fi
DEV="/dev/\${extra}"

if ! blkid "\$DEV" >/dev/null 2>&1; then
  mkfs.ext4 -F "\$DEV"
fi

mkdir -p /data
grep -q " /data " /etc/fstab || echo "\$DEV /data ext4 defaults 0 2" >> /etc/fstab
mount /data || mount -a

mkdir -p "${VOLUME_DIR}"
cat > /etc/systemd/system/seaweed-volume.service <<UNIT
[Unit]
Description=SeaweedFS Volume
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/weed volume \\
  -ip=${ip} \\
  -ip.bind=${ip} \\
  -port=${VOLUME_PORT} \\
  -dir=${VOLUME_DIR} \\
  -mserver=${MASTER_PEERS} \\
  -dataCenter=${VOLUME_DC} \\
  -rack=${rack} \\
  -max=30
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now seaweed-volume.service
systemctl --no-pager --full status seaweed-volume.service | head -n 20 || true
EOF2
}

setup_filer_and_s3_services() {
  local ip="$1" hostname="$2"
  ssh_exec "$ip" "sudo bash -s" <<EOF2
set -euo pipefail

mkdir -p "${FILER_DIR}"
mkdir -p /etc/seaweedfs

cat > /etc/systemd/system/seaweed-filer.service <<UNIT
[Unit]
Description=SeaweedFS Filer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/weed filer \\
  -ip=${ip} \\
  -ip.bind=${ip} \\
  -port=${FILER_PORT} \\
  -master=${MASTER_PEERS} \\
  -port.grpc=${FILER_GRPC_PORT}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/seaweed-s3.service <<UNIT
[Unit]
Description=SeaweedFS S3 Gateway
After=seaweed-filer.service
Wants=seaweed-filer.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/weed s3 \\
  -ip.bind=${ip} \\
  -port=${S3_PORT} \\
  -filer=${ip}:${FILER_PORT}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now seaweed-filer.service seaweed-s3.service
EOF2
}

echo "==> 1) Update /etc/hosts on all nodes"
while read -r ip; do
  wait_for_ssh "$ip" 60 5
  update_hosts_remote "$ip"
done < <(all_node_ips)

echo "==> 2) Install weed binary on all nodes"
while read -r ip; do
  if [ -n "${TARGET_IP}" ] && [ "${TARGET_IP}" != "${ip}" ]; then
    continue
  fi
  echo " - $ip"
  install_weed_binary "$ip"
done < <(all_node_ips)

echo "==> 3) Configure masters"
for x in "${MASTERS[@]}"; do
  read -r _ hn oc <<<"$x"
  ip="${NETWORK_PREFIX}.${oc}"
  should_target "$ip" "master" || continue
  setup_master_service "$ip" "$hn"
done

echo "==> 4) Configure volumes"
for x in "${VOLUMES[@]}"; do
  read -r _ hn oc rack <<<"$x"
  ip="${NETWORK_PREFIX}.${oc}"
  should_target "$ip" "volume" || continue
  setup_volume_disk_and_service "$ip" "$hn" "$rack"
done

echo "==> 5) Configure filers + s3"
for x in "${FILERS[@]}"; do
  read -r _ hn oc <<<"$x"
  ip="${NETWORK_PREFIX}.${oc}"
  should_target "$ip" "filer" || continue
  setup_filer_and_s3_services "$ip" "$hn"
done

echo "==> Done. Next: ./install-postgres.sh"
