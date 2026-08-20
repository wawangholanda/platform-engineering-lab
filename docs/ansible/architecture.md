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
│   ├── site.yml
│   ├── helm.yml
│   ├── control-plane-metrics.yml
│   ├── argocd-bootstrap.yml
│   ├── nfs.yml
│   └── nfs-csi.yml
│
├── requirements.yml
└── ansible.cfg
```

## Inventory

The development inventory groups hosts by their function:

```text
all
└── k8s
    ├── control_plane
    │   ├── k8s-cp01
    │   ├── k8s-cp02
    │   └── k8s-cp03
    └── workers
        ├── k8s-worker01
        └── k8s-worker02
```

Load balancers are maintained as a separate group.

| Host | Role | IP |
|---|---|---|
| k8s-cp01 | Control Plane | 192.168.1.20 |
| k8s-worker01 | Worker | 192.168.1.21 |
| k8s-worker02 | Worker | 192.168.1.22 |
| k8s-cp02 | Control Plane | 192.168.1.23 |
| k8s-cp03 | Control Plane | 192.168.1.24 |
| k8s-lb01 | Load Balancer | 192.168.1.25 |
| k8s-lb02 | Load Balancer | 192.168.1.26 |

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

The main roles are:

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

The main playbook is:

```text
ansible/playbooks/site.yml
```

High-level execution order:

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

Targeted playbooks are used for isolated operational changes.

Examples:

```text
ansible/playbooks/helm.yml
ansible/playbooks/control-plane-metrics.yml
```

## Idempotency

Roles are designed to converge on the desired state when executed
repeatedly.

Check mode:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/<playbook>.yml \
  --check
```

After the desired state is already present, a repeated run should
produce no unexpected changes.

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

Control-plane configuration changes use:

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
  ansible/playbooks/<playbook>.yml \
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

The recommended workflow is:

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
Targeted Playbook
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

Targeted playbooks should be preferred for isolated changes instead of
re-running the full bootstrap process unnecessarily.

## Design Principles

The Ansible implementation follows these principles:

- Reusable logic belongs in roles.
- Environment-specific values belong in inventory and group variables.
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
