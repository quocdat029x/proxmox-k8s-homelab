data "vault_kv_secret_v2" "secret_data" {
  mount = "/proxmox"
  name = "terraform-prov"
}

data "vault_kv_secret_v2" "infra_tfvars" {
  mount = "/proxmox"
  name = "infra-${var.environment}-tfvars"
}