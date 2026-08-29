output "vm_ipv4_address" {
  # value = proxmox_virtual_environment_vm.ubuntu_vm[count.index].ipv4_addresses
  value = [for vm in proxmox_virtual_environment_vm.ubuntu_vm : vm.ipv4_addresses]
}
output "vm_list" {
  description = "A list of maps, each containing VM details"
  value = [
    for vm in proxmox_virtual_environment_vm.ubuntu_vm : {
      name = vm.name
      id   = vm.id
      ip   = try(vm.ipv4_addresses[1][0], "")
    }
  ]
}
