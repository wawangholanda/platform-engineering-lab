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

  bridge     = "vmbr0"
  ip_address = "192.168.1.20/24"
  gateway    = "192.168.1.1"
  nameserver = "192.168.1.1"
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

  bridge     = "vmbr0"
  ip_address = "192.168.1.21/24"
  gateway    = "192.168.1.1"
  nameserver = "192.168.1.1"
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

  bridge     = "vmbr0"
  ip_address = "192.168.1.22/24"
  gateway    = "192.168.1.1"
  nameserver = "192.168.1.1"
}
