module "k8s_nfs01" {
  source = "../../../modules/proxmox-vm"

  vmid           = 107
  name           = "k8s-nfs01"
  target_node    = "laptop"
  clone_template = "ubuntu-2404-template"

  # OS disk
  storage   = "local-lvm"
  disk_size = 20

  # NFS data disk
  data_storage   = "nvme-gabungan"
  data_disk_size = 64

  cores  = 2
  memory = 2048

  bridge         = "vmbr0"
  ip_address     = "192.168.1.27/24"
  gateway        = "192.168.1.1"
  nameserver     = "192.168.1.1"
  ssh_public_key = var.ssh_public_key
}

module "k8s_cp01" {
  source = "../../../modules/proxmox-vm"

  vmid           = 100
  name           = "k8s-cp01"
  target_node    = "laptop"
  clone_template = "ubuntu-2404-template"

  storage   = "nvme-gabungan"
  disk_size = 40
  cores     = 4
  memory    = 8192

  bridge         = "vmbr0"
  ip_address     = "192.168.1.20/24"
  gateway        = "192.168.1.1"
  nameserver     = "192.168.1.1"
  ssh_public_key = var.ssh_public_key
}

module "k8s_cp02" {
  source = "../../../modules/proxmox-vm"

  vmid           = 103
  name           = "k8s-cp02"
  target_node    = "laptop"
  clone_template = "ubuntu-2404-template"

  storage   = "nvme-gabungan"
  disk_size = 40
  cores     = 4
  memory    = 8192

  bridge         = "vmbr0"
  ip_address     = "192.168.1.23/24"
  gateway        = "192.168.1.1"
  nameserver     = "192.168.1.1"
  ssh_public_key = var.ssh_public_key
}

module "k8s_cp03" {
  source = "../../../modules/proxmox-vm"

  vmid           = 104
  name           = "k8s-cp03"
  target_node    = "laptop"
  clone_template = "ubuntu-2404-template"

  storage   = "nvme-gabungan"
  disk_size = 40
  cores     = 4
  memory    = 8192

  bridge         = "vmbr0"
  ip_address     = "192.168.1.24/24"
  gateway        = "192.168.1.1"
  nameserver     = "192.168.1.1"
  ssh_public_key = var.ssh_public_key
}

module "k8s_worker01" {
  source = "../../../modules/proxmox-vm"

  vmid           = 101
  name           = "k8s-worker01"
  target_node    = "laptop"
  clone_template = "ubuntu-2404-template"

  storage   = "nvme-gabungan"
  disk_size = 40
  cores     = 4
  memory    = 8192

  bridge         = "vmbr0"
  ip_address     = "192.168.1.21/24"
  gateway        = "192.168.1.1"
  nameserver     = "192.168.1.1"
  ssh_public_key = var.ssh_public_key
}

module "k8s_worker02" {
  source = "../../../modules/proxmox-vm"

  vmid           = 102
  name           = "k8s-worker02"
  target_node    = "laptop"
  clone_template = "ubuntu-2404-template"

  storage   = "nvme-gabungan"
  disk_size = 40
  cores     = 4
  memory    = 8192

  bridge         = "vmbr0"
  ip_address     = "192.168.1.22/24"
  gateway        = "192.168.1.1"
  nameserver     = "192.168.1.1"
  ssh_public_key = var.ssh_public_key
}
module "k8s_lb01" {
  source = "../../../modules/proxmox-vm"

  vmid           = 105
  name           = "k8s-lb01"
  target_node    = "laptop"
  clone_template = "ubuntu-2404-template"

  storage   = "nvme-gabungan"
  disk_size = 20
  cores     = 2
  memory    = 2048

  bridge         = "vmbr0"
  ip_address     = "192.168.1.25/24"
  gateway        = "192.168.1.1"
  nameserver     = "192.168.1.1"
  ssh_public_key = var.ssh_public_key
}

module "k8s_lb02" {
  source = "../../../modules/proxmox-vm"

  vmid           = 106
  name           = "k8s-lb02"
  target_node    = "laptop"
  clone_template = "ubuntu-2404-template"

  storage   = "nvme-gabungan"
  disk_size = 20
  cores     = 2
  memory    = 2048

  bridge         = "vmbr0"
  ip_address     = "192.168.1.26/24"
  gateway        = "192.168.1.1"
  nameserver     = "192.168.1.1"
  ssh_public_key = var.ssh_public_key
}
