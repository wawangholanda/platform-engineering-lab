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

## Current Status

The Proxmox environment currently runs a highly available Kubernetes
platform with:

- 3 control-plane nodes
- 2 worker nodes
- 2 HAProxy / Keepalived load balancers
- Cilium networking
- NFS-based persistent storage
- NFS CSI integration
- Argo CD GitOps
- Prometheus
- Grafana
- Alertmanager

The current implementation is operational and continuously validated
through infrastructure, Kubernetes, and monitoring checks.

## Current Implementation

### Proxmox → Highly Available Kubernetes

The first implementation provisions and configures a highly available
Kubernetes platform on Proxmox.

Current stack:

- Terraform — infrastructure provisioning
- Ansible — configuration management
- Kubernetes 1.34
- containerd — container runtime
- Cilium — CNI and network observability
- HAProxy — Kubernetes API load balancing
- Keepalived — virtual IP / load balancer HA
- Helm — Kubernetes package management
- NFS — persistent storage
- NFS CSI — Kubernetes storage integration
- Argo CD — GitOps
- Prometheus — metrics and monitoring
- Grafana — visualization and dashboards
- Alertmanager — alert management

### Observability

The Kubernetes platform includes a GitOps-managed observability stack
based on kube-prometheus-stack.

Current components:

- Prometheus
- Grafana
- Alertmanager
- node-exporter
- kube-state-metrics

Monitoring covers:

- Kubernetes API servers
- etcd
- kube-controller-manager
- kube-scheduler
- kubelet
- node metrics
- CoreDNS
- Kubernetes state metrics

Prometheus targets are validated through the Prometheus HTTP API and
Kubernetes target discovery.

Detailed deployment and validation procedures are documented under
`docs/observability/`.

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
         192.168.1.20   192.168.1.23   192.168.1.24
             \              |              /
              \             |             /
               +------------+------------+
                            |
                    Kubernetes Cluster
                       /          \
                      /            \
                 Worker01        Worker02
                192.168.1.21   192.168.1.22
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
    +--------------------+
    |                    |
    v                    v
OS / LB Configuration   Kubernetes Bootstrap
                             |
                             v
                    Cilium / Helm / NFS
                             |
                             v
                         Argo CD
                             |
                  +----------+----------+
                  |          |          |
                  v          v          v
               Apps     Monitoring    Storage
                           |
                  +--------+--------+
                  |        |        |
                  v        v        v
              Prometheus Grafana Alertmanager
```

Terraform provisions the underlying infrastructure, while Ansible
configures the operating systems, load balancers, and Kubernetes
platform.

Argo CD manages Kubernetes platform and application resources through
GitOps.

## Repository Structure

```text
platform-engineering-lab/

├── environments/
│   └── dev/
│       ├── proxmox/       # Environment-specific Terraform
│       └── kubernetes/    # Environment-specific Kubernetes resources
│
├── modules/
│   └── proxmox-vm/        # Reusable Terraform modules
│
├── ansible/
│   ├── inventory/         # Environment inventories
│   ├── roles/             # Reusable Ansible roles
│   └── playbooks/         # Ansible playbooks
│
├── kubernetes/             # Kubernetes platform components and tests
│
├── docs/                   # Technical documentation
│
├── .github/                # GitHub Actions workflows
├── .gitignore
├── .pre-commit-config.yaml
├── LICENSE
└── README.md
```

## Kubernetes Automation

The Kubernetes platform is bootstrapped and configured using Ansible.

The automation currently handles:

- Common Kubernetes node configuration
- Swap configuration
- Kernel modules and sysctl
- containerd configuration
- Kubernetes package installation
- First control-plane bootstrap
- Additional control-plane nodes
- Worker nodes
- HAProxy configuration
- Keepalived configuration
- Cilium installation
- Helm installation
- Control-plane metrics configuration
- NFS server and client configuration
- NFS CSI deployment
- Argo CD installation and GitOps bootstrap
- Monitoring stack deployment through GitOps

The playbooks are designed to be idempotent and are validated using
Ansible syntax checks, check mode, and repeated runs.

Cluster-affecting control-plane operations are executed serially to
reduce the risk of simultaneous disruption.

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

HAProxy distributes Kubernetes API traffic across the control-plane
nodes.

Keepalived provides the virtual IP and failover between the load
balancers.

## Infrastructure as Code

Terraform is used to provision the underlying Proxmox infrastructure,
while Ansible is used for operating system configuration and Kubernetes
bootstrap.

The Terraform structure separates:

- Environment configuration
- Reusable modules
- Provider configuration
- VM definitions
- Infrastructure variables

The Ansible structure separates:

- Inventory
- Group variables
- Reusable roles
- Bootstrap playbooks
- Platform-specific configuration

The long-term goal is to apply the same Infrastructure as Code
principles across Proxmox and public cloud environments.

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
- [x] NFS server and client automation
- [x] NFS CSI driver
- [x] Kubernetes StorageClass
- [x] PersistentVolumeClaim / PersistentVolume testing
- [x] Persistent storage read/write testing
- [x] Worker node failure testing
- [x] Control-plane failure testing
- [x] Control-plane recovery validation
- [x] Argo CD / GitOps
- [x] Application deployment through GitOps

### Observability Roadmap

- [x] Prometheus
- [x] Grafana
- [x] Alertmanager
- [x] Kubernetes control-plane metrics
- [x] Node metrics
- [x] Kubelet metrics
- [x] Kubernetes state metrics
- [x] Monitoring configuration managed through GitOps
- [ ] Infrastructure failure alert rules
- [ ] Alert notification integration
- [ ] Production-oriented Grafana dashboards
- [ ] Logging stack

### Security Roadmap

- [ ] Kubernetes security baseline
- [ ] Cilium NetworkPolicy
- [ ] Pod Security Admission
- [ ] RBAC hardening
- [ ] Secrets management
- [ ] Image vulnerability scanning
- [ ] Kubernetes security validation

### Reliability and Disaster Recovery

- [x] Worker node failure testing
- [x] Control-plane failure testing
- [x] Control-plane recovery validation
- [ ] etcd backup automation
- [ ] Kubernetes backup strategy
- [ ] Disaster recovery procedure
- [ ] Restore testing
- [ ] Automated failure scenarios

### Platform Automation

- [ ] Automated infrastructure validation
- [ ] Kubernetes manifest validation
- [ ] Ansible linting
- [ ] Terraform validation
- [ ] Automated Kubernetes health checks
- [ ] Post-deployment validation
- [ ] Integration testing
- [ ] Automated failure scenario testing

### CI/CD and GitOps

- [x] Argo CD GitOps
- [x] Git-managed application deployment
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

Sensitive values should be stored outside version control and excluded
through `.gitignore`.

Example:

```text
.env
*.tfvars
*.tfstate
*.tfstate.*
```

Example configuration files should contain placeholder values only.

## Development Workflow

Changes are intended to follow this workflow:

```text
Local Development
       |
       v
Terraform Validate / Plan
       |
       v
Ansible Syntax Check / Check Mode
       |
       v
Infrastructure / Platform Changes
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
       |
       v
Argo CD
       |
       v
Kubernetes
```

Pre-commit hooks are used to maintain repository consistency and detect
common issues before changes are committed.

## Documentation

Technical documentation is maintained under `docs/`:

```text
docs/
├── architecture/
├── proxmox/
├── kubernetes/
├── ansible/
├── terraform/
├── gitops/
├── observability/
└── operations/
```

Documentation covers architecture, infrastructure provisioning,
Kubernetes operations, automation, GitOps, observability, and
operational procedures.

## Purpose

This project is a practical Platform Engineering laboratory and
portfolio focused on:

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
