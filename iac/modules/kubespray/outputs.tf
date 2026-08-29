output "vm_ipv4_address" {
  # value = proxmox_virtual_environment_vm.ubuntu_vm[count.index].ipv4_addresses
  value      = [for vm in proxmox_virtual_environment_vm.ubuntu_vm : vm.ipv4_addresses]
  depends_on = [proxmox_virtual_environment_vm.ubuntu_vm, null_resource.wait_for_ip]
}
output "vm_list" {
  value = [
    for host in proxmox_virtual_environment_vm.ubuntu_vm : {
      name   = host.name
      ip     = host.ipv4_addresses != null && length(host.ipv4_addresses) > 0 ? host.ipv4_addresses : []
      memory = host.memory
      vcpus  = host.cpu
    }
  ]
  depends_on = [proxmox_virtual_environment_vm.ubuntu_vm, null_resource.wait_for_ip]
}