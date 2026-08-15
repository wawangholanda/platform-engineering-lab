terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.2-rc08"
    }
  }
}

resource "proxmox_vm_qemu" "this" {
  name        = var.name
  vmid        = var.vmid
  target_node = var.target_node

  clone      = var.clone_template
  full_clone = true

  cpu {
    cores = var.cores
  }
  memory = var.memory

  scsihw = "virtio-scsi-pci"

  disk {
    slot    = "scsi0"
    type    = "disk"
    storage = var.storage
    size    = "${var.disk_size}G"
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = var.bridge
  }

  os_type = "cloud-init"

  ipconfig0 = "ip=${var.ip_address},gw=${var.gateway}"

  nameserver = var.nameserver

  ciuser = "ubuntu"

  boot = "order=scsi0"

  start_at_node_boot = true

  define_connection_info = false

  lifecycle {
    ignore_changes = [
      agent,
      vm_state,
      disk[0].format,
      startup_shutdown,
    ]
  }

}
