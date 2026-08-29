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

provider "proxmox" {
  endpoint = module.secret_data.secret_data.data.endpoint
  # endpoint = data.vault_kv_secret_v2.secret_data.data.endpoint
  username = module.secret_data.secret_data.data.username
  password = module.secret_data.secret_data.data.password
  insecure = module.secret_data.secret_data.data.insecure
  tmp_dir  = "/var/tmp"

  ssh {
    username = module.secret_data.secret_data.data.master_username
    password = module.secret_data.secret_data.data.master_password
    agent = true
  }
}

provider "vault" {
  address = "https://${var.vault_server_address}:8200"
  ca_cert_file = var.ca_cert
}