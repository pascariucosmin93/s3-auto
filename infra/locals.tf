locals {
  vms = length(var.vms) > 0 ? var.vms : [
    {
      name           = var.vm_name
      vmid           = var.vmid
      ip_address     = var.ip_address
      cores          = var.cores
      memory         = var.memory
      os_disk_size   = var.disk_size
      data_disk_size = var.data_disk_size
      role           = "single"
    }
  ]
}
