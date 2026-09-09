# Control Plane Node Recovery

## Purpose

This runbook describes the recovery procedure for a failed Kubernetes control-plane node in the `platform-engineering-lab` environment.

The environment uses three control-plane nodes and a shared Kubernetes API endpoint:

```text
192.168.1.30:6443
```

Because the control plane is highly available, a single failed control-plane node can normally be rebuilt and rejoined without restoring the
entire etcd cluster from snapshot.

---

## Recovery Scenario

Typical scenario:

```text
control-plane node
        ↓
failure
        ↓
remaining control-plane nodes continue serving
        ↓
rebuild failed node
        ↓
kubeadm join --control-plane
        ↓
control-plane restored
```

This procedure assumes sufficient control-plane/etcd quorum remains available.

---

## Environment

| Component              | Value                |
| ---------------------- | -------------------- |
| Kubernetes             | v1.34.10             |
| Control-plane endpoint | `192.168.1.30:6443`  |
| Control plane 1        | `192.168.1.20`       |
| Control plane 2        | `192.168.1.23`       |
| Control plane 3        | `192.168.1.24`       |
| Load Balancers         | HAProxy + Keepalived |

---

## Preconditions

Confirm that the cluster remains accessible:

```bash
kubectl get nodes
```

Verify that at least the remaining control-plane nodes are healthy.

Check:

```bash
kubectl get nodes -l node-role.kubernetes.io/control-plane
```

Confirm the API endpoint:

```bash
kubectl cluster-info
```

---

## Verify Control Plane Health

Check control-plane components:

```bash
kubectl get pods -n kube-system
```

Check etcd members when investigating control-plane failure:

```bash
kubectl get pods -n kube-system -l component=etcd -o wide
```

The exact etcd recovery action depends on whether the failed node can be rebuilt while the existing etcd quorum remains healthy.

---

## Scenario A — Single Control Plane Failure

For a single failed node, the preferred strategy is to rebuild and rejoin the control plane rather than restore the complete etcd cluster.

Example:

```text
cp02 failed

cp01 → healthy
cp03 → healthy
```

The Kubernetes API remains available through:

```text
192.168.1.30:6443
```

---

## Prepare Replacement Node

Rebuild the affected VM using the existing infrastructure automation.

Ensure:

* Ubuntu 24.04.4 LTS
* Correct IP address
* Correct hostname
* SSH access
* containerd
* kubeadm
* kubelet

The common configuration is managed through:

```text
ansible/roles/k8s_common/
```

---

## Rejoin the Control Plane

The control-plane join automation is managed through:

```text
ansible/roles/k8s_control_plane_join/
```

Run:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml
```

The automation determines whether the control-plane node has already joined.

For a new control-plane node, the automation:

1. Uploads control-plane certificates.
2. Extracts the certificate key.
3. Generates the control-plane join command.
4. Runs the control-plane join.

---

## Validate Control Plane Recovery

Check:

```bash
kubectl get nodes -o wide
```

Expected:

```text
k8s-cp01       Ready    control-plane
k8s-cp02       Ready    control-plane
k8s-cp03       Ready    control-plane
```

Check control-plane pods:

```bash
kubectl get pods -n kube-system -o wide
```

Confirm etcd members:

```bash
kubectl get pods -n kube-system \
  -l component=etcd \
  -o wide
```

---

## Validate API Availability

Confirm the shared endpoint:

```bash
curl -k https://192.168.1.30:6443/healthz
```

The endpoint should return a successful health response.

Confirm kubectl connectivity:

```bash
kubectl get --raw='/readyz?verbose'
```

---

## Validate Cilium and Networking

Check Cilium:

```bash
kubectl get pods \
  -n kube-system \
  -l k8s-app=cilium \
  -o wide
```

Verify Gateway API:

```bash
kubectl get gateway -n default
kubectl get httproute -n default
```

---

## Validate GitOps

Check Argo CD applications:

```bash
kubectl get applications -n argocd
```

Expected:

```text
dev-gateway      Synced    Healthy
dev-monitoring   Synced    Healthy
dev-nginx        Synced    Healthy
```

The control-plane replacement should not require manually recreating GitOps applications.

---

## Scenario B — Multiple Control Plane Failures

If multiple control-plane nodes fail, first determine whether etcd quorum remains available.

Do not immediately execute a full reset.

Check:

```bash
kubectl get nodes
```

If the API remains available, inspect control-plane and etcd health before proceeding.

If the etcd quorum is lost but a valid snapshot exists, use the dedicated:

```text
docs/disaster-recovery/etcd-restore-runbook.md
```

Do not treat this as a normal single-node replacement.

---

## When etcd Restore Is Required

Use the etcd restore procedure when:

* The existing etcd state cannot be recovered from remaining members.
* etcd data is corrupted.
* etcd quorum is lost.
* The Kubernetes control-plane state must be restored from a known snapshot.

Use:

```text
docs/disaster-recovery/etcd-restore-runbook.md
```

---

## Recovery Success Criteria

Control-plane recovery is successful when:

```text
All control-plane nodes    → Ready
API VIP                    → Accessible
etcd state                 → Healthy
kube-apiserver             → Healthy
scheduler                  → Healthy
controller-manager         → Healthy
Cilium                     → Healthy
Argo CD                    → Synced + Healthy
Cluster workloads          → Running
```

---

## Important Notes

A single control-plane node failure does not automatically require:

* etcd snapshot restore
* full Kubernetes reconstruction
* GitOps rebootstrap

The preferred approach is node replacement while preserving the healthy cluster state.

---

## Validation Record

Record:

```text
Failure date:
Affected control-plane:
Failure cause:
Remaining control-plane quorum:
Replacement/rebuild performed:
Control-plane rejoined:
API validated:
etcd validated:
Cilium validated:
GitOps validated:
Final result:
```
