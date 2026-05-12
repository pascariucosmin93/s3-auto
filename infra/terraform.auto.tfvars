pm_user = "root@pam"
pm_tls_insecure = false

target_node = "pve"
pool = "terraform"
template_vmid = 1000
template_name = "ubuntu-base-template"

storage = "local-lvm"
cloudinit_storage = "local-lvm"
bridge = "vmbr0"

cidr = 24
gateway = "10.10.1.1"
nameserver = "1.1.1.1"

ci_user = "root"
ci_password = ""
ssh_public_key_file = ""
ssh_public_keys = []

cloudflare_zone_id = ""
domain_storage = ""
domain_s3 = ""
lb_ip = ""
le_email = ""
run_certbot = false

run_post_clone_scripts = false
run_haproxy_on_lb_ip_change = false

vms = [
  {
    name           = "sw-master-1"
    vmid           = 700
    ip_address     = "10.10.1.10"
    cores          = 2
    memory         = 2048
    os_disk_size   = "32G"
    data_disk_size = ""
    role           = "master"
  },
  {
    name           = "sw-filer-1"
    vmid           = 710
    ip_address     = "10.10.1.20"
    cores          = 2
    memory         = 2048
    os_disk_size   = "32G"
    data_disk_size = ""
    role           = "filer"
  },
  {
    name           = "sw-volume-1"
    vmid           = 720
    ip_address     = "10.10.1.30"
    cores          = 4
    memory         = 4096
    os_disk_size   = "32G"
    data_disk_size = "100G"
    role           = "volume"
  },
  {
    name           = "sw-postgres-1"
    vmid           = 730
    ip_address     = "10.10.1.40"
    cores          = 2
    memory         = 4096
    os_disk_size   = "50G"
    data_disk_size = ""
    role           = "postgres"
  },
  {
    name           = "sw-lb-1"
    vmid           = 740
    ip_address     = "10.10.1.50"
    cores          = 2
    memory         = 2048
    os_disk_size   = "32G"
    data_disk_size = ""
    role           = "lb"
  }
]
