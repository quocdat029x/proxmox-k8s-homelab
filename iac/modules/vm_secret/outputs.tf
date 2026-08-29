output "password" {
  value       = random_password.vm_password.result
  sensitive   = true
  description = "Generated VM password (sensitive). Consumed by the VM user_account and stored in Vault."
}

output "username" {
  value       = var.username
  description = "OS username paired with the password."
}

output "vault_path" {
  value       = "${vault_kv_secret_v2.vm_password.mount}/${vault_kv_secret_v2.vm_password.name}"
  description = "Full Vault KV v2 path where the credential is stored."
}
