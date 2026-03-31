#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/common.sh"

TARGET_PG_IP="${TARGET_PG_IP:-}"
TARGET_PG_HOSTNAME="${TARGET_PG_HOSTNAME:-}"
if [ -n "${TARGET_PG_IP}" ]; then
  PG_IP="${TARGET_PG_IP}"
  if [ -n "${TARGET_PG_HOSTNAME}" ]; then
    PG_HOSTNAME="${TARGET_PG_HOSTNAME}"
  else
    PG_HOSTNAME="${TARGET_PG_IP}"
  fi
else
  read -r _ PG_HOSTNAME PG_OCTET <<<"${POSTGRES[0]}"
  PG_IP="${NETWORK_PREFIX}.${PG_OCTET}"
fi

DB_USER="seaweedfs"
DB_PASS="ChangeMe_StrongPass!"
DB_NAME="seaweedfs_filer"
NETWORK_CIDR="${NETWORK_PREFIX}.0/${CIDR}"

echo "==> Installing PostgreSQL on ${PG_HOSTNAME} (${PG_IP})"
ssh_exec "${PG_IP}" "sudo bash -s" <<EOF2
set -euo pipefail
apt-get update -y
apt-get install -y postgresql postgresql-contrib
systemctl enable --now postgresql
EOF2

echo "==> Configuring PostgreSQL listen + pg_hba"
ssh_exec "${PG_IP}" "sudo bash -s" <<'EOF2'
set -euo pipefail
PG_CONF="$(ls -1 /etc/postgresql/*/main/postgresql.conf | head -n1)"
HBA_CONF="$(ls -1 /etc/postgresql/*/main/pg_hba.conf | head -n1)"

sed -i "s/^#listen_addresses =.*/listen_addresses = '*'/" "$PG_CONF" || true
grep -q "${NETWORK_CIDR}" "$HBA_CONF" || echo "host all all ${NETWORK_CIDR} md5" >> "$HBA_CONF"
systemctl restart postgresql
EOF2

echo "==> Creating DB user/db"
ssh_exec "${PG_IP}" "sudo -u postgres psql -v ON_ERROR_STOP=1 -c \"CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';\" || true"
ssh_exec "${PG_IP}" "sudo -u postgres psql -v ON_ERROR_STOP=1 -c \"CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};\" || true"

echo "==> Writing filer.toml on each filer and restarting filer"
for x in "${FILERS[@]}"; do
  read -r _ hn oc <<<"$x"
  ip="${NETWORK_PREFIX}.${oc}"
  ssh_exec "$ip" "sudo bash -s" <<EOF2
set -euo pipefail
echo "${PG_IP} ${PG_HOSTNAME}" | tee -a /etc/hosts >/dev/null
cat > /etc/seaweedfs/filer.toml <<'TOML'
[postgres2]
enabled = true
createTable = """
  CREATE TABLE IF NOT EXISTS "%s" (
    dirhash   BIGINT,
    name      VARCHAR(65535),
    directory VARCHAR(65535),
    meta      bytea,
    PRIMARY KEY (dirhash, name)
  );
"""
hostname = "REPLACE_HOSTNAME"
port = 5432
username = "REPLACE_USER"
password = "REPLACE_PASS"
database = "REPLACE_DB"
schema = "public"
sslmode = "disable"
connection_max_idle = 10
connection_max_open = 50
connection_max_lifetime_seconds = 300
pgbouncer_compatible = false
enableUpsert = true
upsertQuery = """
  INSERT INTO "%[1]s" (dirhash, name, directory, meta)
    VALUES(\$1, \$2, \$3, \$4)
    ON CONFLICT (dirhash, name) DO UPDATE SET
      directory=EXCLUDED.directory,
      meta=EXCLUDED.meta
"""
TOML

sed -i \
  -e "s/REPLACE_HOSTNAME/${PG_HOSTNAME}/" \
  -e "s/REPLACE_USER/${DB_USER}/" \
  -e "s/REPLACE_PASS/${DB_PASS}/" \
  -e "s/REPLACE_DB/${DB_NAME}/" \
  /etc/seaweedfs/filer.toml

systemctl restart seaweed-filer.service
systemctl --no-pager --full status seaweed-filer.service | head -n 20 || true
EOF2
done

echo "==> Done"
