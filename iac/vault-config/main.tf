###############################################################################
# Vault configuration as code.
#
# Manages the HashiCorp Vault instance that runs on the Synology NAS
# (https://192.168.1.254:8200) — the KV engine, AppRole auth + role, the
# read-secrets policy, and the secrets consumed by external-secrets.
#
# Auth: set VAULT_TOKEN env var (root, or a TF admin token — see
# scripts/InitialSetupTFUser). The Synology Vault uses a self-signed cert;
# point vault_ca_cert at a local copy (refresh via scripts/HCVault/RenewVaultCert.sh).
#
# NOTE: Kubernetes auth (auth/kubernetes) is intentionally NOT modelled here.
# Vault on the Synology cannot reach the k8s API (private Proxmox VNET), so
# TokenReview times out. ESO uses AppRole instead. If routing is ever fixed,
# add vault_auth_backend "kubernetes" + vault_kubernetes_auth_backend_* here.
###############################################################################
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "4.5.0"
    }
  }
}

provider "vault" {
  address      = var.vault_address
  ca_cert_file = var.vault_ca_cert
  # token comes from VAULT_TOKEN env var
}

# --- KV-v2 secret engine for cluster secrets ---
resource "vault_mount" "proxmox" {
  path        = "proxmox"
  type        = "kv"
  options     = { version = "2" }
  description = "Proxmox + k8s prod cluster secrets"
}

# --- Policy granting read access to proxmox/* (used by ESO AppRole) ---
resource "vault_policy" "read_secrets" {
  name   = "read-secrets"
  policy = <<-EOT
    path "proxmox/data/*" {
      capabilities = ["read"]
    }
    path "proxmox/metadata/*" {
      capabilities = ["list", "read"]
    }
  EOT
}

# --- AppRole auth (ESO authenticates with role-id/secret-id) ---
resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "AppRole auth for external-secrets (ESO)"
}

resource "vault_approle_auth_backend_role" "eso" {
  backend            = vault_auth_backend.approle.path
  role_name          = "eso"
  token_policies     = [vault_policy.read_secrets.name]
  token_ttl          = 3600
  token_max_ttl      = 7200
  secret_id_ttl      = "0"
  secret_id_num_uses = 0
}

# --- Secrets consumed by ESO (values from sensitive variables; set in terraform.tfvars) ---
# external-dns Cloudflare token
resource "vault_kv_secret_v2" "cloudflare" {
  mount     = vault_mount.proxmox.path
  name      = "cloudflare"
  data_json = jsonencode({ "api-token" = var.cloudflare_api_token })
}

# ArgoCD Azure DevOps repo credentials
resource "vault_kv_secret_v2" "argocd" {
  mount = vault_mount.proxmox.path
  name  = "argocd"
  data_json = jsonencode({
    url      = var.argocd_repo_url
    username = var.argocd_repo_username
    password = var.argocd_repo_pat
  })
}
