variable "ssh_filename" {
  type = string
}

variable "vm_name" {
  type = string
}
variable "timezone" {
  description = "Timezone set on every VM via cloud-init (timedatectl format)"
  type        = string
  default     = "UTC"
}
