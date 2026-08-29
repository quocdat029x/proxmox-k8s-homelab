#!/usr/bin/env bash
# One-time bootstrap of a least-privilege Proxmox user for Terraform/OpenTofu.
#
# Credentials come from Vault (proxmox/terraform-prov). The password is sent
# to the Proxmox node over stdin — never as part of the ssh command line,
# where it would be visible in the local process list.
set -euo pipefail

export VAULT_ADDR="https://192.168.1.254:8200"   # your Vault server

# Retrieve credentials from Vault
username=$(vault kv get -field=username proxmox/terraform-prov)
password=$(vault kv get -field=password proxmox/terraform-prov)

# Export variables for Terraform/OpenTofu
export TF_VAR_proxmox_username="$username"
export TF_VAR_proxmox_password="$password"

# Proxmox server IP or hostname
proxmox_server="192.168.1.237"   # replace with your Proxmox host

# Execute commands on Proxmox via SSH; password travels over stdin only.
printf '%s\n' "$password" | ssh root@"$proxmox_server" \
  'read -rs pw
pveum role add TerraformProv -privs "Datastore.AllocateSpace Mapping.Use Datastore.Allocate Datastore.AllocateTemplate Datastore.Audit Pool.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"
pveum user add terraform-prov@pve --password "$pw"
pveum aclmod / -user terraform-prov@pve -role TerraformProv'
