pm_user = "root@pam"
pm_tls_insecure = false

target_node = "pve"
pool = "terraform"
template_vmid = 102
template_name = "ubuntu-2404-template"

storage = "local-lvm"
cloudinit_storage = "local-lvm"
bridge = "vmbr0"

cidr = 24
gateway = "191.168.1.1"
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
    name           = "node-a1"
    vmid           = 700
    ip_address     = "191.168.1.21"
    cores          = 2
    memory         = 2048
    os_disk_size   = "32G"
    data_disk_size = ""
    role           = "master"
  },
  {
    name           = "node-b2"
    vmid           = 710
    ip_address     = "191.168.1.22"
    cores          = 2
    memory         = 2048
    os_disk_size   = "32G"
    data_disk_size = ""
    role           = "filer"
  },
  {
    name           = "node-c3"
    vmid           = 720
    ip_address     = "191.168.1.23"
    cores          = 4
    memory         = 4096
    os_disk_size   = "32G"
    data_disk_size = "100G"
    role           = "volume"
  },
  {
    name           = "node-d4"
    vmid           = 730
    ip_address     = "191.168.1.24"
    cores          = 2
    memory         = 4096
    os_disk_size   = "50G"
    data_disk_size = ""
    role           = "postgres"
  },
  {
    name           = "node-e5"
    vmid           = 740
    ip_address     = "191.168.1.25"
    cores          = 2
    memory         = 2048
    os_disk_size   = "32G"
    data_disk_size = ""
    role           = "lb"
  },
  {
    name           = "node-f6"
    vmid           = 750
    ip_address     = "191.168.1.26"
    cores          = 2
    memory         = 2048
    os_disk_size   = "32G"
    data_disk_size = ""
    role           = "master"
  },
  {
    name           = "node-g7"
    vmid           = 760
    ip_address     = "191.168.1.27"
    cores          = 2
    memory         = 2048
    os_disk_size   = "32G"
    data_disk_size = ""
    role           = "filer"
  },
  {
    name           = "node-h8"
    vmid           = 770
    ip_address     = "191.168.1.28"
    cores          = 2
    memory         = 2048
    os_disk_size   = "32G"
    data_disk_size = "100G"
    role           = "volume"
  }
]
