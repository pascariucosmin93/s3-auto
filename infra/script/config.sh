#!/usr/bin/env bash
set -euo pipefail

# ===== Network =====
NETWORK_PREFIX="192.168.1.1"
CIDR="24"
GATEWAY="192.168.1.1"
DNS="1.1.1.1"

# ===== Proxmox =====
TEMPLATE_ID=1000
TEMPLATE_NAME="ubuntu-base-template"
VM_STORAGE="local-lvm"
VM_NETWORK_BRIDGE="vnet1"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-/root/.ssh/id_rsa.pub}"
CI_USER="${CI_USER:-root}"

# ===== Disks =====
OS_DISK_SIZE="32G"
VOLUME_DATA_DISK_SIZE="10G"

# ===== Seaweed version =====
WEED_VERSION="4.07"
WEED_URL="https://github.com/seaweedfs/seaweedfs/releases/download/${WEED_VERSION}/linux_amd64.tar.gz"

# ===== Seaweed ports =====
MASTER_PORT="9333"
VOLUME_PORT="8080"
FILER_PORT="8888"
S3_PORT="8333"
FILER_GRPC_PORT="18888"

# ===== Seaweed paths =====
MASTER_MDIR="/var/lib/seaweedfs/master"
VOLUME_DIR="/data/seaweedfs/volume"
FILER_DIR="/var/lib/seaweedfs/filer"

# ===== Seaweed defaults =====
MASTER_DEFAULT_REPL="010"
VOLUME_DC="dc1"

# ===== Domains  =====
DOMAIN_STORAGE=""
DOMAIN_S3=""

# NOTE: Inventory is auto-loaded from infra/terraform.tfvars via common.sh.
# Only use the static list below as a generic fallback if tfvars loading fails.
# ===== Inventory: "VMID HOSTNAME LAST_OCTET [rack]" =====
MASTERS=(
  "700 sw-master-1 10"
  "701 sw-master-2 11"
  "702 sw-master-3 12"
)

FILERS=(
  "710 sw-filer-1 20"
  "711 sw-filer-2 21"
)

VOLUMES=(
  "720 sw-volume-1 30 rack1"
  "721 sw-volume-2 31 rack2"
  "722 sw-volume-3 32 rack3"
)

POSTGRES=("730 sw-postgres-1 40")
LB=("740 sw-lb-1 50")
