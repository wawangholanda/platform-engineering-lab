variable "vmid" {
  description = "Proxmox LXC container ID"
  type        = number
}

variable "name" {
  description = "LXC hostname/name"
  type        = string
}

variable "target_node" {
  description = "Proxmox node where the LXC will run"
  type        = string
}

variable "ostemplate" {
  description = "Proxmox LXC OS template"
  type        = string
}

variable "storage" {
  description = "Proxmox storage for the LXC root filesystem"
  type        = string
}

variable "disk_size" {
  description = "LXC root filesystem size in GB"
  type        = number
  default     = 8
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 1
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 512
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

variable "ssh_public_keys" {
  description = "SSH public key injected into the LXC container"
  type        = string
  sensitive   = false
  default     = null
}

variable "cloud_init_password" {
  description = "Password for the LXC root user"
  type        = string
  sensitive   = true
  default     = null
}

variable "start" {
  description = "Whether the LXC should start after creation"
  type        = bool
  default     = true
}

variable "onboot" {
  description = "Whether the LXC should start when the Proxmox node boots"
  type        = bool
  default     = true
}
