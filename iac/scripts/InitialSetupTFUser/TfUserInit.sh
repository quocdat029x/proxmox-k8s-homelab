export VAULT_ADDR="https://192.168.1.254:8200"

# Retrieve credentials from Vault
username=$(vault kv get -field=username proxmox/terraform-prov)
password=$(vault kv get -field=password proxmox/terraform-prov)

# Export variables for Terraform
export TF_VAR_proxmox_username=$username
export TF_VAR_proxmox_password=$password

# Proxmox server IP or hostname
proxmox_server="192.168.1.237"  # Replace with your Proxmox server IP

# Execute commands on Proxmox via SSH
ssh root@$proxmox_server <<EOF
pveum role add TerraformProv -privs "Datastore.AllocateSpace Mapping.Use Datastore.Allocate Datastore.AllocateTemplate Datastore.Audit Pool.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"
pveum user add terraform-prov@pve --password $password
pveum aclmod / -user terraform-prov@pve -role TerraformProv
EOF
