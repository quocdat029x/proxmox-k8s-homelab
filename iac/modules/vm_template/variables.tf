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
  default = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}
variable "vm_net_subnet_cidr" {
  type        = string
  description = "Address prefix for the internal network (e.g., 192.168.1.0/24)"
}
variable "node_count" {
  type = number
  default = 1
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
