# Security Policy

## Design rules this repo follows

1. **No secrets in git.** Credentials live in HashiCorp Vault and are read at
   `plan` time. `.gitignore` rejects `*.tfstate*`, `*.tfvars` (except
   `*.tfvars.example`), `*.pem`, private SSH keys, and `.terraform/`.
2. **Least privilege.** Terraform talks to Proxmox as `terraform-prov@pve`
   with a scoped role (see `iac/scripts/InitialSetupTFUser/`).
3. **Network isolation.** The Kubernetes VNET is unrouted; the bastion is the
   only dual-homed host and proxies HTTP only.

## Before you open an issue

Do **not** open a public issue containing secrets, tokens, internal hostnames
of a live deployment, or anything you wouldn't paste on a billboard. Mask
values; use `<redacted>` placeholders.

## Reporting a vulnerability

If you believe you found a security-relevant bug in this repo:

1. Prefer a **private vulnerability report** via GitHub
   (Security → Report a vulnerability).
2. If unavailable, email the repo owner (address in the commit history / profile).

Please include: affected file(s), a minimal reproduction, and impact. You will
hear back within a few days. Please do not publicly disclose untriaged issues.

## Deployment hardening notes

Running this stack yourself? At minimum:

- Put Vault behind TLS with a cert you rotate (`iac/scripts/HCVault/RenewVaultCert.sh`).
- Restrict Proxmox API + SSH to your management network.
- Keep `ip_forward=0` on the bastion; only Caddy bridges the networks.
- Review the k8s exposure chain before pointing a public domain at it:
  `docs/expose-architecture.md`.
