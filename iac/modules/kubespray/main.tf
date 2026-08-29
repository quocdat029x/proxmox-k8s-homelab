terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.78.0"
    }
    vault = {
      source = "hashicorp/vault"
      version = "4.5.0"
    }
  }
}

locals {
  kubespray_data_dir = "$HOME/kubespray_data"
  expose_services_dir = "$HOME/expose_services"
  cluster_name = var.location != null ? "k8s-${var.env_name}-${var.location}-${var.cluster_number}" : "k8s-${var.env_name}-${var.cluster_number}"
  cluster_fqdn = "${local.cluster_name}.${var.cluster_domain}"
  setup_kubespray_script_content = templatefile(
    "${path.module}/scripts/setup_kubespray.sh",
    {
      kubespray_data_dir = local.kubespray_data_dir,
      expose_services_dir = local.expose_services_dir,
    }
  )

  install_kubernetes_script_content = templatefile(
    "${path.module}/scripts/install_kubernetes.sh",
    {
      kubespray_data_dir = local.kubespray_data_dir,
      kubespray_image    = var.kubespray_image
    }
  )

  save_argocd_password_script_content = templatefile(
    "${path.module}/scripts/save_argocd_password.sh",
    {
      kubespray_data_dir = local.kubespray_data_dir,
      control_plane_ip = var.control_plane_ip,
      vault_addr    = var.vault_addr
      vault_token    = var.vault_token
      secret_path = var.vault_secret_path
    }
  )

  setup_caddy_script_content = templatefile(
    "${path.module}/scripts/expose_service.sh",
    {
      expose_services_dir = local.expose_services_dir,
      kubespray_image     = var.kubespray_image
    }
  )

  kubespray_inventory_content = templatefile(
    "${path.module}/ansible/inventory.ini",
    {
      cp_nodes     = join("\n", [for host in var.control_plane_vm_list : "${host.name} ansible_ssh_host=${host.ip} ansible_connection=ssh"])
      worker_nodes = join("\n", [for host in var.worker_vm_list : "${host.name} ansible_ssh_host=${host.ip} ansible_connection=ssh"])
      bastion      = module.secret_data.infra_data.data.bastion_ssh_ip != "" ? "[bastion]\nbastion-host-00 ansible_host=${module.secret_data.infra_data.data.bastion_ssh_ip} ansible_port=${module.secret_data.infra_data.data.bastion_ssh_port} ansible_user=${module.secret_data.infra_data.data.bastion_ssh_user}" : ""
    }
  )

  kubespray_k8s_config_content = templatefile(
    "${path.module}/ansible/k8s-cluster.yaml",
    {
      kube_version               = var.kube_version
      kube_network_plugin        = var.kube_network_plugin
      cluster_name               = local.cluster_fqdn
      enable_nodelocaldns        = var.enable_nodelocaldns
      podsecuritypolicy_enabled  = var.podsecuritypolicy_enabled
      persistent_volumes_enabled = var.persistent_volumes_enabled
    }
  )

  kubespray_addon_config_content = templatefile(
    "${path.module}/ansible/addons.yaml",
    {
      helm_enabled          = var.helm_enabled
      ingress_nginx_enabled = var.ingress_nginx_enabled
      argocd_enabled        = var.argocd_enabled
      argocd_version        = var.argocd_version
    }
  )

  expose_service_config_content = templatefile(
    "${path.module}/ansible/expose_service.yaml",
    {
      expose_services_dir = local.expose_services_dir,
      kubespray_image    = var.kubespray_image
    }
  )

}

data "local_file" "ssh_public_key" {
  filename = var.ssh_filename
}


resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  name = "${var.vm_name}-${format("%02d", count.index)}"
  count = var.create_kubespray_host ? 1 : 0
  stop_on_destroy = true
  node_name = "proxmox"
  description = "Contact point: ${var.owner}\nManaged by Terraform"
  tags = [var.environment]
  template = var.template
  agent {
    enabled = true
    timeout = "30s"
  }
  cpu {
    cores        = var.cpu_cores
    type         = "x86-64-v2-AES"  # recommended for modern CPUs
  }
  memory {
    dedicated = 2048
    floating = 2048
  }
  clone {
    vm_id = var.template_id
  }
  initialization {
    ip_config {
      ipv4 {
        address = "${cidrhost(var.vm_net_subnet_cidr, var.vm_host_number + count.index + var.vm_host_offset)}${local.vm_net_subnet_mask}"
        gateway = local.vm_net_default_gw
      }
    }
    user_account {
      keys     = [trimspace(data.local_file.ssh_public_key.content)]
      username = "ubuntu"
      password = module.vm_secret.password
    }
    user_data_file_id = module.user-data.user-data
  }
  lifecycle {
    ignore_changes = [
      initialization,
    ]
  }
  pool_id = var.resource_pool

  network_device {
    bridge = "vmbr1"
    firewall = false
  }
}

# Generate + persist VM password in Vault (replaces the hardcoded password).
module "vm_secret" {
  source      = "../vm_secret"
  environment = var.environment
  vm_name     = var.vm_name
}

module "user-data" {
  source = "../user-data"
  ssh_filename = var.ssh_filename
  vm_name = var.vm_name
}

resource "null_resource" "wait_for_ip" {
  provisioner "local-exec" {
    command = "sleep 30"
  }
  depends_on = [proxmox_virtual_environment_vm.ubuntu_vm]
}

# Main setup resource - runs all scripts
resource "null_resource" "setup_kubespray" {
  count = var.create_kubespray_host ? 1 : 0

  provisioner "remote-exec" {
    inline = [
      local.setup_kubespray_script_content,
      "echo \"${var.ssh_private_key}\" | base64 -d > ${local.kubespray_data_dir}/id_rsa",
      "cat <<EOF > ${local.kubespray_data_dir}/inventory.ini\n${local.kubespray_inventory_content}\nEOF",
      "cat <<EOF > ${local.kubespray_data_dir}/k8s-cluster.yml\n${local.kubespray_k8s_config_content}\nEOF",
      "cat <<EOF > ${local.kubespray_data_dir}/addons.yml\n${local.kubespray_addon_config_content}\nEOF",
      "echo \"${var.ssh_private_key}\" | base64 -d > ${local.expose_services_dir}/id_rsa",
      "cat <<EOF > ${local.expose_services_dir}/inventory.ini\n${local.kubespray_inventory_content}\nEOF",
      "cat <<EOF > ${local.expose_services_dir}/expose_service.yaml\n${local.expose_service_config_content}\nEOF",
      "chmod 600 ${local.kubespray_data_dir}/*",
      "chmod 600 ${local.expose_services_dir}/*",
      local.install_kubernetes_script_content,
      local.save_argocd_password_script_content,
      local.setup_caddy_script_content
    ]
  }

  connection {
    type         = "ssh"
    user         = module.secret_data.infra_data.data.ssh_username
    private_key  = base64decode(var.ssh_private_key)
    host = "${cidrhost(var.vm_net_subnet_cidr, var.vm_host_number + count.index + var.vm_host_offset)}"
    port = 22
    bastion_host = module.secret_data.infra_data.data.bastion_ssh_ip
    bastion_user = module.secret_data.infra_data.data.bastion_ssh_user
    bastion_port = module.secret_data.infra_data.data.bastion_ssh_port
    timeout = "45m"
  }

  depends_on = [
    proxmox_virtual_environment_vm.ubuntu_vm,
    null_resource.wait_for_ip
  ]
}

module "secret_data" {
  source = "../vault"
  environment = var.environment
}
