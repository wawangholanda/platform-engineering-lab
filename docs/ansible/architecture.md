# Ansible Architecture

## Overview

Ansible is the configuration management and Kubernetes bootstrap layer
of the Platform Engineering Lab.

Terraform provisions the infrastructure, while Ansible configures the
operating systems, load balancers, Kubernetes cluster, storage, GitOps,
and monitoring components.

The main goals are:

- Reproducible configuration
- Idempotent execution
- Reusable roles
- Environment-specific inventory
- Safe Kubernetes bootstrap

## Automation Flow

```text
Terraform
    |
    v
Proxmox VMs
    |
    v
Ansible Inventory
    |
    +----------------------+
    |                      |
    v                      v
Load Balancers        Kubernetes Nodes
    |                      |
    v                      v
HAProxy + Keepalived   kubeadm / Kubernetes
                           |
                +----------+----------+
                |          |          |
                v          v          v
              Cilium     Helm      NFS / CSI
                                      |
                                      v
                                    Argo CD
                                      |
                                      v
                              GitOps / Monitoring
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
│   ├── helm/
│   ├── k8s_common/
│   ├── k8s_control_plane/
│   ├── k8s_control_plane_join/
│   ├── k8s_control_plane_metrics/
│   ├── k8s_worker/
│   ├── load_balancer/
│   ├── nfs_csi/
│   └── nfs_server/
│
├── playbooks/
│   └── site.yml
│
├── requirements.yml
└── ansible.cfg
```

`site.yml` is the single Ansible entry point. Role-specific execution
is controlled using Ansible tags.

## Inventory

The development inventory groups hosts by function:

```text
all
├── k8s
│   ├── control_plane
│   │   ├── k8s-cp01
│   │   ├── k8s-cp02
│   │   └── k8s-cp03
│   └── workers
│       ├── k8s-worker01
│       └── k8s-worker02
├── load_balancer
│   ├── k8s-lb01
│   └── k8s-lb02
└── nfs
    └── k8s-nfs01
```

| Host | Role | IP |
|---|---|---|
| k8s-cp01 | Control Plane | 192.168.1.20 |
| k8s-worker01 | Worker | 192.168.1.21 |
| k8s-worker02 | Worker | 192.168.1.22 |
| k8s-cp02 | Control Plane | 192.168.1.23 |
| k8s-cp03 | Control Plane | 192.168.1.24 |
| k8s-lb01 | Load Balancer | 192.168.1.25 |
| k8s-lb02 | Load Balancer | 192.168.1.26 |
| k8s-nfs01 | NFS Server | 192.168.1.27 |

## Group Variables

Environment-specific configuration is stored under:

```text
ansible/inventory/dev/group_vars/
```

Kubernetes variables include:

- Kubernetes version
- Pod CIDR
- Control-plane endpoint
- Cilium version
- Helm version
- GitOps repository
- GitOps revision
- Application definitions

The Kubernetes API endpoint is:

```text
192.168.1.30:6443
```

Group variables keep environment-specific values separate from reusable
automation logic.

## Roles

| Role | Responsibility |
|---|---|
| `k8s_common` | Common node and Kubernetes prerequisites |
| `k8s_control_plane` | First control-plane bootstrap |
| `k8s_control_plane_join` | Additional control-plane nodes |
| `k8s_control_plane_metrics` | Control-plane metrics endpoints |
| `k8s_worker` | Worker node joins |
| `load_balancer` | HAProxy and Keepalived |
| `cilium` | Kubernetes CNI |
| `helm` | Helm installation |
| `nfs_server` | NFS server configuration |
| `nfs_csi` | NFS CSI integration |
| `argocd` | Argo CD installation |
| `argocd_bootstrap` | GitOps bootstrap |

## Main Playbook

The single entry point is:

```text
ansible/playbooks/site.yml
```

The execution order is:

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
NFS / CSI
      |
      v
Argo CD
      |
      v
GitOps Bootstrap
```

Each role is exposed through a matching tag:

```text
load_balancer
k8s_common
k8s_control_plane
k8s_control_plane_join
k8s_control_plane_metrics
helm
cilium
k8s_worker
nfs_server
nfs_csi
argocd
argocd_bootstrap
```

## Ansible Execution

Run the complete automation:

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

The full deployment is executed without `--tags`. Tags are intended for
targeted operational changes.

## Idempotency

Roles are designed to converge on the desired state when executed
repeatedly.

Check mode:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --check
```

After the desired state is present, repeated execution should produce
no unexpected changes.

```text
changed=0
failed=0
```

## Control Plane Safety

Kubernetes control-plane components run as static Pods.

Their manifests are located under:

```text
/etc/kubernetes/manifests/
```

Because kubelet watches this directory directly:

- Control-plane changes should be executed serially.
- Manifest changes should be validated before applying them.
- Backup files must not be stored inside the static Pod directory.
- etcd should be checked before troubleshooting kube-apiserver.
- etcd quorum should be understood before destructive recovery.

Control-plane changes use:

```yaml
serial: 1
```

## Validation

### Syntax Check

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --syntax-check
```

### Check Mode

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

## Operational Workflow

```text
Change
  |
  v
Git Diff
  |
  v
Ansible Syntax Check
  |
  v
Check Mode
  |
  v
Full or Targeted Execution
  |
  v
Kubernetes Validation
  |
  v
Monitoring Validation
  |
  v
Git Commit
```

Use tagged execution for isolated changes and full execution when the
complete automation workflow is required.

## Design Principles

- Reusable logic belongs in roles.
- Environment-specific values belong in inventory and group variables.
- `site.yml` is the single Ansible entry point.
- Tags provide targeted role execution.
- Cluster-affecting changes are validated before application.
- Control-plane changes are performed serially.
- Idempotency is a primary design goal.
- Git remains the source of truth for persistent configuration.
- Emergency manual changes should be reflected back into automation.

## Future Improvements

- [ ] Ansible linting
- [ ] Automated Ansible validation in CI
- [ ] Molecule testing
- [ ] Inventory validation
- [ ] Improved check-mode coverage
- [ ] Automated post-deployment validation
- [ ] Failure scenario testing
- [ ] Secret management integration
- [ ] Multi-environment inventories
- [ ] Reusable platform role abstractions

## Related Documentation

```text
docs/
├── architecture/
│   └── kubernetes-ha.md
├── ansible/
│   └── architecture.md
├── terraform/
│   └── architecture.md
├── kubernetes/
│   ├── cluster-bootstrap.md
│   ├── networking-cilium.md
│   └── storage-nfs.md
├── gitops/
│   └── argocd.md
├── observability/
│   └── prometheus.md
└── operations/
    ├── startup-shutdown.md
    ├── validation.md
    └── control-plane-failure.md
```
