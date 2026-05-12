variable "pm_api_url" {
  type        = string
  description = "Proxmox API URL, e.g. https://proxmox.cosmin-lab.cloud/api2/json or https://proxmox.example.internal:8006/api2/json"
}

variable "pm_user" {
  type        = string
  description = "Proxmox user (ignored if using API token only)"
  default     = "root@pam"
}

variable "pm_password" {
  type        = string
  description = "Proxmox password (leave empty if using API token)"
  default     = ""
  sensitive   = true
  validation {
    condition = (
      length(var.pm_password) > 0 ||
      (length(var.pm_api_token_id) > 0 && length(var.pm_api_token_secret) > 0)
    )
    error_message = "Set pm_password or both pm_api_token_id and pm_api_token_secret."
  }
}

variable "pm_api_token_id" {
  type        = string
  description = "Proxmox API token ID (user!token)"
  default     = ""
}

variable "pm_api_token_secret" {
  type        = string
  description = "Proxmox API token secret"
  default     = ""
  sensitive   = true
}

variable "pm_tls_insecure" {
  type        = bool
  description = "Skip TLS verification for the Proxmox API"
  default     = true
}

variable "target_node" {
  type        = string
  description = "Proxmox node to place the VM on"
  default     = "pve9"
}

variable "pool" {
  type        = string
  description = "Proxmox pool for the VMs"
  default     = ""
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token with DNS edit permissions"
  default     = ""
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone ID for the target domain"
  default     = ""
}

variable "domain_storage" {
  type        = string
  description = "Domain for filer UI"
  default     = ""
}

variable "domain_s3" {
  type        = string
  description = "Domain for S3 endpoint"
  default     = ""
}

variable "lb_ip" {
  type        = string
  description = "HAProxy public IP for DNS records"
  default     = "198.51.100.10"
}

variable "le_email" {
  type        = string
  description = "Email for Let's Encrypt registration"
  default     = "ops@example.com"
}

variable "run_certbot" {
  type        = bool
  description = "Run certbot before configuring HAProxy"
  default     = false
}

variable "template_vmid" {
  type        = number
  description = "Template VMID to clone"
  default     = 3002
}

variable "template_name" {
  type        = string
  description = "Template name to clone (takes precedence over template_vmid when set)"
  default     = ""
}

variable "vm_name" {
  type        = string
  description = "Name for the new VM"
}

variable "vmid" {
  type        = number
  description = "Optional VMID for the new VM"
  default     = null
}

variable "vms" {
  type = list(object({
    name           = string
    vmid           = number
    ip_address     = string
    cores          = number
    memory         = number
    os_disk_size   = string
    data_disk_size = string
    role           = string
  }))
  description = "List of VMs to create (name/vmid/ip/cores/memory/disk sizes)"
  default     = []
}

variable "cores" {
  type        = number
  description = "CPU cores"
  default     = 2
}

variable "memory" {
  type        = number
  description = "Memory in MB"
  default     = 2048
}

variable "disk_size" {
  type        = string
  description = "Disk size for the cloned VM"
  default     = "32G"
}

variable "data_disk_size" {
  type        = string
  description = "Optional extra data disk size for the cloned VM"
  default     = ""
}

variable "storage" {
  type        = string
  description = "Storage for the VM disk"
  default     = "local-lvm"
}

variable "cloudinit_storage" {
  type        = string
  description = "Storage for the cloud-init drive"
  default     = "local-lvm"
}

variable "bridge" {
  type        = string
  description = "Network bridge"
  default     = "vmbr0"
}

variable "ip_address" {
  type        = string
  description = "Static IP address for the VM"
}

variable "cidr" {
  type        = number
  description = "CIDR mask"
  default     = 24
}

variable "gateway" {
  type        = string
  description = "Default gateway"
  default     = "192.168.1.1"
}

variable "nameserver" {
  type        = string
  description = "DNS nameserver"
  default     = "8.8.8.8"
}

variable "ci_user" {
  type        = string
  description = "Cloud-init username"
  default     = "root"
}

variable "ci_password" {
  type        = string
  description = "Cloud-init password"
  default     = ""
  sensitive   = true
}

variable "ssh_public_key_file" {
  type        = string
  description = "Path to SSH public key file"
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "List of SSH public keys to inject via cloud-init (preferred over ssh_public_key_file)"
  default     = []
}

variable "full_clone" {
  type        = bool
  description = "Create a full clone (not linked)"
  default     = true
}

variable "onboot" {
  type        = bool
  description = "Start VM on boot"
  default     = true
}

variable "post_clone_delay_seconds" {
  type        = number
  description = "Delay before running post-clone shell scripts"
  default     = 60
}

variable "run_post_clone_scripts" {
  type        = bool
  description = "Run repo shell scripts after VM creation"
  default     = true
}

variable "post_clone_trigger" {
  type        = string
  description = "Manual trigger for post-clone null_resources; bump to force re-run"
  default     = "v1"
}

variable "run_haproxy_on_lb_ip_change" {
  type        = bool
  description = "Re-run HAProxy install script when lb_ip changes"
  default     = true
}

variable "ci_user_snippet" {
  type        = string
  description = "Cloud-init user-data snippet (e.g. local:snippets/ssh-password.yml)"
  default     = ""
}
