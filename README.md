# Platform Engineering Lab

A hands-on Platform Engineering laboratory for building, automating,
and operating infrastructure across multiple platforms.

The project focuses on Infrastructure as Code, configuration management,
Kubernetes, GitOps, observability, security, and highly available
infrastructure using reproducible automation.

## Overview

The laboratory is designed to support multiple infrastructure platforms:

- Proxmox
- AWS
- Google Cloud
- Alibaba Cloud
- Future platforms

The goal is to maintain a consistent Platform Engineering approach
across different infrastructure environments.

## Current Implementation

### Proxmox → Highly Available Kubernetes

The first implementation provisions and configures a highly available
Kubernetes cluster on Proxmox.

Current stack:

- Terraform — infrastructure provisioning
- Ansible — configuration management
- Kubernetes 1.34
- containerd — container runtime
- Cilium — CNI
- HAProxy — Kubernetes API load balancing
- Keepalived — virtual IP / load balancer HA
- Helm — Kubernetes package management

### Architecture

```text
                       Kubernetes API
                            |
                    Virtual IP (VIP)
                    192.168.1.30:6443
                            |
                 +----------+----------+
                 |                     |
              LB01                    LB02
          192.168.1.25           192.168.1.26
            HAProxy                HAProxy
           Keepalived             Keepalived
                 |                     |
                 +----------+----------+
                            |
             +--------------+--------------+
             |              |              |
            CP01           CP02           CP03
          192.168.1.20    192.168.1.23    192.168.1.24
             |
        +----+----+
        |         |
      Worker01  Worker02
      192.168.1.21  192.168.1.22
```

## Infrastructure Workflow

The current infrastructure follows this workflow:

```text
Terraform
    |
    v
Proxmox Infrastructure
    |
    v
Ansible
    |
    v
Operating System Configuration
    |
    v
Kubernetes Cluster
    |
    v
Cilium / Helm / Platform Services
    |
    v
GitOps / Observability / Security
```

Terraform is responsible for provisioning infrastructure, while Ansible
configures the operating systems and bootstraps the Kubernetes platform.

## Repository Structure

```text
platform-engineering-lab/
├── environments/
│   └── dev/
│       └── proxmox/       # Environment-specific Terraform
│
├── modules/
│   └── proxmox-vm/        # Reusable Terraform modules
│
├── ansible/
│   ├── inventory/         # Environment inventories
│   ├── roles/             # Ansible roles
│   └── site.yml           # Main Ansible playbook
│
├── kubernetes/            # Kubernetes platform components
├── docs/                  # Technical documentation
│
├── .github/               # GitHub Actions workflows
├── .gitignore
├── .pre-commit-config.yaml
├── LICENSE
└── README.md
```

## Kubernetes Automation

The Kubernetes cluster is bootstrapped using Ansible.

The automation currently handles:

- Common Kubernetes node configuration
- Swap configuration
- Kernel modules and sysctl
- containerd configuration
- Kubernetes package installation
- First control-plane bootstrap
- Additional control-plane nodes
- Worker nodes
- Cilium installation
- Helm installation
- HAProxy configuration
- Keepalived configuration

The playbooks are designed to be idempotent so they can safely be
re-applied to an existing environment.

## High Availability

The Kubernetes API endpoint is exposed through a virtual IP:

```text
192.168.1.30:6443
```

Two load balancer nodes provide high availability:

```text
LB01
192.168.1.25
HAProxy + Keepalived
MASTER

LB02
192.168.1.26
HAProxy + Keepalived
BACKUP
```

HAProxy distributes Kubernetes API traffic across the control-plane nodes.

Keepalived provides the virtual IP and failover between the load balancers.

## Infrastructure as Code

Terraform is used to provision the Proxmox infrastructure.

The Terraform structure separates:

- Environment configuration
- Reusable modules
- Provider configuration
- VM definitions
- Infrastructure variables

The long-term goal is to use the same Infrastructure as Code principles
across Proxmox and public cloud environments.

## Roadmap

### Completed

- [x] Terraform + Proxmox
- [x] Reusable Terraform VM module
- [x] Ansible automation
- [x] Idempotent Ansible configuration
- [x] Highly available Kubernetes control plane
- [x] HAProxy
- [x] Keepalived
- [x] Cilium
- [x] Helm
- [x] Kubernetes worker nodes
- [x] NFS server automation
- [x] NFS client configuration
- [x] NFS CSI driver
- [x] Kubernetes StorageClass
- [x] PersistentVolumeClaim / PersistentVolume testing
- [x] Persistent storage read/write testing
- [x] Worker node failure testing
- [x] Control-plane failure testing
- [x] Argo CD / GitOps
- [x] Application deployment through GitOps

### Next

- [ ] Monitoring with Prometheus and Grafana
- [ ] Logging
- [ ] Kubernetes security automation
- [ ] NetworkPolicy with Cilium
- [ ] Backup and disaster recovery
- [ ] Automated validation and testing

### CI/CD and Platform Automation

- [ ] GitHub Actions
- [ ] Terraform CI/CD
- [ ] Ansible CI/CD
- [ ] Kubernetes manifest validation
- [ ] Atlantis
- [ ] Automated infrastructure testing

### Planned Platforms

- [ ] AWS
- [ ] Google Cloud
- [ ] Alibaba Cloud
- [ ] Additional infrastructure platforms

Each platform will be implemented as a separate environment while
reusing common Platform Engineering principles and automation patterns.

## Security

Secrets, credentials, private keys, and other sensitive configuration
must never be committed to the repository.

Sensitive values are stored locally and excluded through `.gitignore`.

Example:

```text
.env
*.tfvars
*.tfstate
*.tfstate.*
```

Example configuration files containing sensitive values should use
placeholder values only.

## Development Workflow

Changes are intended to follow this workflow:

```text
Local Development
       |
       v
Terraform Validate / Plan
       |
       v
Ansible Syntax Check
       |
       v
Ansible Playbook
       |
       v
Kubernetes Validation
       |
       v
Git Commit
       |
       v
GitHub
       |
       v
CI/CD
```

Pre-commit hooks are used to maintain repository consistency and detect
common issues before changes are committed.

## Documentation

Technical documentation will be maintained under:

```text
docs/
├── architecture/
├── proxmox/
├── kubernetes/
├── ansible/
├── terraform/
└── operations/
```

## Purpose

This project is a practical Platform Engineering laboratory and portfolio
focused on:

- Reproducible infrastructure
- Infrastructure as Code
- Configuration management
- Highly available systems
- Kubernetes
- Automation
- GitOps
- Observability
- Security
- Multi-platform infrastructure

The project is intended to evolve from a Proxmox-based Kubernetes
laboratory into a multi-platform Platform Engineering environment.

## License

See [LICENSE](LICENSE).
