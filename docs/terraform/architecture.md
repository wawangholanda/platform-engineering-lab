# Terraform Architecture

## Overview

Terraform provisions the infrastructure layer of the Platform Engineering
Lab.

The current implementation targets Proxmox and provisions the virtual
machines required for the highly available Kubernetes platform.

Terraform manages infrastructure provisioning, while Ansible handles
operating system configuration, Proxmox bootstrap, and Kubernetes
bootstrap.

## Infrastructure Flow

```text
Proxmox Bootstrap
        |
        +-----------------------------+
        |                             |
        v                             v
Terraform API User              Ubuntu VM Template
Role + ACL + Token                  VMID 9000
        |                             |
        +-------------+---------------+
                      |
                      v
                  Terraform
                      |
                      v
              Environment Configuration
                      |
                      v
               Reusable VM Module
                      |
                      v
                Proxmox Provider
                      |
                      v
                 Proxmox VMs
                      |
                      v
                   Ansible
                      |
                      v
              Kubernetes Platform
                      |
                      v
                 GitOps Services
```

The Proxmox bootstrap stage is implemented by:

```text
ansible/playbooks/proxmox-bootstrap.yml
```

The Terraform infrastructure stage is implemented under:

```text
environments/dev/proxmox/
```

## Repository Structure

```text
platform-engineering-lab/

├── ansible/
│   ├── playbooks/
│   │   ├── proxmox-bootstrap.yml
│   │   └── site.yml
│   │
│   └── roles/
│       └── proxmox_bootstrap/
│
├── environments/
│   └── dev/
│       └── proxmox/
│           ├── main.tf
│           ├── providers.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── terraform.tfvars.example
│
└── modules/
    └── proxmox-vm/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

The environment layer contains Proxmox-specific configuration, while
the module contains reusable VM provisioning logic.

Ansible is responsible for preparing the Proxmox prerequisites required
by Terraform, including the Terraform API user, role, token, ACL, and
Ubuntu VM template.

## Proxmox Infrastructure

The development environment currently contains:

| VMID | Hostname | Role | IP |
|---:|---|---|---|
| 100 | k8s-cp01 | Control Plane | 192.168.1.20 |
| 101 | k8s-worker01 | Worker | 192.168.1.21 |
| 102 | k8s-worker02 | Worker | 192.168.1.22 |
| 103 | k8s-cp02 | Control Plane | 192.168.1.23 |
| 104 | k8s-cp03 | Control Plane | 192.168.1.24 |
| 105 | k8s-lb01 | Load Balancer | 192.168.1.25 |
| 106 | k8s-lb02 | Load Balancer | 192.168.1.26 |
| 107 | k8s-nfs01 | NFS Server | 192.168.1.27 |
| 9000 | ubuntu-2404-template | Template | — |

The Kubernetes API is exposed through:

```text
192.168.1.30:6443
```

The virtual IP is managed by Keepalived and is therefore not provisioned
as a separate Terraform VM.

Terraform provisions the VMs on the Proxmox `local-zfs` storage.

## Reusable VM Module

The reusable module is:

```text
modules/proxmox-vm/
```

The module encapsulates common VM configuration such as:

- VM name and VM ID
- Clone source
- CPU and memory
- Network configuration
- IP address and gateway
- Cloud-init
- QEMU guest agent
- Startup configuration

This allows Kubernetes and load-balancer VMs to be provisioned
consistently without duplicating resource definitions.

## Template-Based Provisioning

The VMs are cloned from:

```text
VMID 9000
ubuntu-2404-template
```

The template is prepared by the Ansible Proxmox bootstrap role before
Terraform provisions the infrastructure.

The provisioning model is:

```text
Ansible Proxmox Bootstrap
          |
          v
Ubuntu Cloud Image
          |
          v
VM Template 9000
          |
          v
Terraform Reusable VM Module
          |
          v
Environment VM Definitions
          |
          v
Proxmox VMs
```

The template is based on the Ubuntu 24.04 cloud image and provides the
base image used by the Terraform-managed virtual machines.

## Provider

The Proxmox provider is configured in:

```text
environments/dev/proxmox/providers.tf
```

Provider credentials and other sensitive values should be supplied
through variables or environment configuration and must not be
committed to Git.

The Proxmox API user, role, token, and required ACL are prepared by the
Ansible `proxmox_bootstrap` role.

## Variables and Outputs

Environment-specific values are defined through Terraform variables.

A template is provided as:

```text
environments/dev/proxmox/terraform.tfvars.example
```

Sensitive or environment-specific `.tfvars` files should remain outside
version control.

Terraform outputs provide infrastructure information such as:

- VM IDs
- VM names
- IP addresses
- Other infrastructure attributes

These outputs can be consumed by subsequent automation stages.

## State Management

Terraform maintains infrastructure state in:

```text
terraform.tfstate
```

State files may contain sensitive infrastructure information and should
not be committed to Git.

Recommended `.gitignore` entries:

```text
*.tfstate
*.tfstate.*
```

Remote state is a future improvement for CI/CD and multi-user workflows.

## Infrastructure Lifecycle

The intended lifecycle is:

```text
Proxmox Bootstrap
      |
      v
Terraform Init
      |
      v
Terraform Validate
      |
      v
Terraform Plan
      |
      v
Review
      |
      v
Terraform Apply
      |
      v
Proxmox Infrastructure
      |
      v
Ansible Configuration
      |
      v
Kubernetes Bootstrap
      |
      v
GitOps Platform Services
```

The Proxmox bootstrap prepares the infrastructure prerequisites before
Terraform is executed.

Terraform then provisions the virtual machines, while Ansible configures
the operating systems and Kubernetes platform.

This separation keeps infrastructure provisioning independent from
operating system and Kubernetes configuration.

## Validation

Format Terraform:

```bash
terraform fmt -check -recursive
```

Initialize the working directory:

```bash
terraform init
```

Validate the configuration:

```bash
terraform validate
```

Review infrastructure changes:

```bash
terraform plan
```

Apply only after the plan has been reviewed:

```bash
terraform apply
```

The expected workflow is:

```text
fmt
 |
 v
init
 |
 v
validate
 |
 v
plan
 |
 v
review
 |
 v
apply
```

## Failure and Recovery

Terraform manages infrastructure, but it should not be used as a
substitute for Kubernetes or etcd recovery procedures.

Before destroying or recreating a control-plane VM:

1. Verify Kubernetes cluster health.
2. Verify etcd membership and quorum.
3. Confirm that the node can be safely replaced.
4. Preserve required data and certificates.
5. Review the Terraform plan carefully.

Control-plane replacement should be treated as a Kubernetes operational
procedure, not simply as a VM recreation task.

A fresh Proxmox host must first be prepared by the Proxmox bootstrap
playbook before the Terraform environment can provision the Kubernetes
infrastructure.

## Design Principles

The Terraform implementation follows these principles:

- Environment-specific configuration is separated from reusable modules.
- Reusable infrastructure logic is encapsulated in modules.
- Sensitive configuration is kept outside version control.
- Infrastructure changes are reviewed through `terraform plan`.
- VM provisioning is separated from operating system configuration.
- Kubernetes configuration is delegated to Ansible.
- Proxmox prerequisites are automated through Ansible.
- Infrastructure should remain reproducible.

## Future Improvements

- [ ] Remote Terraform state
- [ ] Terraform CI/CD
- [ ] Policy validation
- [ ] Drift detection
- [ ] Additional Proxmox environments
- [ ] AWS infrastructure
- [ ] Google Cloud infrastructure
- [ ] Alibaba Cloud infrastructure
- [ ] Shared multi-platform modules

## Related Documentation

```text
docs/
├── architecture/
│   └── kubernetes-ha.md
│
├── ansible/
│   └── architecture.md
│
├── terraform/
│   └── architecture.md
│
├── kubernetes/
│   ├── cluster-bootstrap.md
│   ├── networking-cilium.md
│   └── storage-nfs.md
│
├── gitops/
│   └── argocd.md
│
├── observability/
│   └── prometheus.md
│
└── operations/
    ├── startup-shutdown.md
    ├── validation.md
    └── control-plane-failure.md
```
