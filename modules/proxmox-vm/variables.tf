variable "vmid" {
  description = "Proxmox VM ID"
  type        = number
}

variable "name" {
  description = "VM hostname/name"
  type        = string
}

variable "target_node" {
  description = "Proxmox node where the VM will run"
  type        = string
}

variable "clone_template" {
  description = "Source Proxmox VM template name"
  type        = string
}

variable "storage" {
  description = "Proxmox storage for the VM disk"
  type        = string
}

variable "disk_size" {
  description = "VM disk size"
  type        = number
  default     = 40
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 4
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 8192
}

variable "bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "ip_address" {
  description = "Static IPv4 address with CIDR"
  type        = string
}

variable "gateway" {
  description = "IPv4 gateway"
  type        = string
}

variable "nameserver" {
  description = "DNS nameserver"
  type        = string
  default     = "192.168.1.1"
}
