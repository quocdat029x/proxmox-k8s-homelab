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
locals {
  tags = {
    Project = var.project
    Environment = var.environment
    ResponsibileParty = var.responsible_party
    Owner = var.owner
  }
  domain_name = "${var.environment}.${module.secret_data.infra_data.data.root_domain_name}"
}
module "secret_data" {
  source = "../../modules/vault"
  environment = var.environment
}

resource "proxmox_virtual_environment_pool" "k8s" {
  comment =  "k8s ${local.tags.Environment} Node pool - Managed by Terraform"
  pool_id  = "${local.tags.Environment}-k8s-pool"
}
resource "proxmox_virtual_environment_pool" "standalone" {
  comment =  "${local.tags.Environment} Node pool for standalone - manage by Terraform"
  pool_id  = "standalone-pool"
}