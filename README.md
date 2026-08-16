# Platform Engineering Lab

A hands-on Platform Engineering laboratory for building, automating,
and operating infrastructure across multiple platforms.

## Overview

This project explores Infrastructure as Code, configuration management,
Kubernetes, GitOps, observability, and security using reproducible
automation.

The project is designed to support multiple infrastructure platforms:

- Proxmox
- AWS
- Google Cloud
- Alibaba Cloud
- Future platforms

## Current Implementation

### Proxmox → Highly Available Kubernetes

The first implementation provisions and configures a highly available
Kubernetes cluster on Proxmox.

Current stack:

- Terraform — infrastructure provisioning
- Ansible — configuration management
- Kubernetes 1.34
- containerd
- Cilium
- HAProxy
- Keepalived
- Helm

Architecture:

```text
                    Kubernetes API
                    Virtual IP
                         |
                  +------+------+
                  |             |
                LB01          LB02
              HAProxy       HAProxy
             Keepalived     Keepalived
                  |             |
                  +------+------+
                         |
              +----------+----------+
              |          |          |
             CP01       CP02       CP03
              |
          +---+---+
          |       |
        Worker1 Worker2

## Repository Structure
platform-engineering-lab/
├── environments/     # Environment-specific Terraform
├── modules/          # Reusable Terraform modules
├── ansible/          # Configuration management
├── kubernetes/       # Kubernetes platform components
├── docs/             # Technical documentation
└── .github/          # CI/CD workflows

## Workflow
Terraform
    ↓
Infrastructure
    ↓
Ansible
    ↓
Kubernetes
    ↓
GitOps / Platform Services


## Roadmap
Terraform + Proxmox
HA Kubernetes cluster
Ansible automation
HAProxy + Keepalived
Cilium
Helm
Argo CD
Monitoring
Logging
Security
GitHub Actions
Atlantis
AWS
Google Cloud
Alibaba Cloud


## Security

Secrets and credentials are never committed to the repository.

Sensitive configuration is stored locally and excluded using .gitignore.

See the documentation for details.

Documentation
Architecture

Proxmox

Kubernetes

Ansible

Roadmap

## Purpose

This project is a practical Platform Engineering laboratory and portfolio,
focused on reproducible, automated, highly available, and scalable
infrastructure.

License

See LICENSE

.
