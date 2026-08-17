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

  automatic_reboot = true

  scsihw = "virtio-scsi-pci"

  disks {
    scsi {
      scsi0 {
        disk {
          storage = var.storage
          size    = var.disk_size
        }
      }

      dynamic "scsi1" {
        for_each = var.data_storage != null && var.data_disk_size > 0 ? [1] : []

        content {
          disk {
            storage = var.data_storage
            size    = var.data_disk_size
          }
        }
      }
    }

    ide {
      ide2 {
        cloudinit {
          storage = var.storage
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = var.bridge
  }

  os_type = "cloud-init"

  ipconfig0 = "ip=${var.ip_address},gw=${var.gateway}"

  nameserver = var.nameserver

  sshkeys = var.ssh_public_key

  ciuser = "ubuntu"

  boot = "order=scsi0"

  start_at_node_boot = true

  define_connection_info = false

  agent = 1

  lifecycle {
    ignore_changes = [
      vm_state,
      disk[0].format,
      startup_shutdown,
    ]
  }
}
