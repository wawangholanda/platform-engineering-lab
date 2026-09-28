# Ansible Architecture

## Overview

Ansible is the configuration management and Kubernetes bootstrap layer
of the Platform Engineering Lab.

Terraform provisions the infrastructure, while Ansible configures the
operating systems, load balancers, Kubernetes cluster, storage, GitOps,
and platform validation.

The main goals are:

* Reproducible configuration
* Idempotent execution
* Reusable roles
* Environment-specific inventory
* Safe Kubernetes bootstrap
* Automated platform validation

## Automation Flow

```text
Proxmox Bootstrap
        |
        +---------------------------+
        |                           |
        v                           v
Terraform API User             VM Template 9000
Role + ACL + Token             Ubuntu 24.04
        |                           |
        +-------------+-------------+
                      |
                      v
                  Terraform
                      |
                      v
                 Proxmox VMs
                      |
                      v
               Ansible Inventory
                      |
        +-------------+-------------+
        |                           |
        v                           v
  Load Balancers              Kubernetes Nodes
        |                           |
        v                           v
 HAProxy + Keepalived        kubeadm / Kubernetes
                                    |
                         +----------+----------+
                         |          |          |
                         v          v          v
                       Cilium     Helm      NFS / CSI
                         |          |          |
                         +----------+----------+
                                    |
                                    v
                                 Argo CD
                                    |
                                    v
                              GitOps Resources
                                    |
                                    v
                           Monitoring / Apps
                                    |
                                    v
                         Automated Validation
```

The Proxmox bootstrap stage prepares the Proxmox API access and the
Ubuntu VM template required by Terraform.

The Kubernetes and platform configuration stage is executed by:

```text
ansible/playbooks/site.yml
```

The Proxmox bootstrap stage is executed separately by:

```text
ansible/playbooks/proxmox-bootstrap.yml
```

Cluster reconstruction safety and controlled reset are handled separately
by:

```text
ansible/playbooks/cluster-reconstruct.yml
```

## Repository Structure

```text
ansible/

├── inventory/
│   └── dev/
│       ├── hosts.yml
│       └── group_vars/
│           ├── k8s.yml
│           └── load_balancer/
│               └── main.yml
│
├── roles/
│   ├── argocd/
│   ├── argocd_bootstrap/
│   ├── cilium/
│   ├── etcd_backup/
│   ├── helm/
│   ├── k8s_common/
│   ├── k8s_control_plane/
│   ├── k8s_control_plane_join/
│   ├── k8s_control_plane_metrics/
│   ├── k8s_reset/
│   ├── k8s_validation/
│   ├── k8s_worker/
│   ├── kubeconfig/
│   ├── load_balancer/
│   ├── nfs_csi/
│   ├── nfs_server/
│   └── proxmox_bootstrap/
│
├── playbooks/
│   ├── cluster-reconstruct.yml
│   ├── proxmox-bootstrap.yml
│   └── site.yml
│
├── requirements.yml
└── ansible.cfg
```

The Ansible automation is divided into three operational stages.

The Proxmox bootstrap stage prepares the Proxmox environment required by
Terraform:

```text
ansible/playbooks/proxmox-bootstrap.yml
        |
        v
proxmox_bootstrap role
        |
        +-- Terraform API user
        +-- Terraform role
        +-- API token
        +-- ACL
        +-- Ubuntu VM template
```

The platform configuration stage is executed through:

```text
ansible/playbooks/site.yml
```

It configures the Kubernetes cluster and supporting platform services
using reusable Ansible roles.

The cluster reconstruction stage is executed through:

```text
ansible/playbooks/cluster-reconstruct.yml
```

It provides a safety gate for persistent Kubernetes resources and
includes the controlled `k8s_reset` role. The reset is disabled by
default and requires explicit confirmation.

## Inventory

The development inventory groups hosts by function:

```text
all
├── proxmox
│   └── pve
│
├── k8s
│   ├── control_plane
│   │   ├── k8s-cp01
│   │   ├── k8s-cp02
│   │   └── k8s-cp03
│   └── workers
│       ├── k8s-worker01
│       └── k8s-worker02
│
├── load_balancer
│   ├── k8s-lb01
│   └── k8s-lb02
│
└── nfs
    └── k8s-nfs01
```

The `proxmox` group is used by the Proxmox bootstrap playbook.

The Kubernetes, load-balancer, and NFS groups are used by the platform
configuration playbook.

| Host         | Role          | IP           |
| ------------ | ------------- | ------------ |
| pve          | Proxmox Host  | 192.168.1.11 |
| k8s-cp01     | Control Plane | 192.168.1.20 |
| k8s-worker01 | Worker        | 192.168.1.21 |
| k8s-worker02 | Worker        | 192.168.1.22 |
| k8s-cp02     | Control Plane | 192.168.1.23 |
| k8s-cp03     | Control Plane | 192.168.1.24 |
| k8s-lb01     | Load Balancer | 192.168.1.25 |
| k8s-lb02     | Load Balancer | 192.168.1.26 |
| k8s-nfs01    | NFS Server    | 192.168.1.27 |

## Group Variables

Environment-specific configuration is stored under:

```text
ansible/inventory/dev/group_vars/
```

Kubernetes variables include:

* Kubernetes version
* Pod CIDR
* Control-plane endpoint
* Cilium version
* Helm version
* GitOps repository
* GitOps revision
* Application definitions

The Kubernetes API endpoint is:

```text
192.168.1.30:6443
```

Group variables keep environment-specific values separate from reusable
automation logic.

## Roles

| Role                        | Responsibility                                     |
| --------------------------- | -------------------------------------------------- |
| `proxmox_bootstrap`         | Proxmox Terraform prerequisites and VM template    |
| `k8s_common`                | Common node and Kubernetes prerequisites           |
| `k8s_control_plane`         | First control-plane bootstrap                      |
| `kubeconfig`                | Workstation kubeconfig configuration               |
| `k8s_control_plane_join`    | Additional control-plane nodes                     |
| `k8s_control_plane_metrics` | Control-plane metrics endpoints                    |
| `k8s_worker`                | Worker node joins                                  |
| `load_balancer`             | HAProxy and Keepalived                             |
| `cilium`                    | Kubernetes CNI                                     |
| `helm`                      | Helm installation                                  |
| `nfs_server`                | NFS server configuration                           |
| `nfs_csi`                   | NFS CSI integration                                |
| `argocd`                    | Argo CD installation                               |
| `argocd_bootstrap`          | GitOps bootstrap                                   |
| `etcd_backup`               | Automated etcd backup and isolated restore tooling |
| `k8s_validation`            | Automated Kubernetes platform validation           |
| `k8s_reset`                 | Controlled Kubernetes reset for reconstruction     |

The `k8s_reset` role is not part of the normal `site.yml` execution.
It is explicitly included by `cluster-reconstruct.yml`.

## Main Playbooks

Ansible uses separate playbooks for infrastructure bootstrap, platform
configuration, and cluster reconstruction.

### Proxmox Bootstrap

The Proxmox bootstrap playbook is:

```text
ansible/playbooks/proxmox-bootstrap.yml
```

Its purpose is to prepare the Proxmox environment required by Terraform.

The bootstrap process configures:

```text
Terraform API User
        |
        v
Terraform Role
        |
        v
API Token
        |
        v
ACL
        |
        v
Ubuntu VM Template
        |
        v
Ready for Terraform
```

The bootstrap playbook targets the `proxmox` inventory group.

### Platform Configuration

The main platform playbook is:

```text
ansible/playbooks/site.yml
```

The execution order follows the orchestration defined in `site.yml`:

```text
Load Balancers
      |
      v
Common Node Configuration
      |
      v
First Control Plane
      |
      v
Workstation Kubeconfig
      |
      v
Additional Control Planes
      |
      v
Control-Plane Metrics
      |
      v
Helm
      |
      v
Cilium
      |
      v
Workers
      |
      v
NFS Server
      |
      v
NFS CSI
      |
      v
Argo CD
      |
      v
GitOps Bootstrap
      |
      v
etcd Backup
      |
      v
Kubernetes Platform Validation
```

Each platform role is exposed through a matching tag:

```text
load_balancer

k8s_common

k8s_control_plane

kubeconfig

k8s_control_plane_join

k8s_control_plane_metrics

helm

cilium

k8s_worker

nfs_server

nfs_csi

argocd

argocd_bootstrap

etcd_backup

k8s_validation
```

The Proxmox bootstrap playbook has its own tag:

```text
proxmox_bootstrap
```

The complete platform deployment is executed without `--tags`. Tags are
intended for targeted operational changes and validation.

The `kubeconfig` role runs after the first control plane is bootstrapped
and prepares the workstation kubeconfig.

The `etcd_backup` role configures the automated etcd backup service and
timer.

The `k8s_validation` role performs automated platform validation after
the platform components have been configured.

### Cluster Reconstruction

The cluster reconstruction playbook is:

```text
ansible/playbooks/cluster-reconstruct.yml
```

Its purpose is to provide a safety gate before a controlled Kubernetes
reconstruction.

The workflow is:

```text
Check Existing PV/PVC
        |
        v
Persistent Storage Exists?
      /     \
    Yes      No
     |        |
     v        v
Stop /     Safety Gate
Require       Pass
Explicit        |
Approval        v
              k8s_reset
```

The reconstruction playbook checks existing PersistentVolume and
PersistentVolumeClaim resources before including the `k8s_reset` role.

The persistent-data override is disabled by default:

```yaml
reconstruction_allow_persistent_data: false
```

The Kubernetes reset confirmation is also disabled by default:

```yaml
k8s_reset_confirm: false
```

These controls prevent an ordinary reconstruction run from accidentally
resetting a cluster containing persistent resources.

## Ansible Execution

### Proxmox Bootstrap Procedure

Run the Proxmox bootstrap:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/proxmox-bootstrap.yml
```

Run the Proxmox bootstrap in check mode:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/proxmox-bootstrap.yml \
  --check
```

Run the bootstrap role using its tag:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/proxmox-bootstrap.yml \
  --tags proxmox_bootstrap
```

### Platform Configuration Procedure

Run the complete platform automation:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml
```

Run a specific role:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --tags cilium
```

Run multiple roles:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --tags "helm,argocd,argocd_bootstrap"
```

Run automated etcd backup configuration independently:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --tags etcd_backup
```

Run platform validation independently:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --tags k8s_validation
```

List available tags:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --list-tags
```

List tasks for a specific role:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --tags cilium \
  --list-tasks
```

The full platform deployment is executed without `--tags`. Tags are
intended for targeted operational changes.

### Cluster Reconstruction Procedure

Run the reconstruction safety gate without enabling destructive reset:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/cluster-reconstruct.yml
```

The controlled reset must only be enabled explicitly when the
reconstruction procedure has confirmed that persistent application data
is protected:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/cluster-reconstruct.yml \
  -e k8s_reset_confirm=true
```

The persistent-data override is a separate safety control and should only
be enabled when application-data recovery has been explicitly reviewed.

## Idempotency

Ansible roles are designed to converge on the desired state when
executed repeatedly.

Check mode can be used for both the Proxmox bootstrap and platform
configuration playbooks.

For Proxmox bootstrap:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/proxmox-bootstrap.yml \
  --check
```

For platform configuration:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --check
```

After the desired state is present, repeated execution should produce no
unexpected changes.

```text
changed=0
failed=0
```

Idempotency is especially important for the Proxmox bootstrap because
the same automation may be executed when reconstructing the
infrastructure on an existing Proxmox host.

## Control Plane Safety

Kubernetes control-plane components run as static Pods.

Their manifests are located under:

```text
/etc/kubernetes/manifests/
```

Because kubelet watches this directory directly:

* Control-plane changes should be executed serially.
* Manifest changes should be validated before applying them.
* Backup files must not be stored inside the static Pod directory.
* etcd should be checked before troubleshooting kube-apiserver.
* etcd quorum should be understood before destructive recovery.

Control-plane changes use:

```yaml
serial: 1
```

The `k8s_control_plane_metrics` role also runs serially to reduce the risk
of simultaneous control-plane changes.

## Validation

### Syntax Check

Validate the Proxmox bootstrap playbook:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/proxmox-bootstrap.yml \
  --syntax-check
```

Validate the platform playbook:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --syntax-check
```

Validate the reconstruction playbook:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/cluster-reconstruct.yml \
  --syntax-check
```

### Ansible Lint

Run Ansible linting:

```bash
ansible-lint
```

The repository uses Ansible linting as part of the development validation
workflow.

### Check Mode

Validate the Proxmox bootstrap without applying changes:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/proxmox-bootstrap.yml \
  --check
```

Validate the platform configuration without applying changes:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --check
```

### Kubernetes

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

### Monitoring

Prometheus readiness:

```bash
curl -s http://localhost:9091/-/ready
```

Target health:

```bash
curl -s http://localhost:9091/api/v1/targets |
  jq '[.data.activeTargets[] | select(.health != "up")] | length'
```

Expected:

```text
0
```

The `k8s_validation` role provides automated validation of Kubernetes
nodes, API health, Cilium, Gateway API, HTTPRoutes, storage, Argo CD,
Prometheus, monitoring, and etcd backup state.

## Operational Workflow

The infrastructure lifecycle is divided into infrastructure bootstrap,
infrastructure provisioning, platform configuration, GitOps deployment,
and validation.

### 1. Bootstrap Proxmox

Prepare the Proxmox host for Terraform:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/proxmox-bootstrap.yml
```

This prepares:

* Terraform API user
* Terraform role
* API token
* ACL
* Ubuntu VM template

### 2. Provision Infrastructure

Terraform provisions the virtual machines from the prepared Proxmox
environment.

```text
Terraform
    |
    v
Proxmox
    |
    v
Kubernetes VMs
```

### 3. Configure the Platform

Run the main Ansible playbook:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml
```

This configures:

* Load balancers
* Kubernetes nodes
* Workstation kubeconfig
* Cilium
* Helm
* NFS / CSI
* Argo CD
* GitOps bootstrap
* etcd backup
* Platform validation

### 4. Validate the Environment

Validate the resulting Kubernetes platform:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

Then verify monitoring and platform health according to the validation
procedures.

The automated validation role can also be executed independently:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --tags k8s_validation
```

### 5. Cluster Reconstruction

For a full Kubernetes reconstruction, use:

```text
cluster-reconstruct.yml
        |
        v
Safety Gate
        |
        v
Controlled Reset
        |
        v
site.yml
        |
        v
Kubernetes Platform
        |
        v
GitOps
        |
        v
Validation
```

The reconstruction procedure is destructive and must be treated
separately from normal platform configuration.

### 6. Ongoing Operations

For routine changes, use Ansible tags to target the required component
instead of re-running unrelated roles.

Examples:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --tags cilium
```

or:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --tags load_balancer
```

The Proxmox bootstrap playbook is normally executed when preparing or
reconstructing the Proxmox environment. The platform playbook is used
for Kubernetes and platform configuration.

## Design Principles

### Infrastructure and Configuration Separation

Terraform is responsible for infrastructure provisioning, while Ansible
is responsible for configuration and platform bootstrap.

```text
Terraform
    |
    v
Infrastructure

Ansible
    |
    v
Configuration + Platform
```

This separation keeps infrastructure lifecycle and configuration
management independently reproducible.

### Bootstrap Before Provisioning

The Proxmox environment must be prepared before Terraform provisioning.

```text
Proxmox Bootstrap
        |
        v
Terraform Prerequisites
        |
        v
Terraform Provisioning
```

This ensures that Terraform does not depend on manually created API
users, permissions, tokens, or VM templates.

### Reusable Roles

Configuration is implemented using reusable Ansible roles rather than
large monolithic task files.

Each role has a focused responsibility and can be executed independently
when operational changes are required.

### Idempotent Automation

Roles should converge on the desired state and remain safe to execute
multiple times.

Changes should be predictable and should not depend on whether the
environment was created manually or through automation.

### Environment-Specific Configuration

Environment-specific values belong in inventory and group variables,
while reusable configuration logic remains inside roles.

This allows the same automation structure to support additional
environments without duplicating role implementations.

### Safe Kubernetes Bootstrap

Kubernetes bootstrap operations are separated between:

* Initial control-plane creation
* Workstation kubeconfig configuration
* Additional control-plane joins
* Worker joins
* Cluster networking
* Storage integration
* GitOps bootstrap
* Platform validation

This separation reduces the risk of accidentally re-running destructive
cluster initialization tasks.

### Controlled Reconstruction

Cluster reconstruction is intentionally separated from the normal
platform deployment.

The reconstruction playbook checks persistent Kubernetes resources
before invoking the controlled reset role. Destructive reset requires
explicit confirmation.

This provides a safety boundary between normal idempotent configuration
and destructive recovery operations.

### GitOps as the Application Delivery Layer

Ansible bootstraps the platform and Argo CD, while GitOps manages
Kubernetes application configuration.

```text
Ansible
    |
    v
Argo CD
    |
    v
Git Repository
    |
    v
Kubernetes Applications
```

This keeps infrastructure and platform bootstrap automation separate
from ongoing application delivery.

### Automated Validation

Platform validation is implemented as an Ansible role:

```text
ansible/roles/k8s_validation/
```

The validation role is executed at the end of the normal platform
playbook and can also be targeted independently.

This makes validation part of the automation workflow rather than only
a manual post-deployment activity.

## Future Improvements

Potential improvements to the Ansible automation include:

* Expand automated infrastructure validation after Terraform provisioning
* Add automated failure-scenario testing for Kubernetes components
* Improve automated validation of HAProxy and Keepalived failover
* Add automated verification of NFS and CSI functionality
* Expand disaster-recovery automation and validation
* Add additional environment inventories beyond `dev`
* Improve secret management for bootstrap credentials and API tokens
* Integrate more Ansible validation into CI/CD
* Improve reporting of configuration drift and validation results

Future improvements should preserve the existing separation between
infrastructure provisioning, configuration management, and GitOps
application delivery.

## Related Documentation

### Infrastructure

* [Terraform Architecture](../terraform/architecture.md)

### Kubernetes Documentation

* [Kubernetes HA Architecture](../architecture/kubernetes-ha.md)
* [Cluster Bootstrap](../kubernetes/cluster-bootstrap.md)
* [Cilium Networking](../kubernetes/networking-cilium.md)
* [NFS Storage](../kubernetes/storage-nfs.md)

### GitOps and Platform

* [Argo CD](../gitops/argocd.md)
* [Prometheus](../observability/prometheus.md)

### Validation and Operations

* [Validation](../operations/validation.md)
* [Control Plane Failure](../operations/control-plane-failure.md)
* [Disaster Recovery](../operations/disaster-recovery.md)
* [Startup and Shutdown](../operations/startup-shutdown.md)

### Disaster Recovery

* [Kubernetes Disaster Recovery Runbook](../disaster-recovery/kubernetes-disaster-recovery-runbook.md)
* [Control Plane Node Recovery](../disaster-recovery/control-plane-node-recovery.md)
* [Worker Node Recovery](../disaster-recovery/worker-node-recovery.md)
* [etcd Restore Runbook](../disaster-recovery/etcd-restore-runbook.md)
* [etcd Backup and Restore](../operations/etcd-backup-and-restore.md)

The documentation is organized around the same lifecycle as the
automation:

```text
Infrastructure
      |
      v
Kubernetes
      |
      v
Platform Services
      |
      v
GitOps
      |
      v
Automated Validation
      |
      v
Operations and Disaster Recovery
```
