resource "proxmox_vm_qemu" "vms" {
  for_each           = { for vm in local.vms : tostring(vm.vmid) => vm }
  name               = each.value.name
  target_node        = var.target_node
  pool               = var.pool
  vmid               = each.value.vmid
  clone              = var.template_name != "" ? var.template_name : tostring(var.template_vmid)
  full_clone         = var.full_clone
  start_at_node_boot = var.onboot

  cpu {
    cores = each.value.cores
  }
  memory   = each.value.memory
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"
  os_type  = "cloud-init"

  serial {
    id   = 0
    type = "socket"
  }

  vga {
    type = "serial0"
  }

  disk {
    slot    = "scsi0"
    type    = "disk"
    size    = each.value.os_disk_size
    storage = var.storage
  }

  dynamic "disk" {
    for_each = (each.value.role == "volume" || each.value.data_disk_size != "") ? [1] : []
    content {
      slot    = "scsi1"
      type    = "disk"
      size    = each.value.data_disk_size != "" ? each.value.data_disk_size : var.data_disk_size
      storage = var.storage
    }
  }

  disk {
    slot    = "ide2"
    type    = "cloudinit"
    storage = var.cloudinit_storage
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = var.bridge
  }
  ciuser     = var.ci_user
  cipassword = var.ci_password
  sshkeys    = length(var.ssh_public_keys) > 0 ? join("\n", var.ssh_public_keys) : file(var.ssh_public_key_file)
  cicustom   = var.ci_user_snippet != "" ? "user=${var.ci_user_snippet}" : null
  nameserver = var.nameserver
  ipconfig0  = "ip=${each.value.ip_address}/${var.cidr},gw=${var.gateway}"

  lifecycle {
    ignore_changes = [
      agent,
      disk,
      ciuser,
      cipassword,
      sshkeys,
      cicustom,
      ipconfig0,
      startup_shutdown,
    ]
  }
}
