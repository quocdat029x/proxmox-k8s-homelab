output "secret_data" {
  value = data.vault_kv_secret_v2.secret_data
}
output "infra_data" {
  value = data.vault_kv_secret_v2.infra_tfvars
}