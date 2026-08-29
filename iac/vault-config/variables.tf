# Vault connection
variable "vault_address" {
  type        = string
  default     = "https://192.168.1.254:8200"
  description = "Vault server address (Synology NAS)."
}

variable "vault_ca_cert" {
  type        = string
  default     = "../scripts/HCVault/volume2/Data/vault/file/vault-cert.pem"
  description = "Path to Vault CA cert PEM (self-signed Synology cert). Same as prod; refresh via scripts/HCVault/RenewVaultCert.sh."
}

# Secret values (sensitive — set in terraform.tfvars, which is gitignored)
variable "cloudflare_api_token" {
  type      = string
  sensitive = true
  description = "Cloudflare API token (Zone.Zone:Read, Zone.DNS:Edit) for external-dns. Stored at proxmox/cloudflare."
}

variable "argocd_repo_url" {
  type    = string
  default = "https://git.example.com/your-org/your-gitops-repo"
}

variable "argocd_repo_username" {
  type    = string
  default = "your-user"
}

variable "argocd_repo_pat" {
  type      = string
  sensitive = true
  description = "Azure DevOps PAT (Code:Read) for the InfrastructureGitOps repo. Stored at proxmox/argocd."
}
