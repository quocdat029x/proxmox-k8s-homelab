output "k8s_pool" {
  value = proxmox_virtual_environment_pool.k8s.pool_id
}
output "standalone_pool" {
  value = proxmox_virtual_environment_pool.standalone.pool_id
}