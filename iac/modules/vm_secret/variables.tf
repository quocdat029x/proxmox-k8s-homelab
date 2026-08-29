variable "environment" {
  type        = string
  description = "Environment name (e.g. prod, dev). Used as a password keeper and in the Vault path."
}

variable "vm_name" {
  type        = string
  description = "Logical VM name (e.g. control-plane, k8s-worker). Used as a password keeper and in the Vault path."
}

variable "username" {
  type        = string
  default     = "ubuntu"
  description = "OS user the password belongs to."
}

variable "password_length" {
  type        = number
  default     = 32
  description = "Length of the generated password."
}

variable "override_special" {
  type        = string
  default     = "_%@"
  description = "Allowed special characters in the generated password."
}

variable "vault_mount_path" {
  type        = string
  default     = "/proxmox"
  description = "Vault KV v2 mount path where the secret is written (must match the data source in modules/vault)."
}

variable "vault_secret_name_prefix" {
  type        = string
  default     = "vm-"
  description = "Prefix prepended to the Vault secret name (e.g. 'vm-' -> 'vm-control-plane-password')."
}
