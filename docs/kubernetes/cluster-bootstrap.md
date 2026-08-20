# Kubernetes Cluster Bootstrap

## Overview

The Kubernetes cluster is provisioned on Proxmox using Terraform and
bootstrapped with Ansible.

Terraform manages the infrastructure layer, while Ansible configures
the operating system and initializes the Kubernetes platform.

## Bootstrap Flow

```text
Terraform
    |
    v
Proxmox VMs
    |
    v
Ansible Common Configuration
    |
    v
First Control Plane
    |
    v
Additional Control Planes
    |
    v
Workers
    |
    v
Cilium
    |
    v
Storage / Helm / Argo CD
    |
    v
GitOps / Monitoring
```

## Cluster Configuration

| Component | Value |
|---|---|
| Kubernetes | 1.34.10 |
| kubeadm | 1.34.10 |
| kubelet | 1.34.10 |
| containerd | 2.2.1 |
| OS | Ubuntu 24.04.4 LTS |
| CNI | Cilium 1.20.0 |
| Pod CIDR | 10.0.0.0/16 |
| Service CIDR | 10.96.0.0/12 |
| Cluster DNS | 10.96.0.10 |
| API Endpoint | 192.168.1.30:6443 |

## Node Topology

| Host | Role | IP |
|---|---|---|
| k8s-cp01 | Control Plane | 192.168.1.20 |
| k8s-cp02 | Control Plane | 192.168.1.23 |
| k8s-cp03 | Control Plane | 192.168.1.24 |
| k8s-worker01 | Worker | 192.168.1.21 |
| k8s-worker02 | Worker | 192.168.1.22 |
| k8s-lb01 | Load Balancer | 192.168.1.25 |
| k8s-lb02 | Load Balancer | 192.168.1.26 |
| k8s-nfs01 | NFS Server | 192.168.1.27 |

The Kubernetes API is exposed through:

```text
192.168.1.30:6443
```

HAProxy distributes API traffic across the control-plane nodes, while
Keepalived provides the virtual IP.

## Bootstrap Components

### Common Node Configuration

The `k8s_common` role prepares Kubernetes nodes with:

- OS prerequisites
- Swap configuration
- Kernel modules and sysctl
- containerd
- Kubernetes packages
- kubeadm
- kubelet
- kubectl

### Control Plane

The first control-plane node is initialized by:

```text
ansible/roles/k8s_control_plane/
```

Additional control-plane nodes join through:

```text
ansible/roles/k8s_control_plane_join/
```

Control-plane changes are executed serially:

```yaml
serial: 1
```

This reduces the risk of disrupting multiple control-plane nodes at the
same time.

### Workers

Worker nodes are joined using:

```text
ansible/roles/k8s_worker/
```

Worker joins are also performed serially.

### Cilium Networking

Cilium provides the Kubernetes networking layer:

```text
ansible/roles/cilium/
```

It provides:

- Pod networking
- Service connectivity
- Network policy capabilities
- Network observability

### Helm

Helm is installed using:

```text
ansible/roles/helm/
```

### Persistent Storage

Persistent storage is provided through NFS:

```text
NFS Server
    |
    v
NFS CSI
    |
    v
StorageClass
    |
    v
PVC / PV
```

Related roles:

```text
ansible/roles/nfs_server/
ansible/roles/nfs_csi/
```

### GitOps and Monitoring

Argo CD provides GitOps:

```text
ansible/roles/argocd/
ansible/roles/argocd_bootstrap/
```

The monitoring stack uses `kube-prometheus-stack` and is managed through
GitOps.

## Ansible Bootstrap

The single Ansible entry point is:

```text
ansible/playbooks/site.yml
```

The high-level execution order is:

```text
1. Load Balancers
2. Common Kubernetes Configuration
3. First Control Plane
4. Additional Control Planes
5. Control-Plane Metrics
6. Helm
7. Cilium
8. Workers
9. NFS Server
10. NFS CSI
11. Argo CD
12. GitOps Bootstrap
```

Run the complete bootstrap:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml
```

Specific roles can be executed using tags:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --tags cilium
```

Multiple roles can be selected when required:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --tags "helm,argocd,argocd_bootstrap"
```

Available role tags include:

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

List available tags:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --list-tags
```

Tags are intended for targeted operational changes, while running
`site.yml` without `--tags` executes the complete automation workflow.

## Validation

### Nodes

```bash
kubectl get nodes -o wide
```

Expected:

```text
k8s-cp01       Ready
k8s-cp02       Ready
k8s-cp03       Ready
k8s-worker01   Ready
k8s-worker02   Ready
```

### System Pods

```bash
kubectl get pods -n kube-system
```

Core Kubernetes and networking components should be healthy.

### API Server

```bash
curl -k --max-time 5 \
  https://192.168.1.30:6443/readyz
```

Expected:

```text
ok
```

### Cilium

```bash
kubectl -n kube-system get pods \
  -l k8s-app=cilium \
  -o wide
```

Cilium should be running on all Kubernetes nodes.

### DNS

```bash
kubectl run dns-test \
  --image=busybox:1.36 \
  --restart=Never \
  --rm -it \
  -- nslookup kubernetes.default.svc.cluster.local
```

Expected DNS resolution:

```text
10.96.0.1
```

### Storage

```bash
kubectl get storageclass
kubectl get pv
kubectl get pvc -A
```

PVCs should reach:

```text
Bound
```

### GitOps

```bash
kubectl get applications -n argocd
```

Applications should report:

```text
Synced
Healthy
```

### Monitoring

Prometheus readiness:

```bash
curl -s http://localhost:9091/-/ready
```

Validate active target health:

```bash
curl -s http://localhost:9091/api/v1/targets |
  jq '[.data.activeTargets[] | select(.health != "up")] | length'
```

Expected:

```text
0
```

## Idempotency

Bootstrap automation is designed to be safely re-applied.

Validate syntax:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --syntax-check
```

Use check mode where practical:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --check
```

For isolated changes, use the appropriate role tag instead of
re-running the complete bootstrap workflow.

## Control Plane Safety

Kubernetes control-plane components run as static Pods.

Manifests are located under:

```text
/etc/kubernetes/manifests/
```

Changes to these files are immediately processed by kubelet.

Therefore:

- Change one control-plane node at a time.
- Validate manifests before applying changes.
- Never store backup manifests inside the static Pod directory.
- Check etcd before troubleshooting kube-apiserver.
- Verify etcd membership and quorum before destructive recovery.

Control-plane operations in Ansible use:

```yaml
serial: 1
```

## Recovery Principles

If the Kubernetes API becomes unavailable:

```text
API unavailable
      |
      v
Check kube-apiserver
      |
      v
Check etcd
      |
      v
Check quorum
      |
      v
Check kubelet / static Pods
      |
      v
Recover affected component
      |
      v
Validate etcd
      |
      v
Validate API
      |
      v
Validate Kubernetes
      |
      v
Validate Monitoring
```

Do not immediately use destructive operations such as:

```text
kubeadm reset
rm -rf /var/lib/etcd
etcd member remove
etcd member add
```

until the state of the etcd cluster is understood.

## Design Principles

The bootstrap implementation follows these principles:

- Infrastructure provisioning is separated from platform configuration.
- Reusable logic is encapsulated in Ansible roles.
- `site.yml` is the single Ansible entry point.
- Tags provide targeted role execution.
- Control-plane changes are executed serially.
- Cluster state is validated after platform changes.
- Git remains the source of truth for persistent GitOps configuration.
- Recovery procedures prioritize preserving etcd quorum and cluster state.

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
