terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "4.5.0"
    }
  }
}

# Generate a strong, random password for the VM's default user.
# `keepers` pins the password to (environment, vm_name) so it is NOT regenerated
# on every plan — only when one of these identity attributes changes.
resource "random_password" "vm_password" {
  length           = var.password_length
  override_special = var.override_special
  special          = true
  keepers = {
    environment = var.environment
    vm_name     = var.vm_name
  }
}

# Persist the generated password into HashiCorp Vault (KV v2) so it can be
# retrieved later for SSH fallback, debugging, or rotation.
# prevent_destroy guards against accidental `terraform destroy` wiping secrets.
resource "vault_kv_secret_v2" "vm_password" {
  mount = var.vault_mount_path
  name  = "${var.vault_secret_name_prefix}${var.vm_name}-password"

  data_json = jsonencode({
    username    = var.username
    password    = random_password.vm_password.result
    vm_name     = var.vm_name
    environment = var.environment
  })

  lifecycle {
    prevent_destroy = true
  }
}
