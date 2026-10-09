terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.2-rc08"
    }
  }
}

resource "proxmox_lxc" "this" {
  hostname    = var.name
  vmid        = var.vmid
  target_node = var.target_node

  ostemplate = var.ostemplate

  cores  = var.cores
  memory = var.memory

  password        = var.cloud_init_password
  ssh_public_keys = var.ssh_public_keys

  nameserver = var.nameserver

  rootfs {
    storage = var.storage
    size    = "${var.disk_size}G"
  }

  network {
    name   = "eth0"
    bridge = var.bridge
    ip     = var.ip_address
    gw     = var.gateway
  }

  start  = var.start
  onboot = var.onboot

  unprivileged = true
}
