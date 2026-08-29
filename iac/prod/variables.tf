### COMMON 
variable "prefix" {
  type = string
}
variable "project" {
  type = string
}
variable "environment" {
  type = string
}
variable "region" {
  type = string
}
variable "region_code" {
  type = string
}
variable "responsible_party" {
  type = string
}
variable "owner" {
  type = string
}
variable "ssh_public_key_path" {
  description = "Path to the SSH public key injected into all VMs (relative to iac/prod). Never commit the private key."
  type        = string
  default     = "./ssh/id_ed25519.pub"
}
variable "vault_provider_version" {
  type = string
}
variable "proxmox_provider_version" {
  type = string
}
variable "root_domain_name" {
  type = string
  sensitive = true
}
variable "ca_cert" {
  description = "Path to the CA certificate"
  type        = string
  sensitive = true
}
variable "vault_server_address" {
  description = "vaul server address"
  type        = string
  sensitive = true
}
variable "virtual_environment_endpoint" {
  description = "virtual_environment_endpoint"
  type        = string
  sensitive = true
}
variable "cpu_cores" {
  type = string
  default = "1"
}
variable "disk_size" {
  type = string
  default = "20"
}
# variable "internal_net_subnet_cidr" {
#   type = string
# }