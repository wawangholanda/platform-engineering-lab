# Worker Node Recovery

## Purpose

This runbook describes the recovery procedure for a failed Kubernetes worker node in the `platform-engineering-lab` environment.

The procedure is intended for a worker node that is unavailable or must be rebuilt while the remaining Kubernetes control plane and worker
nodes continue operating.

This recovery does not require an etcd snapshot restore and does not require rebuilding the entire Kubernetes cluster.

---

## Recovery Scenario

Typical scenario:

```text
worker node
    ↓
failure / replacement required
    ↓
rebuild worker VM
    ↓
rejoin Kubernetes cluster
    ↓
Cilium agent restored
    ↓
workloads scheduled onto available nodes
```

The existing control plane remains operational.

---

## Environment

| Component              | Value               |
| ---------------------- | ------------------- |
| Kubernetes             | v1.34.10            |
| Control-plane endpoint | `192.168.1.30:6443` |
| CNI                    | Cilium 1.20.0       |
| Worker 1               | `192.168.1.21`      |
| Worker 2               | `192.168.1.22`      |

---

## Preconditions

Before replacing a worker node, confirm that the control plane is healthy:

```bash
kubectl get nodes
```

Expected:

```text
k8s-cp01       Ready
k8s-cp02       Ready
k8s-cp03       Ready
```

Confirm that another worker remains available when possible:

```bash
kubectl get nodes
```

Review workloads currently running on the failed node:

```bash
kubectl get pods -A -o wide
```

Identify pods scheduled to the affected worker.

---

## Scenario A — Worker Is Still Reachable

If the worker is reachable and Kubernetes can communicate with it, drain it before rebuilding.

Replace `<worker-node>` with the affected node:

```bash
kubectl cordon <worker-node>
```

Then:

```bash
kubectl drain <worker-node> \
  --ignore-daemonsets \
  --delete-emptydir-data
```

Verify:

```bash
kubectl get nodes
```

The affected node should no longer receive new workloads.

---

## Scenario B — Worker Is Unreachable

If the worker has completely failed, the drain operation may not be possible.

Confirm its status:

```bash
kubectl get node <worker-node>
```

If the node cannot be recovered, proceed with VM replacement and rejoin.

Do not remove the node object automatically without first confirming that the node is permanently unavailable.

---

## Rebuild the Worker

The worker VM can be rebuilt using the existing Terraform and Ansible infrastructure.

Verify the VM has:

* Ubuntu 24.04.4 LTS
* Correct network configuration
* Correct hostname
* SSH access
* containerd
* kubeadm
* kubelet

The common Kubernetes configuration is managed by:

```text
ansible/roles/k8s_common/
```

---

## Rejoin the Worker

The worker is joined using the existing automation:

```text
ansible/roles/k8s_worker/
```

Run:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml
```

The worker role checks whether the worker has already joined and generates a new kubeadm join command when required.

---

## Validate Worker Recovery

Check nodes:

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

Verify Cilium:

```bash
kubectl get pods \
  -n kube-system \
  -l k8s-app=cilium \
  -o wide
```

The recovered worker should have a healthy Cilium agent.

---

## Validate Workload Scheduling

Inspect workloads:

```bash
kubectl get pods -A -o wide
```

Confirm that workloads can be scheduled to the recovered worker.

For deployment-based workloads:

```bash
kubectl get deployments -A
```

Check application services:

```bash
kubectl get svc -A
```

---

## Validate Persistent Storage

For workloads using NFS-backed storage, verify the recovered worker can mount required volumes.

Check PVCs:

```bash
kubectl get pvc -A
```

Check pods using persistent volumes:

```bash
kubectl get pods -A -o wide
```

Persistent application data should remain on the external NFS storage rather than depend on the worker node's local filesystem.

---

## Recovery Success Criteria

Worker recovery is successful when:

```text
Worker node               → Ready
kubelet                   → Running
containerd                → Running
Cilium agent              → Healthy
Workloads                 → Scheduling normally
Persistent storage        → Accessible
Cluster control plane     → Unaffected
```

---

## Important Notes

Worker node recovery does not normally require:

* etcd snapshot restore
* control-plane reconstruction
* full cluster reset
* GitOps application recreation

Argo CD-managed applications should remain available because their desired state is stored in Git and their control plane remains
operational.

---

## Validation Record

A successful worker recovery should record:

```text
Failure date:
Affected node:
Cause:
Replacement/rebuild performed:
Worker successfully rejoined:
Cilium validated:
Workloads validated:
Persistent storage validated:
Final result:
```
