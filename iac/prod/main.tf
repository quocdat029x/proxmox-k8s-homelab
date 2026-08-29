locals {
  tags = {
    Project = var.project
    Environment = var.environment
    ResponsibileParty = var.responsible_party
    Owner = var.owner
  }
  domain_name = "${var.environment}.${module.secret_data.infra_data.data.root_domain_name}"
}

module "proxmox_pools" {
  source = "../modules/pool"
  environment = var.environment
  owner = var.owner
  prefix = var.prefix
  project = var.project
  region = var.region
  region_code = var.region_code
  responsible_party = var.responsible_party
}

module "secret_data" {
  source = "../modules/vault"
  environment = var.environment
}

module "vm_template" {
  vm_name = "ubuntu-cloud-template"
  source = "../modules/vm_template"
  environment = var.environment
  owner = var.owner
  prefix = var.prefix
  project = var.project
  region = var.region
  region_code = var.region_code
  responsible_party = var.responsible_party
  ssh_filename = data.local_file.ssh_public_key.filename
  resource_pool = module.proxmox_pools.k8s_pool
  cpu_cores = "1"
  disk_size = "20"
  template = true
  vm_net_subnet_cidr = module.secret_data.infra_data.data.internal_net_subnet_cidr
  image = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  vm_host_number = 10
}

module "vm_k8s_control_plane" {
  vm_name = "control-plane"
  source = "../modules/vm"
  environment = var.environment
  owner = var.owner
  prefix = var.prefix
  project = var.project
  region = var.region
  region_code = var.region_code
  responsible_party = var.responsible_party
  ssh_filename = data.local_file.ssh_public_key.filename
  resource_pool = module.proxmox_pools.k8s_pool
  cpu_cores = "6"
  disk_size = "50"
  template = false
  vm_net_subnet_cidr = module.secret_data.infra_data.data.internal_net_subnet_cidr
  vm_host_number = 10
  node_count = 3
  template_id = module.vm_template.template_id
  vm_host_offset = 10
  memory = "8192"
}

module "vm_k8s_worker" {
  vm_name = "k8s-worker"
  source = "../modules/vm"
  environment = var.environment
  owner = var.owner
  prefix = var.prefix
  project = var.project
  region = var.region
  region_code = var.region_code
  responsible_party = var.responsible_party
  ssh_filename = data.local_file.ssh_public_key.filename
  resource_pool = module.proxmox_pools.k8s_pool
  cpu_cores = "4"
  disk_size = "40"
  template = false
  vm_net_subnet_cidr = module.secret_data.infra_data.data.internal_net_subnet_cidr
  vm_host_number = 10
  node_count = 3
  template_id = module.vm_template.template_id
  depends_on = [module.vm_k8s_control_plane]
  vm_host_offset = 20
  memory = "8192"
}

module "vm_k8s_kubespray" {
  vm_name = "kubespray"
  source = "../modules/kubespray"
  environment = var.environment
  owner = var.owner
  prefix = var.prefix
  project = var.project
  region = var.region
  region_code = var.region_code
  responsible_party = var.responsible_party
  ssh_filename = data.local_file.ssh_public_key.filename
  ssh_private_key = module.secret_data.infra_data.data.ssh_encoded_private_key
  resource_pool = module.proxmox_pools.k8s_pool
  cpu_cores = "4"
  disk_size = "20"
  template = false
  vm_net_subnet_cidr = module.secret_data.infra_data.data.internal_net_subnet_cidr
  vm_host_number = 10
  node_count = 1
  template_id = module.vm_template.template_id
  depends_on = [module.vm_template]
  vm_host_offset = 0
  create_kubespray_host = true
  # Pass the VM list directly without trying to convert it
  control_plane_vm_list = module.vm_k8s_control_plane.vm_list
  worker_vm_list = module.vm_k8s_worker.vm_list
}

module "bastion_host" {
  vm_name = "bastion-host"
  source = "../modules/bastion_host"
  environment = var.environment
  owner = var.owner
  prefix = var.prefix
  project = var.project
  region = var.region
  region_code = var.region_code
  responsible_party = var.responsible_party
  ssh_filename = data.local_file.ssh_public_key.filename
  resource_pool = module.proxmox_pools.k8s_pool
  cpu_cores = "2"
  disk_size = "20"
  template = false
  vm_net_subnet_cidr = module.secret_data.infra_data.data.management_net_subnet_cidr
  vm_net_subnet_cidr_second = module.secret_data.infra_data.data.internal_net_subnet_cidr
  vm_host_number = 10
  node_count = 1
  template_id = module.vm_template.template_id
  vm_host_offset = 30
}

data "local_file" "ssh_public_key" {
  filename = var.ssh_public_key_path
}