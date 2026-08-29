terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.78.0"
    }
    vault = {
      source = "hashicorp/vault"
      version = "4.5.0"
    }
  }
}

data "local_file" "ssh_public_key" {
  filename = var.ssh_filename
}

resource "proxmox_virtual_environment_file" "hook_script" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "proxmox"
  # Hook scripts must be executable, otherwise the Proxmox VE API will reject the configuration for the VM/CT.
  file_mode    = "0700"
  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: ${var.vm_name}
    users:
      - default
      - name: ubuntu
        groups:
          - sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(data.local_file.ssh_public_key.content)}
        sudo: ALL=(ALL) NOPASSWD:ALL
    runcmd:
        - echo \"SUBSYSTEM==\\\"cpu\\\", ACTION==\\\"add\\\", TEST==\\\"online\\\", ATTR{online}==\\\"0\\\", ATTR{online}=\\\"1\\\"\" > /lib/udev/rules.d/80-hotplug-cpu.rules
        - apt update
        - apt install -y qemu-guest-agent net-tools
        - timedatectl set-timezone ${var.timezone}
        - systemctl enable qemu-guest-agent
        - systemctl start qemu-guest-agent
        - echo "done" > /tmp/cloud-config.done

    EOF

    file_name = "user-data-cloud-config-${var.vm_name}.yaml"
  }
  lifecycle {
    ignore_changes = [
      source_raw[0].data
    ]
  }
}
