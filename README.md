# Platform Engineering Lab

Repository portfolio untuk eksperimen dan implementasi Infrastructure as Code (IaC), Kubernetes, dan Cloud Platform Engineering.

## Overview

Project ini berisi implementasi:

- Terraform
- Kubernetes
- Proxmox
- AWS
- Google Cloud Platform
- Alibaba Cloud
- Helm
- Ansible
- Atlantis
- GitHub Actions
- GitOps dengan ArgoCD

## Architecture

```text
Infrastructure
      |
      v
Terraform
      |
      v
Kubernetes Cluster
      |
      v
GitOps (ArgoCD)
      |
      +----------------+
      |                |
      v                v
 Monitoring        Security
 Prometheus        Kyverno
 Grafana           Falco
 Loki              Cert Manager
