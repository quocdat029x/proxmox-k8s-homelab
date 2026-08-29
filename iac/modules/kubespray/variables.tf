variable "prefix" {
  type = string
}
variable "project" {
  type = string
}
variable "environment" {
  type = string
}
variable "region" {
  type = string
}
variable "region_code" {
  type = string
}
variable "responsible_party" {
  type = string
}
variable "owner" {
  type = string
}

variable "ssh_filename" {
  type = string
}

variable "resource_pool" {
  type = string
}

variable "vm_name" {
  type = string
}
variable "image_file_id" {
  type = string
  default = ""
}
variable "cpu_cores" {
  type = string
  default = "1"
}
variable "disk_size" {
  type = string
  default = "20"
}
variable "template" {
  type = string
  default = false
}
variable "image" {
  type = string
  default = ""
}
variable "vm_net_subnet_cidr" {
  type        = string
  description = "Address prefix for the internal network (e.g., 192.168.1.0/24)"
}
variable "node_count" {
  type = number
}
variable "vm_host_number" {
  type        = number
  description = "The host number of the VM in the subnet (e.g., 10 for .10)"
}

locals {
  # Extract subnet mask from CIDR
  vm_net_subnet_mask = "/${split("/", var.vm_net_subnet_cidr)[1]}"

  # First usable IP as the gateway
  vm_net_default_gw = cidrhost(var.vm_net_subnet_cidr, 1)
}
variable "template_id" {
  type = string
}
variable "vm_host_offset" {
  type = number
}

variable "kubespray_image" {
  type        = string
  description = "The Docker image to deploy Kubespray"
  default     = "quay.io/kubespray/kubespray:v2.28.0"
}

variable "kube_version" {
  type        = string
  description = "Kubernetes version"
  default     = "1.32.3"
}

variable "etcd_version" {
  type        = string
  description = "Etcd version"
  default     = "3.5.21"
}

variable "pod_infra_supported_versions" {
  type        = string
  description = "Pod infra supported versions"
  default     = "3.10"
  
}

variable "kube_network_plugin" {
  type        = string
  description = "The network plugin to be installed on your cluster. Example: `cilium`, `calico`, `kube-ovn`, `weave` or `flannel`"
  default     = "calico"
}

variable "enable_nodelocaldns" {
  type        = bool
  description = "Whether to enable nodelocal dns cache on your cluster"
  default     = false
}
variable "podsecuritypolicy_enabled" {
  type        = bool
  description = "Whether to enable pod security policy on your cluster (RBAC must be enabled either by having 'RBAC' in authorization_modes or kubeadm enabled)"
  default     = false
}
variable "persistent_volumes_enabled" {
  type        = bool
  description = "Whether to add Persistent Volumes Storage Class for corresponding cloud provider (supported: in-tree OpenStack, Cinder CSI, AWS EBS CSI, Azure Disk CSI, GCP Persistent Disk CSI)"
  default     = false
}
variable "helm_enabled" {
  type        = bool
  description = "Whether to enable Helm on your cluster"
  default     = true
}
variable "ingress_nginx_enabled" {
  type        = bool
  description = "Whether to enable Nginx ingress on your cluster"
  default     = true
}
variable "argocd_enabled" {
  type        = bool
  description = "Whether to enable ArgoCD on your cluster"
  default     = false
}
variable "argocd_version" {
  type        = string
  description = "The ArgoCD version to be installed"
  default     = "2.10.5"
}
variable "location" {
  type        = string
  description = "The city or region where the cluster is provisioned"
  default     = "cantho"
}
variable "env_name" {
  type        = string
  description = "The stage of the development lifecycle for the k8s cluster. Example: `prod`, `dev`, `qa`, `stage`, `test`"
  default     = "prod"
}
variable "cluster_number" {
  type        = string
  description = "The instance count for the k8s cluster, to differentiate it from other clusters. Example: `00`, `01`"
  default     = "01"
}
variable "cluster_domain" {
  type        = string
  description = "The cluster domain name"
  default     = "local"
}
variable "create_kubespray_host" {
  type        = bool
  description = "Whether to provision the Kubespray as a VM"
  default     = true
}
variable "control_plane_vm_list" {
  type = list(map(string))
  description = "List of control plane VMs"
}
variable "worker_vm_list" {
  type = list(map(string))
  description = "List of worker VMs"
}
variable "ssh_private_key" {
  type = string
}

variable "control_plane_ip" {
  type        = string
  description = "Control plane IP address for accessing the cluster"
  default     = ""
}

variable "vault_addr" {
  type        = string
  description = "Vault server address"
  default     = ""
}

variable "vault_token" {
  type        = string
  description = "Vault authentication token"
  default     = ""
}

variable "vault_secret_path" {
  type        = string
  description = "Vault secret path for storing credentials"
  default     = ""
}
