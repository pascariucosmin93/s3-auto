resource "null_resource" "post_clone_scripts" {
  for_each   = var.run_post_clone_scripts ? { for vm in var.vms : vm.name => vm } : {}
  depends_on = [proxmox_vm_qemu.vms]
  triggers = {
    manual = var.post_clone_trigger
    vmid   = each.value.vmid
    role   = each.value.role
    ip     = each.value.ip_address
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOF
      cd ${path.root}/..
      export CI_USER='${var.ci_user}'
      export CI_PASSWORD='${var.ci_password}'
      export SSH_PASSWORD='${var.ci_password}'
      export TARGET_IP='${each.value.ip_address}'
      export TARGET_ROLE='${each.value.role}'
      source ./infra/script/common.sh
      while read -r ip; do
        ssh-keygen -f "/root/.ssh/known_hosts" -R "$ip" >/dev/null 2>&1 || true
      done < <(all_node_ips)
      sleep ${var.post_clone_delay_seconds}
      if [ "${each.value.role}" = "master" ] || [ "${each.value.role}" = "filer" ] || [ "${each.value.role}" = "volume" ]; then
        bash ./infra/script/install-seaweedfs.sh
      fi
      if [ "${each.value.role}" = "postgres" ]; then
        export TARGET_PG_IP='${each.value.ip_address}'
        export TARGET_PG_HOSTNAME='${each.value.name}'
        bash ./infra/script/install-postgres.sh
      fi
      if [ "${each.value.role}" = "lb" ]; then
        export TARGET_LB_IP='${each.value.ip_address}'
        bash ./infra/script/install-haproxy.sh
      fi
    EOF
  }
}

resource "null_resource" "post_clone_certbot" {
  count      = var.run_post_clone_scripts && var.run_certbot ? 1 : 0
  depends_on = [null_resource.post_clone_scripts]
  triggers = {
    manual   = var.post_clone_trigger
    vms_hash = sha1(jsonencode(var.vms))
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOF
      cd ${path.root}/..
      export CI_USER='${var.ci_user}'
      export CI_PASSWORD='${var.ci_password}'
      export SSH_PASSWORD='${var.ci_password}'
      export CF_TOKEN='${var.cloudflare_api_token}'
      export LE_EMAIL='${var.le_email}'
      bash ./infra/script/install-certbot.sh
      bash ./infra/script/install-haproxy.sh
    EOF
  }
}

resource "null_resource" "haproxy_on_lb_ip_change" {
  count      = var.run_post_clone_scripts && var.run_haproxy_on_lb_ip_change ? 1 : 0
  depends_on = [proxmox_vm_qemu.vms]
  triggers = {
    lb_ip    = var.lb_ip
    vms_hash = sha1(jsonencode(var.vms))
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOF
      cd ${path.root}/..
      export CI_USER='${var.ci_user}'
      export CI_PASSWORD='${var.ci_password}'
      export SSH_PASSWORD='${var.ci_password}'
      bash ./infra/script/install-haproxy.sh
    EOF
  }
}
