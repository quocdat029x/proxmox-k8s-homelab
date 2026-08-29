# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning: [SemVer](https://semver.org/).

## [0.1.0] — 2026-08-29

### Added

- Initial public release.
- OpenTofu/Terraform root modules: `iac/prod` (VMs + cluster) and
  `iac/vault-config` (Vault as code).
- 8 composable Proxmox modules: pool, vault, vm_template, vm, kubespray,
  bastion_host, user-data, vm_secret.
- Kubespray-based Kubernetes 1.32.3 provisioning via a bastion-relayed
  remote-exec deployer VM (Calico, ingress-nginx, MetalLB, ArgoCD).
- Vault-backed secret model — no credentials in git; per-VM random passwords.
- Admin tooling: `gen-ssh-config.sh`, `k8s-tunnel.sh`.
- CI (fmt/validate/shellcheck/gitleaks), pre-commit hooks, SECURITY.md,
  CONTRIBUTING.md, MIT license.
