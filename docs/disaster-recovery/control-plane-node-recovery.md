# Control Plane Node Recovery

## Purpose

This runbook describes the recovery procedure for a failed Kubernetes
control-plane node in the `platform-engineering-lab` environment.

The environment uses three control-plane nodes and a shared Kubernetes API
endpoint:

192.168.1.30:6443

---

## Recovery Scenario

The normal recovery scenario for a single failed control-plane node is:

control-plane node
        |
        v
     failure
        |
        v
remaining control-plane nodes
continue serving the cluster
        |
        v
verify etcd quorum
        |
        v
rebuild replacement VM
        |
        v
configure node with Ansible
        |
        v
kubeadm join --control-plane
        |
        v
control-plane node restored
        |
        v
validate Kubernetes, etcd,
networking, and GitOps

---

## Environment

| Component | Value |
|---|---|
| Kubernetes | v1.34.11 |
| Control-plane endpoint | `192.168.1.30:6443` |
| Control plane 1 | `192.168.1.20` |
| Control plane 2 | `192.168.1.23` |
| Control plane 3 | `192.168.1.24` |
| Load Balancers | HAProxy + Keepalived |
| etcd | Stacked etcd, 3 members |
| CNI | Cilium 1.20.0 |
| Container runtime | containerd 2.2.1 |
| Operating system | Ubuntu 24.04.5 |

---

## Preconditions

Before rebuilding a failed control-plane node, confirm that the remaining
cluster is healthy enough to perform the recovery.

### Verify Cluster Access

```bash
kubectl get nodes -o wide
```

The remaining control-plane nodes should be `Ready`.

Verify the shared API endpoint:

```bash
kubectl cluster-info
```

The cluster should remain accessible through:

```text
192.168.1.30:6443
```

### Verify Control-Plane Nodes

```bash
kubectl get nodes \
  -l node-role.kubernetes.io/control-plane \
  -o wide
```

Confirm that the remaining control-plane nodes are available.

### Verify etcd Quorum

Check the etcd pods:

```bash
kubectl get pods \
  -n kube-system \
  -l component=etcd \
  -o wide
```

The cluster uses three stacked etcd members. At least two healthy members are
required to maintain etcd quorum.

If etcd quorum is unavailable, **stop this procedure** and follow:

```text
docs/disaster-recovery/etcd-restore-runbook.md
```

### Verify Infrastructure Automation

Ensure that the infrastructure and configuration automation is available:

```text
Terraform
    |
    v
Proxmox VM
    |
    v
Ansible
    |
    v
Kubernetes control-plane
```

The replacement node should use the same infrastructure and configuration
management process as the original node.

---

## Verify Control Plane Health

Before replacing the failed node, verify the health of the remaining
control-plane components.

Check all Kubernetes system pods:

```bash
kubectl get pods -n kube-system -o wide
```

Check the remaining etcd members:

```bash
kubectl get pods \
  -n kube-system \
  -l component=etcd \
  -o wide
```

Confirm that the remaining etcd members are running and that the cluster
still has quorum.

Check the Kubernetes API readiness:

```bash
kubectl get --raw='/readyz?verbose'
```

The API server should report a successful readiness response.

If the API server is unavailable or etcd quorum has been lost, stop the
single-node recovery procedure and follow the appropriate disaster recovery
runbook instead.

For etcd recovery, see:

```text
docs/disaster-recovery/etcd-restore-runbook.md
```

For full Kubernetes disaster recovery, see:

```text
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
```

---

## Scenario A — Single Control Plane Failure

For a single failed control-plane node, the preferred recovery strategy is to
rebuild the affected node and rejoin it to the existing Kubernetes cluster.

Example:

```text
cp02 failed

cp01 → healthy
cp03 → healthy
```

The remaining control-plane nodes continue serving the cluster through the
shared Kubernetes API endpoint:

```text
192.168.1.30:6443
```

Before proceeding, verify that:

* The API endpoint remains accessible.
* The remaining control-plane nodes are `Ready`.
* At least two etcd members remain healthy.
* etcd quorum is maintained.

The failed node should then be treated as a replacement node rather than
restoring the entire Kubernetes control plane from an etcd snapshot.

---

## Prepare Replacement Node

Rebuild the affected control-plane VM using the existing infrastructure
automation.

The replacement node should retain the expected infrastructure configuration:

* Ubuntu 24.04.5
* Correct control-plane IP address
* Correct hostname
* SSH access
* containerd
* kubeadm
* kubelet

The infrastructure layer is managed through Terraform and Proxmox.

The Kubernetes node configuration is managed through Ansible, including the
common Kubernetes configuration:

```text
ansible/roles/k8s_common/
```

The control-plane configuration and join process are managed through:

```text
ansible/roles/k8s_control_plane/
ansible/roles/k8s_control_plane_join/
```

After the replacement VM has been provisioned and configured, verify basic
node connectivity before proceeding with the control-plane join:

```bash
ansible -i ansible/inventory/dev/hosts.yml \
  k8s-cp02 \
  -m ping
```

Replace `k8s-cp02` with the hostname of the affected control-plane node.

Do not proceed with the control-plane join until the replacement node has the
correct hostname, IP address, container runtime, `kubeadm`, and `kubelet`
configuration.

---

## Rejoin the Control Plane

The control-plane rejoin process is managed through the Ansible automation:

```text
ansible/roles/k8s_control_plane_join/
```

Run the platform playbook against the replacement node:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --limit <replacement-control-plane>
```

Replace `<replacement-control-plane>` with the affected control-plane
hostname, for example:

```text
k8s-cp02
```

The control-plane join automation handles the required preparation and
generates the `kubeadm join --control-plane` operation using the existing
cluster state.

For a new control-plane node, the automation performs the required
control-plane certificate handling, obtains the certificate key, generates
the control-plane join configuration, and executes the join operation.

After the playbook completes successfully, verify that the replacement node
has joined the Kubernetes cluster before continuing with the validation
steps.

```bash
kubectl get nodes -o wide
```

Do not manually reset or reinitialize the remaining healthy control-plane
nodes during a single-node recovery.

---

## Validate Control Plane Recovery

After the replacement control-plane node has rejoined the cluster, verify
that all control-plane nodes are available and healthy.

Check the nodes:

```bash
kubectl get nodes -o wide
```

Expected:

```text
k8s-cp01       Ready    control-plane
k8s-cp02       Ready    control-plane
k8s-cp03       Ready    control-plane
```

Check the Kubernetes control-plane components:

```bash
kubectl get pods -n kube-system -o wide
```

Verify the etcd members:

```bash
kubectl get pods \
  -n kube-system \
  -l component=etcd \
  -o wide
```

All three control-plane nodes should have their corresponding etcd members
running.

Check API server readiness:

```bash
kubectl get --raw='/readyz?verbose'
```

The readiness checks should report successful results.

If any control-plane component or etcd member remains unhealthy, investigate
the node before considering the recovery complete.

---

## Validate API Availability

Confirm that the Kubernetes API remains accessible through the shared
control-plane endpoint:

```bash
curl -k https://192.168.1.30:6443/healthz
```

The endpoint should return a successful health response.

Verify Kubernetes API readiness:

```bash
kubectl get --raw='/readyz?verbose'
```

The readiness checks should report successful results.

Confirm that `kubectl` is using the expected HA API endpoint:

```bash
kubectl cluster-info
```

The Kubernetes API endpoint should remain:

```text
192.168.1.30:6443
```

This confirms that the recovered control-plane node has rejoined the cluster
without changing the shared API endpoint used by clients.

---

## Validate Cilium and Networking

After the control-plane node has been recovered, verify that Cilium is healthy
across the cluster.

Check Cilium pods:

```bash
kubectl get pods \
  -n kube-system \
  -l k8s-app=cilium \
  -o wide
```

All expected Cilium pods should be `Running` or otherwise in a healthy state.

Verify the Cilium Gateway API resources:

```bash
kubectl get gateway -n default
kubectl get httproute -n default
```

The primary Gateway should be available:

```text
nginx-gateway
```

Verify the Gateway LoadBalancer address:

```bash
kubectl get gateway nginx-gateway -n default -o wide
```

The expected Gateway address is:

```text
192.168.1.240
```

A control-plane node replacement should not require recreating the Gateway
API resources. These resources remain managed through the existing GitOps
configuration.

---

## Validate GitOps

Verify that the control-plane recovery did not affect the GitOps-managed
resources.

Check Argo CD applications:

```bash id="9e7t2p"
kubectl get applications -n argocd
```

The expected applications include:

```text id="q5n4x1"
dev-gateway
dev-monitoring
dev-nginx
```

Confirm the application status in Argo CD:

```bash id="t8w2a6"
kubectl get applications -n argocd \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
```

Applications should report the expected `Synced` and `Healthy` states.

The control-plane replacement should not require manually recreating
GitOps-managed applications or Gateway API resources.

If an application is not synchronized or healthy, investigate the Argo CD
application and its managed resources before marking the recovery complete.

---

## Scenario B — Multiple Control Plane Failures

If multiple control-plane nodes fail, first determine whether the remaining
etcd members still have quorum.

Do not immediately rebuild or reset the remaining control-plane nodes.

Check cluster access:

```bash
kubectl get nodes -o wide
```

If the Kubernetes API remains available, inspect the remaining control-plane
and etcd health:

```bash
kubectl get pods \
  -n kube-system \
  -l component=etcd \
  -o wide
```

The cluster uses three stacked etcd members. With three members, quorum
requires at least two healthy members.

If two control-plane nodes have failed and the remaining etcd member is still
healthy, the cluster may remain accessible, but etcd no longer has quorum and
the cluster cannot safely continue normal control-plane operations that
require etcd writes.

If etcd quorum is lost, stop the normal node-replacement procedure and follow:

```text
docs/disaster-recovery/etcd-restore-runbook.md
```

If the Kubernetes control-plane state requires a broader reconstruction,
follow:

```text
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
```

Multiple control-plane failures must therefore be treated as a potential
cluster disaster-recovery scenario rather than a normal single-node
replacement.

---

## When etcd Restore Is Required

Use the dedicated etcd restore procedure when the existing etcd state cannot
be recovered through normal control-plane node replacement.

Typical conditions include:

* The existing etcd quorum has been lost.
* Remaining etcd members cannot form a healthy cluster.
* etcd data is corrupted or otherwise unusable.
* A known-good etcd snapshot must be used to restore the Kubernetes cluster
  state.
* The Kubernetes control-plane state must be reconstructed from a snapshot.

Before performing an etcd restore, preserve the remaining cluster state and
avoid unnecessary `kubeadm reset` or etcd membership changes.

Use the dedicated runbook:

```text
docs/disaster-recovery/etcd-restore-runbook.md
```

For a broader Kubernetes disaster recovery scenario, use:

```text
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
```

An etcd snapshot restore is a **disaster recovery operation**, not the normal
procedure for replacing a single failed control-plane node.

---

## Recovery Success Criteria

Control-plane recovery is considered successful when all required platform
components have been validated.

```text
All control-plane nodes    → Ready
API VIP                    → Accessible
etcd state                 → Healthy
kube-apiserver             → Healthy
scheduler                  → Healthy
controller-manager         → Healthy
Cilium                     → Healthy
Gateway API                → Available
Argo CD                    → Synced + Healthy
Cluster workloads          → Running
```

The recovered control-plane node must be `Ready` and its control-plane
components must be running normally.

The shared Kubernetes API endpoint must remain accessible through:

```text id="c0ngm7"
192.168.1.30:6443
```

The recovery should not introduce changes to existing GitOps-managed
applications, Gateway API resources, or persistent storage configuration.

If any required component remains unhealthy, continue troubleshooting before
closing the recovery procedure.

---

## Important Notes

A single control-plane node failure does not automatically require:

* An etcd snapshot restore.
* Full Kubernetes cluster reconstruction.
* GitOps rebootstrap.
* Reconfiguration of the shared Kubernetes API endpoint.

The preferred approach is to replace the failed node while preserving the
healthy cluster state.

Before rebuilding the node, always verify that the remaining control-plane
nodes are healthy and that etcd quorum is available.

Do not reset, remove, or reconfigure healthy control-plane nodes as part of a
single-node replacement.

If etcd quorum has been lost, stop the node-replacement procedure and follow
the dedicated etcd restore or Kubernetes disaster recovery runbook.

---

## Validation Record

Record the recovery activity and validation results after completing the
control-plane node replacement.

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

Gateway API validated:

GitOps validated:

Cluster workloads validated:

Final result:
```

The completed record should be retained as part of the operational history
for the Kubernetes platform.
