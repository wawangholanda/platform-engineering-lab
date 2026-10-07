# Platform Engineering Lab

A hands-on **Platform Engineering laboratory** for building, automating, validating, and operating infrastructure across multiple platforms.

The project focuses on:

* Infrastructure as Code
* Configuration management
* Highly available Kubernetes
* Cloud-native networking
* GitOps
* Observability
* Storage
* Reliability and disaster recovery
* Infrastructure validation
* Reproducible automation

The current implementation runs a highly available Kubernetes platform on Proxmox and is designed to evolve toward a multi-platform environment.

---

## Overview

The project follows a layered Platform Engineering approach:

```text
Infrastructure
     │
     ▼
Terraform
     │
     ▼
Proxmox
     │
     ▼
Ansible
     │
     ▼
Kubernetes Platform
     │
     ├── Cilium
     ├── Storage
     ├── GitOps
     └── Observability
     │
     ▼
Applications
```

The goal is not simply to deploy Kubernetes, but to demonstrate how
infrastructure can be **provisioned, configured, operated, validated,
and recovered through automation**.

---

## Who Is This For?

### Beginner

If you are learning Platform Engineering, start with:

1. [Architecture](#architecture)
2. [What You Will Learn](#what-you-will-learn)
3. [Quick Start](#quick-start)
4. `docs/`

You do not need to understand the entire repository before starting.

### Intermediate

Explore the implementation of:

* Terraform
* Ansible
* Kubernetes
* Cilium
* HAProxy
* Keepalived
* NFS
* Argo CD
* Prometheus
* Grafana
* Platform validation

### Advanced

The `docs/` directory contains deeper implementation and operational documentation covering:

* Architecture decisions
* Terraform
* Ansible
* Kubernetes
* GitOps
* Observability
* Operations
* Disaster recovery
* Failure testing

---

## What You Will Learn

This laboratory provides practical experience with:

| Area                     | Technologies                              |
| ------------------------ | ----------------------------------------- |
| Infrastructure as Code   | Terraform                                 |
| Virtualization           | Proxmox                                   |
| Configuration Management | Ansible                                   |
| Container Orchestration  | Kubernetes                                |
| Networking               | Cilium                                    |
| API High Availability    | HAProxy + Keepalived                      |
| Storage                  | NFS + NFS CSI                             |
| Package Management       | Helm                                      |
| GitOps                   | Argo CD                                   |
| Metrics                  | Prometheus                                |
| Visualization            | Grafana                                   |
| Alerting                 | Alertmanager                              |
| Validation               | Ansible + Kubernetes tests                |
| Reliability              | Failure and recovery testing              |
| Disaster Recovery        | etcd backup and reconstruction validation |

---

## Current Platform

The current Proxmox environment provides a highly available Kubernetes platform with:

* 3 control-plane nodes
* 2 worker nodes
* 2 HAProxy / Keepalived load balancers
* Cilium networking
* NFS persistent storage
* NFS CSI
* Argo CD GitOps
* Prometheus
* Grafana
* Alertmanager
* Telegram alert notifications
* Sealed Secrets for secret management

The platform is continuously validated through infrastructure, Kubernetes, networking, storage, GitOps, monitoring, and recovery checks.

---

## Architecture

```text
                         Kubernetes API
                              |
                              v
                    Virtual IP / Load Balancing
                              |
                    +---------+---------+
                    |                   |
                   LB01                LB02
                 HAProxy             HAProxy
                Keepalived           Keepalived
                    |                   |
                    +---------+---------+
                              |
             +----------------+----------------+
             |                |                |
            CP01             CP02             CP03
             \                |                /
              \               |               /
               +--------------+--------------+
                              |
                     Kubernetes Cluster
                         /          \
                        /            \
                   Worker01        Worker02
```

The platform is built in layers:

```text
Terraform
   │
   ▼
Proxmox Infrastructure
   │
   ▼
Ansible
   │
   ├── Operating System
   ├── Load Balancers
   ├── Kubernetes Nodes
   └── Platform Components
          │
          ▼
      Kubernetes
          │
          ├── Cilium
          ├── NFS / NFS CSI
          ├── Argo CD
          └── Observability
                 │
                 ├── Prometheus
                 ├── Grafana
                 └── Alertmanager
```

Detailed architecture documentation is available under [`docs/architecture/`](docs/architecture/).

---

## Infrastructure Workflow

The project follows this general workflow:

```text
Local Development
       |
       v
Terraform Validate / Plan
       |
       v
Proxmox Infrastructure
       |
       v
Ansible
       |
       +----------------------+
       |                      |
       v                      v
OS / LB Configuration    Kubernetes Bootstrap
                              |
                              v
                     Cilium / Helm / NFS
                              |
                              v
                          Argo CD
                              |
                   +----------+----------+
                   |          |         |
                   v          v         v
                Apps     Monitoring   Storage
```

The complete development workflow continues with validation and Git:

```text
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

---

## Quick Start

This project is primarily a laboratory environment, so deployment requires access to a Proxmox environment and the required infrastructure configuration.

### 1. Clone the Repository

```bash
git clone https://github.com/wawangholanda/platform-engineering-lab.git
cd platform-engineering-lab
```

### 2. Explore the Repository

Start by understanding the main directories:

```text
platform-engineering-lab/
├── environments/
│   └── dev/
│       ├── proxmox/
│       └── kubernetes/
├── modules/
│   └── proxmox-vm/
├── ansible/
│   ├── inventory/
│   ├── roles/
│   ├── playbooks/
│   └── requirements.yml
├── kubernetes/
├── docs/
└── .github/
```

### 3. Configure the Environment

Quick Start uses a local `.env` file for credentials and environment-specific configuration.

Create it from the tracked example:

```bash
cp .env.example .env
```

Configure the required Proxmox, SSH, and Keepalived values in `.env`.
Telegram Alertmanager notifications are optional. If both
`TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` are configured, Quick Start
enables Telegram notifications automatically. If either value is empty,
Telegram configuration is skipped.

**Important:** `.env` contains secrets and must never be committed to Git.

### 4. Prepare the Workstation

The repository includes a dedicated Ansible playbook for preparing a Linux workstation used to operate the platform:

```text
ansible/playbooks/workstation.yml
```

The workstation playbook currently supports **Ubuntu and Kali Linux** and installs the base packages required by the project.

It also manages pinned versions of the main Platform Engineering CLI tools:

* Terraform
* kubectl
* Helm

The playbook uses SHA-256 checksums when downloading pinned binaries and is designed to be idempotent.

Install the required Ansible collections first:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

The repository pins the collection versions used by the project:

```yaml
collections:
  - name: kubernetes.core
    version: 6.4.0
  - name: community.general
    version: 13.0.1
  - name: ansible.posix
    version: 2.2.0
```

Validate the workstation playbook:

```bash
ansible-playbook \
  ansible/playbooks/workstation.yml \
  --syntax-check
```

Run Ansible in check mode before applying changes:

```bash
ansible-playbook \
  ansible/playbooks/workstation.yml \
  --check \
  --ask-become-pass
```

Apply the workstation configuration:

```bash
ansible-playbook \
  ansible/playbooks/workstation.yml \
  --ask-become-pass
```

The workstation automation installs the pinned tools under `/usr/local/bin`.

Verify the installed versions:

```bash
/usr/local/bin/terraform version
/usr/local/bin/kubectl version --client
/usr/local/bin/helm version --short
ansible --version
```

The workstation playbook is separate from the Kubernetes platform playbook so that the development/operations workstation can be prepared
independently from the target infrastructure.

### 5. Automated Quick Start

For the normal lab deployment workflow, run:

```bash
./quick-start.sh
```

Quick Start performs the deployment flow in order:

```text
Environment Validation
        ↓
Terraform Init
        ↓
Terraform Validate
        ↓
Terraform Plan
        ↓
Terraform Confirmation
        ↓
Terraform Apply
        ↓
Ansible Platform Configuration
        ↓
Platform Validation
```

Terraform variables are loaded from `.env` through the `TF_VAR_*` environment variables, so a `terraform.tfvars` file is not required for this workflow.

The Terraform plan is displayed before applying infrastructure changes and requires confirmation before `terraform apply` runs.

If both `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` are configured,
Quick Start automatically configures Alertmanager Telegram notifications.
If either value is empty, Telegram configuration is skipped.

The script is safe to re-run: Terraform reconciles the infrastructure state and Ansible applies the desired Kubernetes configuration.

### 6. Prepare Terraform

The Proxmox environment is located at:

```text
environments/dev/proxmox/
```

Review the example variables:

```bash
cd environments/dev/proxmox
cp terraform.tfvars.example terraform.tfvars
```

Configure the values required by your own Proxmox environment.

Initialize Terraform:

```bash
terraform init
```

Validate the configuration:

```bash
terraform validate
```

Review the planned infrastructure:

```bash
terraform plan
```

Detailed Terraform procedures are documented under [`docs/terraform/`](docs/terraform/).

### 7. Provision Infrastructure

When the Terraform plan has been reviewed:

```bash
terraform apply
```

Terraform provisions the underlying virtual infrastructure.

Return to the repository root:

```bash
cd ../../..
```

### 8. Prepare Ansible

The development inventory is:

```text
ansible/inventory/dev/hosts.yml
```

The main platform playbook is:

```text
ansible/playbooks/site.yml
```

The playbook configures the platform in stages:

```text
Load Balancers
     ↓
Kubernetes Common Configuration
     ↓
First Control Plane
     ↓
Additional Control Planes
     ↓
Helm
     ↓
Cilium
     ↓
Workers
     ↓
NFS
     ↓
NFS CSI
     ↓
Argo CD
     ↓
GitOps Bootstrap
     ↓
etcd Backup
     ↓
Platform Validation
```

Before applying changes, validate the playbook:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --syntax-check
```

For a detailed Ansible workflow, see [`docs/ansible/`](docs/ansible/).

### 9. Configure the Kubernetes Platform

Run the main Ansible platform playbook after the inventory and infrastructure have been configured:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml
```

The playbook is designed to configure the Kubernetes platform through reusable Ansible roles.

Control-plane operations that can affect cluster availability are executed serially where appropriate.

### 10. Enable GitOps

Argo CD is installed and bootstrapped by the Ansible platform workflow.

After GitOps is configured, Kubernetes resources can be managed from Git rather than manually applying every application manifest.

Detailed GitOps procedures are available under [`docs/gitops/`](docs/gitops/).

### 11. Validate the Platform

The platform includes automated validation for areas such as:

* Kubernetes node readiness
* Kubernetes API availability
* Cilium health
* Gateway API
* HTTPRoute
* NFS StorageClass
* Argo CD
* Monitoring
* Prometheus
* etcd backup
* End-to-end platform health

The repository also contains Kubernetes integration and failure tests under [`kubernetes/tests/`](kubernetes/tests/).

Detailed validation procedures are documented under [`docs/operations/`](docs/operations/).

---

## Repository Structure

```text
platform-engineering-lab/
│
├── environments/
│   └── dev/
│       ├── proxmox/             # Proxmox Terraform environment
│       └── kubernetes/          # Environment Kubernetes resources
│
├── modules/
│   └── proxmox-vm/              # Reusable Terraform VM module
│
├── ansible/
│   ├── inventory/               # Environment inventories
│   ├── roles/                   # Reusable Ansible roles
│   ├── playbooks/               # Platform and workstation playbooks
│   └── requirements.yml         # Pinned Ansible collections
│
├── kubernetes/
│   ├── storage/                 # Kubernetes storage resources
│   └── tests/                   # Platform and failure tests
│
├── docs/
│   ├── architecture/
│   ├── proxmox/
│   ├── kubernetes/
│   ├── ansible/
│   ├── terraform/
│   ├── gitops/
│   ├── observability/
│   └── operations/
│
├── .github/                     # GitHub workflows
├── .gitignore
├── .pre-commit-config.yaml
├── LICENSE
└── README.md
```

---

## Current Status

The core platform implementation is operational and includes:

* Infrastructure provisioning
* Configuration management
* Highly available Kubernetes
* Cilium networking
* Gateway API
* Persistent storage
* GitOps
* Observability
* Platform validation
* Failure testing
* etcd backup
* Disaster recovery procedures
* Cluster reconstruction validation
* Reproducible workstation preparation

The project continues to evolve as additional platform engineering capabilities are implemented.

---

## Roadmap

### Completed

* [x] Infrastructure provisioning with Terraform + Proxmox
* [x] Reusable Terraform VM module
* [x] Idempotent Ansible automation
* [x] Reproducible workstation preparation with Ansible
* [x] Pinned Terraform, kubectl, and Helm tooling
* [x] Highly available Kubernetes
* [x] HAProxy + Keepalived
* [x] Cilium networking and Gateway API
* [x] Persistent storage with NFS / NFS CSI
* [x] GitOps with Argo CD
* [x] Prometheus, Grafana, and Alertmanager
* [x] Platform validation
* [x] Worker and control-plane failure testing
* [x] etcd backup and restore testing
* [x] Disaster recovery procedures
* [x] Kubernetes cluster reconstruction validation
* [x] Secrets management
* [x] Infrastructure failure alerting
* [x] Alert notification integration

### In Progress

* [ ] Production-oriented Grafana dashboards
* [ ] Kubernetes security baseline
* [ ] Cilium NetworkPolicy
* [ ] RBAC hardening
* [ ] Image vulnerability scanning
* [ ] Automated failure scenarios

### Planned

* [ ] Tailscale private access
* [ ] HA Tailscale access through lb01/lb02
* [ ] Private Grafana access validation
* [ ] Private Argo CD access validation
* [ ] GitHub Actions / CI/CD automation
* [ ] Terraform CI/CD
* [ ] Ansible CI/CD
* [ ] Automated infrastructure testing
* [ ] AWS
* [ ] Google Cloud
* [ ] Alibaba Cloud
* [ ] Additional infrastructure platforms

See the [`docs/`](docs/) directory for implementation-level details and operational procedures.

---

## Documentation

The README provides the high-level project overview.

Detailed technical documentation is organized under:

| Area          | Documentation                                |
| ------------- | -------------------------------------------- |
| Architecture  | [`docs/architecture/`](docs/architecture/)   |
| Proxmox       | [`docs/proxmox/`](docs/proxmox/)             |
| Terraform     | [`docs/terraform/`](docs/terraform/)         |
| Ansible       | [`docs/ansible/`](docs/ansible/)             |
| Kubernetes    | [`docs/kubernetes/`](docs/kubernetes/)       |
| GitOps        | [`docs/gitops/`](docs/gitops/)               |
| Observability | [`docs/observability/`](docs/observability/) |
| Operations    | [`docs/operations/`](docs/operations/)       |

Use the README to understand **what the project is**.

Use the documentation to understand **how the project works**.

---

## Development Workflow

Changes are intended to follow a repeatable workflow:

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

Pre-commit hooks are used to maintain repository consistency and detect common issues before changes are committed.

---

## Security

Secrets, credentials, private keys, and other sensitive configuration must never be committed to the repository.

Sensitive values should remain outside version control and be excluded through `.gitignore`.

Example:

```text
.env
*.tfvars
*.tfstate
*.tfstate.*
```

Example configuration files should contain placeholder values only.

Security implementation and future hardening work are documented under [`docs/`](docs/).

---

## Support the Project

If this project helps you learn Platform Engineering, build your own
infrastructure laboratory, or explore Kubernetes automation, you can
support its continued development.

### 🇮🇩 Indonesia

Support via QRIS:

![QRIS support](assets/qris.png)

Scan the QRIS code to support the project.

### 🌎 International

International supporters can use Ko-fi:

[☕ Support via Ko-fi](https://ko-fi.com/wawangholanda)

Thank you for supporting open-source learning and continued development of the project.

---

## Purpose

This project is a practical Platform Engineering laboratory and portfolio focused on:

* Reproducible infrastructure
* Infrastructure as Code
* Configuration management
* Highly available systems
* Kubernetes
* Automation
* GitOps
* Observability
* Security
* Reliability
* Disaster recovery
* Multi-platform infrastructure

The long-term goal is to evolve the laboratory from a Proxmox-based Kubernetes environment into a broader multi-platform Platform Engineering environment.

---

## License

See [`LICENSE`](LICENSE).
