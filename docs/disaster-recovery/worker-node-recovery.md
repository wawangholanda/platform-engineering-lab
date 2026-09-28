# Worker Node Recovery

## Purpose

This runbook describes the recovery procedure for a failed Kubernetes worker
node in the `platform-engineering-lab` environment.

The procedure is intended for a worker node that is unavailable or must be
rebuilt while the remaining Kubernetes control-plane and worker nodes
continue operating.

The environment currently uses two worker nodes:

* `k8s-worker01` — `192.168.1.21`
* `k8s-worker02` — `192.168.1.22`

Worker recovery is performed as a **node replacement operation**. The
replacement node is provisioned and configured using the existing
infrastructure and Ansible automation before being rejoined to the
Kubernetes cluster.

A single worker-node failure does not require an etcd snapshot restore or
rebuilding the entire Kubernetes control plane.

Workload availability after a worker failure depends on workload replicas,
available cluster capacity, scheduling constraints, and required persistent
storage.

## Recovery Scenario

The normal recovery flow is:

```text
Worker Failure
      |
      v
Check Worker State
      |
      +----------------------+
      |                      |
      v                      v
Worker Reachable       Worker Unreachable
      |                      |
      v                      v
Cordon + Drain         Confirm Failure
      |                      |
      +----------+-----------+
                 |
                 v
          Remove/Rebuild Node
                 |
                 v
        Provision Replacement
                 |
                 v
             Ansible
                 |
                 v
          kubeadm Worker Join
                 |
                 v
        Validate Worker Node
                 |
                 v
       Validate Workloads
                 |
                 v
       Validate Persistent Storage
```

The recovery procedure separates:

* Kubernetes node lifecycle management.
* Proxmox VM provisioning.
* Operating-system and Kubernetes configuration.
* Worker-node cluster membership.
* Workload and storage validation.

A worker failure should not be treated as a control-plane recovery event unless
the failure is accompanied by a broader cluster failure.

## Environment

The current platform environment is:

| Component         | Configuration       |
| ----------------- | ------------------- |
| Kubernetes        | v1.34.11            |
| Operating system  | Ubuntu 24.04.5      |
| Container runtime | containerd 2.2.1    |
| CNI               | Cilium 1.20.0       |
| Helm              | v3.21.4             |
| Pod CIDR          | `10.0.0.0/16`       |
| Service CIDR      | `10.96.0.0/12`      |
| Kubernetes API    | `192.168.1.30:6443` |
| Worker 01         | `192.168.1.21`      |
| Worker 02         | `192.168.1.22`      |
| NFS server        | `192.168.1.27`      |

The Kubernetes API is accessed through the HAProxy and Keepalived load-balancer
pair rather than directly through an individual control-plane node.

## Preconditions

Before starting worker recovery:

1. Confirm that the Kubernetes API is available.

   ```bash
   kubectl get nodes -o wide
   ```

2. Confirm that the remaining control-plane nodes are healthy.

   ```bash
   kubectl get nodes
   ```

3. Confirm that the remaining worker capacity is sufficient to temporarily
   host workloads.

4. Check for workloads affected by the failed worker.

   ```bash
   kubectl get pods -A -o wide
   ```

5. Check for pods that are already unhealthy or pending.

   ```bash
   kubectl get pods -A
   ```

6. Confirm that the Proxmox infrastructure is available if the worker must
   be rebuilt.

7. Confirm that the repository contains the infrastructure and Ansible
   configuration required to recreate the worker.

8. If persistent workloads are involved, confirm that the NFS server and NFS
   CSI components are healthy before treating storage-related pod failures as
   worker-node failures.

A single worker failure does not require an etcd restore.

## Scenario A — Worker Is Still Reachable

If the failed worker is still reachable through SSH and the Kubernetes
control plane can communicate with it, first determine whether the node can
be safely drained.

Check the node:

```bash
kubectl get node <worker-node> -o wide
```

Check the workloads:

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=<worker-node>
```

Cordon the worker before maintenance:

```bash
kubectl cordon <worker-node>
```

Drain the worker:

```bash
kubectl drain <worker-node> \
  --ignore-daemonsets \
  --delete-emptydir-data
```

The drain operation may require additional options for workloads that use
PodDisruptionBudgets or other scheduling constraints.

Do not force-delete workloads without first understanding why they cannot be
evicted normally.

After workloads have been moved, the worker can be rebuilt or repaired.

If the existing VM will be reused, ensure that its Kubernetes state is
consistent with the intended replacement process before rejoining it.

## Scenario B — Worker Is Unreachable

If the worker is completely unreachable, first confirm that the failure is
actually isolated to that worker.

Check:

```bash
kubectl get nodes -o wide
```

Then inspect the node:

```bash
kubectl describe node <worker-node>
```

Look for conditions such as:

* `Ready: False`
* `Ready: Unknown`
* node heartbeat failures
* kubelet failures
* networking failures
* resource pressure
* filesystem or runtime errors

If the VM is confirmed lost and will not return with the same Kubernetes
identity, remove the failed worker from the cluster before introducing the
replacement with the same intended node identity.

```bash
kubectl delete node <worker-node>
```

Do not delete the Kubernetes node object merely because the node is
temporarily unreachable.

The failed VM must be considered permanently unavailable before removing its
cluster membership. This prevents an old worker from unexpectedly returning
and creating an inconsistent recovery situation.

## Rebuild the Worker

Worker replacement should use the existing infrastructure automation rather
than manually constructing a Kubernetes node.

The infrastructure flow is:

```text
Proxmox
   |
   v
Terraform
   |
   v
Ubuntu VM
   |
   v
Ansible
   |
   v
Kubernetes Worker Configuration
   |
   v
kubeadm Join
```

The repository separates infrastructure provisioning from platform
configuration.

### Provision the Replacement VM

Use the Terraform configuration under:

```text
environments/dev/proxmox/
```

The worker definition should match the intended environment configuration,
including:

* VM name
* VM ID
* CPU
* memory
* storage
* network configuration
* cloud-init configuration

Run the normal Terraform workflow:

```bash
terraform init
terraform validate
terraform plan
```

Review the plan before applying it.

If the worker VM is being replaced using the same infrastructure definition,
confirm that the old VM has been removed or otherwise reconciled before
creating the replacement.

Apply only after the plan has been reviewed:

```bash
terraform apply
```

### Configure the Replacement Worker

After the VM is available and reachable, use the platform Ansible automation.

The primary platform playbook is:

```text
ansible/playbooks/site.yml
```

The worker configuration is implemented by:

```text
ansible/roles/k8s_worker/
```

Run the worker-specific configuration against the replacement node using the
inventory and the appropriate host limit.

For example:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --limit <replacement-worker>
```

The exact inventory hostname should match the repository inventory.

The role is responsible for preparing the worker for Kubernetes rather than
requiring the recovery procedure to manually reproduce the base Kubernetes
configuration.

## Rejoin the Worker

The replacement worker must rejoin the existing Kubernetes cluster using the
repository's Kubernetes worker automation.

The worker must have:

* the expected operating system configuration
* containerd configured and running
* required Kubernetes packages installed
* network connectivity to the Kubernetes API
* the required Cilium prerequisites
* the correct hostname and inventory configuration

The worker join operation is handled through the project's Ansible
Kubernetes worker role and its kubeadm-based workflow.

Do not manually invent a new cluster initialization procedure for a worker
replacement.

The worker must join the existing cluster rather than creating a new
Kubernetes cluster.

After the join completes, verify the node:

```bash
kubectl get nodes -o wide
```

The replacement worker should eventually report:

```text
Ready
```

## Validate Worker Recovery

Confirm that the replacement node is present:

```bash
kubectl get nodes -o wide
```

Check the node details:

```bash
kubectl describe node <worker-node>
```

Confirm that the expected labels, taints, addresses, capacity, and allocatable
resources are present.

Check the kubelet:

```bash
systemctl status kubelet --no-pager
```

Check containerd:

```bash
systemctl status containerd --no-pager
```

Check Cilium:

```bash
kubectl get pods -n kube-system -o wide
```

The replacement worker must have a healthy Cilium agent before it is considered
fully recovered.

## Validate Workload Scheduling

After the worker becomes `Ready`, verify workload scheduling:

```bash
kubectl get pods -A -o wide
```

Check for pods in problematic states:

```bash
kubectl get pods -A | grep -E \
  'Pending|CrashLoopBackOff|ImagePullBackOff|ContainerCreating'
```

Review workloads that were previously running on the failed worker.

For deployments:

```bash
kubectl get deployments -A
```

For stateful workloads:

```bash
kubectl get statefulsets -A
```

For daemonsets:

```bash
kubectl get daemonsets -A
```

Workload recovery depends on the application's replica configuration.

A single worker failure may cause temporary workload disruption when:

* only one replica exists
* insufficient worker capacity remains
* a PodDisruptionBudget prevents eviction
* node affinity or anti-affinity restricts scheduling
* topology constraints restrict scheduling
* required persistent storage is unavailable

Therefore, a recovered worker node being `Ready` does not by itself prove that
all applications have recovered.

## Validate Persistent Storage

If workloads use persistent storage, verify the storage layer independently.

Check StorageClasses:

```bash
kubectl get storageclass
```

Check persistent volumes:

```bash
kubectl get pv
```

Check persistent volume claims:

```bash
kubectl get pvc -A
```

Check the NFS CSI components:

```bash
kubectl get pods -A | grep -i nfs
```

Inspect any PVC that remains pending:

```bash
kubectl describe pvc <pvc-name> -n <namespace>
```

A worker-node replacement does not recreate or restore data stored on the NFS
server.

The expected relationship is:

```text
Application Pod
      |
      v
PVC
      |
      v
StorageClass
      |
      v
NFS CSI
      |
      v
NFS Server
192.168.1.27
```

If a workload fails after worker recovery because its persistent data is
missing, this is a storage recovery problem rather than a normal worker-node
recovery problem.

## Validate Cilium Networking

Verify Cilium components:

```bash
kubectl get pods -n kube-system -o wide
```

Check the Cilium status from the replacement worker if the Cilium CLI is
available:

```bash
cilium status
```

Confirm that the worker has a Cilium agent and that the agent is healthy.

If application connectivity is affected, validate the Gateway API resources:

```bash
kubectl get gateway -A
kubectl get httproute -A
```

The primary application Gateway is:

```text
nginx-gateway
192.168.1.240
```

Networking recovery should be validated independently from node readiness.

## Validate GitOps

The worker-node recovery procedure should not require manual recreation of
GitOps-managed application resources.

Check Argo CD applications:

```bash
kubectl get applications -n argocd
```

The expected applications include:

```text
dev-gateway
dev-monitoring
dev-nginx
```

If an application remains degraded after worker recovery, inspect its state
through Argo CD and Kubernetes before making manual changes.

Git remains the source of truth for GitOps-managed application and platform
resources.

## Recovery Success Criteria

Worker recovery is considered complete when:

* The replacement worker is present in the Kubernetes cluster.
* The worker reports `Ready`.
* Kubelet is running normally.
* Containerd is running normally.
* Cilium is healthy on the replacement worker.
* No unexpected node conditions are present.
* Workloads can be scheduled onto the available worker capacity.
* Previously affected workloads have recovered or their remaining issues have
  been identified.
* Persistent volume claims required by affected workloads are healthy.
* NFS CSI components are healthy when persistent storage is required.
* Gateway and application networking remain functional.
* Argo CD applications remain in the expected state.
* No unnecessary control-plane or etcd recovery was performed.

The recovery result should be evaluated at both the **node level** and the
**workload level**.

## Important Notes

A worker-node recovery is not an etcd recovery.

The worker node does not contain the authoritative Kubernetes cluster state.
That state is maintained by the Kubernetes control plane and etcd.

Therefore:

```text
Worker Failure
     |
     +--> Replace worker
     |
     +--> Rejoin cluster
     |
     +--> Reschedule workloads
     |
     +--> Validate storage and networking
```

is fundamentally different from:

```text
Control Plane / etcd State Loss
     |
     +--> Restore etcd
     |
     +--> Restore Kubernetes state
     |
     +--> Validate control plane
```

Do not restore an etcd snapshot as part of normal worker-node replacement.

If a control-plane node fails, use:

```text
docs/disaster-recovery/control-plane-node-recovery.md
```

If etcd state has been lost or corrupted and restoration is required, use:

```text
docs/disaster-recovery/etcd-restore-runbook.md
```

If the entire Kubernetes platform must be reconstructed, use:

```text
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
```

Worker recovery should also preserve the distinction between Kubernetes state
and external application data. Rejoining a worker does not restore files
stored on NFS or other external storage systems.

## Validation Record

Record the following information after a worker recovery:

| Item                                   | Result |
| -------------------------------------- | ------ |
| Failed worker                          |        |
| Replacement worker                     |        |
| Failure date/time                      |        |
| Failure cause                          |        |
| Worker reachable before replacement    |        |
| Node cordoned/drained                  |        |
| Failed node removed                    |        |
| Replacement VM provisioned             |        |
| Ansible worker configuration completed |        |
| Worker joined Kubernetes               |        |
| Worker status                          |        |
| Kubelet status                         |        |
| Containerd status                      |        |
| Cilium status                          |        |
| Workloads recovered                    |        |
| PVC/PV status                          |        |
| NFS CSI status                         |        |
| Gateway/networking status              |        |
| Argo CD status                         |        |
| Final validation result                |        |
| Operator                               |        |
| Notes                                  |        |
