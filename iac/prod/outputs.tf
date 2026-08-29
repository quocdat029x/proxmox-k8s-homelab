# Admin tooling outputs — consumed by scripts/admin/gen-ssh-config.sh and k8s-tunnel.sh
# via `tofu -chdir iac/prod output -json`.

output "bastion_access" {
  description = "Bastion SSH endpoint reachable from the admin network (sourced from Vault)."
  value = {
    ip   = module.secret_data.infra_data.data.bastion_ssh_ip
    port = module.secret_data.infra_data.data.bastion_ssh_port
    user = module.secret_data.infra_data.data.bastion_ssh_user
  }
  # Sourced from a Vault KV secret (sensitive). `tofu output -json` still returns
  # the real values for tooling (gen-ssh-config.sh); only the CLI plan display redacts.
  sensitive = true
}

output "control_plane_nodes" {
  description = "k8s control-plane nodes: { name, ip (internal vmbr1) }."
  value = [for h in module.vm_k8s_control_plane.vm_list : { name = h.name, ip = h.ip }]
}

output "worker_nodes" {
  description = "k8s worker nodes: { name, ip (internal vmbr1) }."
  value = [for h in module.vm_k8s_worker.vm_list : { name = h.name, ip = h.ip }]
}

output "kubespray_node" {
  description = "kubespray deployment host: { name, ip (internal vmbr1) }."
  value = [for h in module.vm_k8s_kubespray.vm_list : { name = h.name, ip = try(h.ip[1][0], "") }]
}
