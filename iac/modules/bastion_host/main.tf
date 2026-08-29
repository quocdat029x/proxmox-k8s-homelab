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

data "local_file" "ssh_public_key" {
  filename = var.ssh_filename
}

resource "null_resource" "wait_for_ip" {
  provisioner "local-exec" {
    command = "sleep 30"  # Increase if needed
  }

  depends_on = [proxmox_virtual_environment_vm.ubuntu_vm]
}

resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  name = "${var.vm_name}-${format("%02d", count.index)}"
  count = var.node_count
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
    # hotplugged = 1
  }

  clone {
    vm_id = var.template_id
    datastore_id = "local-lvm"
  }
  initialization {
    ip_config {
      ipv4 {
        # Generate the IP address with subnet mask
        address = "${cidrhost(var.vm_net_subnet_cidr, var.vm_host_number + count.index + var.vm_host_offset)}${local.vm_net_subnet_mask}"

        # Assign the gateway (only specified here, not in the address)
        gateway = local.vm_net_default_gw
      }
    }

    ip_config {
      ipv4 {
        # Generate the IP address with subnet mask
        address = "${cidrhost(var.vm_net_subnet_cidr_second, var.vm_host_number + count.index + var.vm_host_offset)}${local.vm_net_subnet_mask_second}"

        # Assign the gateway (only specified here, not in the address)
        gateway = local.vm_net_default_gw_second

      }
    }

    user_account {
      keys     = [trimspace(data.local_file.ssh_public_key.content)]
      username = "ubuntu"
      password = module.vm_secret.password
    }

    # Reference the user-data module
    user_data_file_id = module.user-data.user-data
  }
  lifecycle {
    ignore_changes = [
      initialization,
      # Remove these lines:
      # ipv4_addresses,
      # ipv6_addresses,
      # network_interface_names,
      network_device
    ]
  }
  pool_id = var.resource_pool

  network_device {
    bridge = "vmbr0"
  }
  network_device {
    bridge = "vmbr1"
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