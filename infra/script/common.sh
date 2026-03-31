#!/usr/bin/env bash
set -euo pipefail

here() { cd "$(dirname "${BASH_SOURCE[0]}")" && pwd; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }
}

load_inventory_from_tfvars() {
  local tf_root tfvars
  command -v python3 >/dev/null 2>&1 || return 0

  tf_root="$(cd "$(here)/.." && pwd)"
  tfvars="${TFVARS_PATH:-${TF_ROOT:-$tf_root}/terraform.tfvars}"
  [ -f "$tfvars" ] || return 0

  eval "$(python3 - "$tfvars" <<'PY'
import json,re,sys
tfvars_path=sys.argv[1]
text=open(tfvars_path,"r",encoding="utf-8").read()

def get_simple(key):
    m=re.search(r'^\s*'+re.escape(key)+r'\s*=\s*("([^"]*)"|[^\s#]+)', text, re.M)
    if not m:
        return ""
    if m.group(2) is not None:
        return m.group(2)
    return m.group(1).strip('"')

def extract_vms():
    m=re.search(r'^\s*vms\s*=\s*\[', text, re.M)
    if not m:
        return []
    i=m.end()
    depth=1
    while i < len(text) and depth > 0:
        if text[i] == '[':
            depth += 1
        elif text[i] == ']':
            depth -= 1
        i += 1
    block=text[m.end():i-1]
    items=re.findall(r'\{([^{}]*)\}', block, re.S)
    vms=[]
    for item in items:
        vm={}
        for k, v, vq in re.findall(r'(\w+)\s*=\s*("([^"]*)"|[^\s#]+)', item):
            vm[k]=vq if vq else v.strip('"')
        vms.append(vm)
    return vms

data={
    "vms": extract_vms(),
    "cidr": get_simple("cidr"),
    "gateway": get_simple("gateway"),
    "nameserver": get_simple("nameserver"),
    "domain_storage": get_simple("domain_storage"),
    "domain_s3": get_simple("domain_s3"),
    "lb_ip": get_simple("lb_ip"),
    "ci_user": get_simple("ci_user"),
}

vms=data.get("vms",[])
def ip_prefix(ip):
    parts=ip.split(".")
    return ".".join(parts[:3]) if len(parts)>=3 else ""
def last_octet(ip):
    parts=ip.split(".")
    return parts[-1] if parts else ""

out=[]
out.append("MASTERS=()")
out.append("FILERS=()")
out.append("VOLUMES=()")
out.append("POSTGRES=()")
out.append("LB=()")

vol_idx=0
for vm in vms:
    role=vm.get("role","")
    name=vm.get("name","")
    vmid=vm.get("vmid","")
    ip=vm.get("ip_address","")
    octet=last_octet(ip)
    if role=="volume":
        vol_idx += 1
        rack=f"rack{vol_idx}"
        out.append(f'VOLUMES+=("{vmid} {name} {octet} {rack}")')
    elif role=="master":
        out.append(f'MASTERS+=("{vmid} {name} {octet}")')
    elif role=="filer":
        out.append(f'FILERS+=("{vmid} {name} {octet}")')
    elif role=="postgres":
        out.append(f'POSTGRES+=("{vmid} {name} {octet}")')
    elif role=="lb":
        out.append(f'LB+=("{vmid} {name} {octet}")')

gateway=data.get("gateway","")
nameserver=data.get("nameserver","")
prefix=ip_prefix(gateway) or (ip_prefix(vms[0].get("ip_address","")) if vms else "")
if prefix:
    out.append(f'NETWORK_PREFIX="{prefix}"')
cidr=data.get("cidr","")
if cidr!="":
    out.append(f'CIDR="{cidr}"')
if gateway:
    out.append(f'GATEWAY="{gateway}"')
if nameserver:
    out.append(f'DNS="{nameserver}"')
domain_storage=data.get("domain_storage","")
if domain_storage:
    out.append(f'DOMAIN_STORAGE="{domain_storage}"')
domain_s3=data.get("domain_s3","")
if domain_s3:
    out.append(f'DOMAIN_S3="{domain_s3}"')
lb_ip=data.get("lb_ip","")
if lb_ip:
    out.append(f'LB_IP="{lb_ip}"')
ci_user=data.get("ci_user","")
if ci_user:
    out.append(f'CI_USER="{ci_user}"')

print("\n".join(out))
PY
)"
  [ -n "${MASTERS[*]:-}" ] || return 0
  INVENTORY_LOADED="1"
}

ip_from_octet() {
  local prefix="$1" octet="$2"
  echo "${prefix}.${octet}"
}

build_hosts_block() {
  local cfg="$1"
  if [ "${INVENTORY_LOADED:-}" != "1" ]; then
    # shellcheck source=/dev/null
    source "$cfg"
  fi

  {
    echo "# seaweedfs cluster"
    for x in "${MASTERS[@]}"; do read -r _ hn oc <<<"$x"; echo "$(ip_from_octet "$NETWORK_PREFIX" "$oc") $hn"; done
    for x in "${FILERS[@]}";  do read -r _ hn oc <<<"$x"; echo "$(ip_from_octet "$NETWORK_PREFIX" "$oc") $hn"; done
    for x in "${VOLUMES[@]}"; do read -r _ hn oc _rack <<<"$x"; echo "$(ip_from_octet "$NETWORK_PREFIX" "$oc") $hn"; done
  for x in "${POSTGRES[@]:-}"; do
    read -r _ hn oc <<<"$x"
    echo "$(ip_from_octet "$NETWORK_PREFIX" "$oc") $hn"
  done
  for x in "${LB[@]:-}"; do
    read -r _ hn oc <<<"$x"
    echo "$(ip_from_octet "$NETWORK_PREFIX" "$oc") $hn"
  done
    echo "# end seaweedfs cluster"
  }
}

_ssh_base_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

ssh_exec() {
  local ip="$1"; shift
  if [ -n "${CI_PASSWORD:-}" ]; then
    if ! command -v sshpass >/dev/null 2>&1; then
      echo "Missing command: sshpass (needed for password SSH). Install it or use SSH keys."
      exit 1
    fi
    sshpass -p "${CI_PASSWORD}" ssh "${_ssh_base_opts[@]}" "${CI_USER}@${ip}" "$@"
  else
    ssh "${_ssh_base_opts[@]}" "${CI_USER}@${ip}" "$@"
  fi
}

scp_to() {
  local ip="$1" src="$2" dst="$3"
  if [ -n "${CI_PASSWORD:-}" ]; then
    if ! command -v sshpass >/dev/null 2>&1; then
      echo "Missing command: sshpass (needed for password SSH). Install it or use SSH keys."
      exit 1
    fi
    sshpass -p "${CI_PASSWORD}" scp "${_ssh_base_opts[@]}" "$src" "${CI_USER}@${ip}:${dst}"
  else
    scp "${_ssh_base_opts[@]}" "$src" "${CI_USER}@${ip}:${dst}"
  fi
}

wait_for_ssh() {
  local ip="$1" tries="${2:-30}" delay="${3:-5}"
  local i=1
  while [ "$i" -le "$tries" ]; do
    if ssh_exec "$ip" "true" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
    i=$((i+1))
  done
  echo "ERROR: SSH not ready for ${ip} after $((tries*delay))s"
  return 1
}

all_node_ips() {
  if [ "${INVENTORY_LOADED:-}" != "1" ]; then
    # shellcheck source=/dev/null
    source "$(here)/config.sh"
  fi
  local ips=()
  for x in "${MASTERS[@]}"; do read -r _ _ oc <<<"$x"; ips+=("$(ip_from_octet "$NETWORK_PREFIX" "$oc")"); done
  for x in "${FILERS[@]}";  do read -r _ _ oc <<<"$x"; ips+=("$(ip_from_octet "$NETWORK_PREFIX" "$oc")"); done
  for x in "${VOLUMES[@]}"; do read -r _ _ oc _ <<<"$x"; ips+=("$(ip_from_octet "$NETWORK_PREFIX" "$oc")"); done
  for x in "${POSTGRES[@]:-}"; do
    read -r _ _ oc <<<"$x"
    ips+=("$(ip_from_octet "$NETWORK_PREFIX" "$oc")")
  done
  for x in "${LB[@]:-}"; do
    read -r _ _ oc <<<"$x"
    ips+=("$(ip_from_octet "$NETWORK_PREFIX" "$oc")")
  done
  printf "%s\n" "${ips[@]}"
}

all_vmids() {
  if [ "${INVENTORY_LOADED:-}" != "1" ]; then
    # shellcheck source=/dev/null
    source "$(here)/config.sh"
  fi
  local ids=()
  for x in "${MASTERS[@]}"; do read -r id _ _ <<<"$x"; ids+=("$id"); done
  for x in "${FILERS[@]}";  do read -r id _ _ <<<"$x"; ids+=("$id"); done
  for x in "${VOLUMES[@]}"; do read -r id _ _ _ <<<"$x"; ids+=("$id"); done
  for x in "${POSTGRES[@]:-}"; do
    read -r id _ _ <<<"$x"
    ids+=("$id")
  done
  for x in "${LB[@]:-}"; do
    read -r id _ _ <<<"$x"
    ids+=("$id")
  done
  printf "%s\n" "${ids[@]}"
}

# Best-effort override using terraform.tfvars so inventory stays in sync.
load_inventory_from_tfvars || true

# Allow CI to pass password as SSH_PASSWORD when CI_PASSWORD is not set.
: "${CI_PASSWORD:=${SSH_PASSWORD:-}}"
