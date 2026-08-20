# Terraform Architecture

## Overview

Terraform provisions the infrastructure layer of the Platform Engineering
Lab.

The current implementation targets Proxmox and provisions the virtual
machines required for the highly available Kubernetes platform.

Terraform manages infrastructure provisioning, while Ansible handles
operating system configuration and Kubernetes bootstrap.

## Infrastructure Flow

```text
Terraform
    |
    v
Environment Configuration
    |
    v
Reusable Modules
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
```

## Repository Structure

```text
platform-engineering-lab/

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
| 9000 | ubuntu-2404-template | Template | — |

The Kubernetes API is exposed through:

```text
192.168.1.30:6443
```

The virtual IP is managed by Keepalived and is therefore not provisioned
as a separate Terraform VM.

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

The provisioning model is:

```text
Ubuntu Template
      |
      v
Reusable VM Module
      |
      v
Environment VM Definitions
      |
      v
Proxmox VMs
```

## Provider

The Proxmox provider is configured in:

```text
environments/dev/proxmox/providers.tf
```

Provider credentials and other sensitive values should be supplied
through variables or environment configuration and must not be
committed to Git.

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
Terraform Plan
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
3. Confirm that the node can safely be replaced.
4. Preserve required data and certificates.
5. Review the Terraform plan carefully.

Control-plane replacement should be treated as a Kubernetes operational
procedure, not simply as a VM recreation task.

## Design Principles

The Terraform implementation follows these principles:

- Environment-specific configuration is separated from reusable modules.
- Reusable infrastructure logic is encapsulated in modules.
- Sensitive configuration is kept outside version control.
- Infrastructure changes are reviewed through `terraform plan`.
- VM provisioning is separated from operating system configuration.
- Kubernetes configuration is delegated to Ansible.
- Infrastructure should remain reproducible.

## Future Improvements

- [ ] Remote Terraform state
- [ ] Terraform CI/CD
- [ ] Automated validation
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
