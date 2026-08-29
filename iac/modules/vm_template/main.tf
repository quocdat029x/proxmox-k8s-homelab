terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.78.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "4.5.0"
    }
  }
}

data "local_file" "ssh_public_key" {
  filename = var.ssh_filename
}

# Download the Ubuntu cloud image.
# overwrite = false disables the URL size check, so the file is only
# (re)downloaded when `var.image` is explicitly changed (i.e. a manual upgrade).
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "proxmox"
  url          = var.image
  overwrite    = false
}

# Create a template VM from the cloud image
resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  name        = var.vm_name
  node_name   = "proxmox"
  description = "Contact point: ${var.owner}\nManaged by Terraform"
  tags        = ["template", var.environment]
  template    = true

  agent {
    enabled = true
    timeout = "30s"
  }

  cpu {
    cores = var.cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
    floating  = 2048
  }

  # Import the cloud image as a bootable disk
  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    size         = var.disk_size
    discard      = "on"
    iothread     = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    user_account {
      keys     = [trimspace(data.local_file.ssh_public_key.content)]
      username = "ubuntu"
      password = module.vm_secret.password
    }
    user_data_file_id = module.user-data.user-data
  }

  boot_order = ["scsi0", "net0"]

  network_device {
    bridge   = "vmbr1"
    firewall = false
  }

  pool_id = var.resource_pool

  lifecycle {
    ignore_changes = [network_device]
  }
}

output "template_id" {
  value = proxmox_virtual_environment_vm.ubuntu_vm.id
}

# Generate + persist VM password in Vault (replaces the hardcoded password).
module "vm_secret" {
  source      = "../vm_secret"
  environment = var.environment
  vm_name     = var.vm_name
}

module "user-data" {
  source       = "../user-data"
  ssh_filename = var.ssh_filename
  vm_name      = var.vm_name
}
