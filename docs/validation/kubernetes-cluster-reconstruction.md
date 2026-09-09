# Kubernetes Cluster Reconstruction

## Purpose

Validate that the Kubernetes platform can be reconstructed from a reset state using the complete Ansible automation.

The validation focuses on repeatability of the platform build and confirms that the reconstructed environment returns to a functional state
without requiring manual configuration of individual components.

The validation covers:

* Kubernetes high-availability control plane reconstruction.
* Worker node reconstruction.
* HAProxy and Keepalived configuration.
* Cilium networking and Gateway API.
* NFS server and NFS CSI integration.
* Argo CD installation and GitOps bootstrap.
* Monitoring deployment.
* etcd backup automation.
* Repeatability of the complete `site.yml` workflow.

---

## Environment

| Component      | Value                 |
| -------------- | --------------------- |
| Proxmox VE     | 9.2.0                 |
| Host OS        | Debian GNU/Linux 13   |
| Kubernetes     | v1.34.10              |
| Kubernetes OS  | Ubuntu 24.04.4 LTS    |
| CNI            | Cilium 1.20.0         |
| GitOps         | Argo CD               |
| Monitoring     | kube-prometheus-stack |
| Storage        | NFS + NFS CSI         |
| Load Balancer  | HAProxy + Keepalived  |
| Kubernetes VIP | `192.168.1.30:6443`   |

### Kubernetes Nodes

| Node         | IP             | Role          |
| ------------ | -------------- | ------------- |
| k8s-cp01     | `192.168.1.20` | control-plane |
| k8s-worker01 | `192.168.1.21` | worker        |
| k8s-worker02 | `192.168.1.22` | worker        |
| k8s-cp02     | `192.168.1.23` | control-plane |
| k8s-cp03     | `192.168.1.24` | control-plane |
| k8s-lb01     | `192.168.1.25` | load balancer |
| k8s-lb02     | `192.168.1.26` | load balancer |
| k8s-nfs01    | `192.168.1.27` | NFS server    |

---

## Validation Procedure

## 1. Verify Repository State

Before reconstruction, verify that the repository has no uncommitted changes:

```bash
git status --short
```

Expected result:

```text
(no output)
```

Verify the current branch and recent commits:

```bash
git branch --show-current
git log --oneline -3
```

The repository should contain the current reconstruction automation and Kubernetes manifests.

---

## 2. Run the Reconstruction Safety Gate

Execute:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/cluster-reconstruct.yml
```

The safety gate validates the state of persistent storage before any destructive operation.

Expected result:

```text
Existing PVs: []
Existing PVCs: []
No PV/PVC resources detected. Reconstruction safety gate passed.
```

The playbook then stops because destructive reset is disabled by default.

Expected assertion:

```text
Kubernetes reset is disabled.
Set k8s_reset_confirm=true explicitly to allow destructive reset.
```

This confirms that destructive reconstruction requires explicit authorization.

---

## 3. Perform Controlled Kubernetes Reset

After confirming that reconstruction is safe, execute:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/cluster-reconstruct.yml \
  -e k8s_reset_confirm=true
```

The reset is performed on:

```text
k8s-cp01
k8s-cp02
k8s-cp03
k8s-worker01
k8s-worker02
```

Expected result:

```text
failed=0
unreachable=0
```

---

## Initial Reconstruction

After the Kubernetes nodes have been reset, run the complete automation:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml
```

The complete playbook reconstructs the platform without requiring individual roles or tags to be executed manually.

---

## Initial GitOps Issue

During the first reconstruction, the workflow reached the Argo CD bootstrap phase but `dev-gateway` initially reported:

```text
SYNC STATUS   HEALTH STATUS
Synced        Degraded
```

Investigation identified the affected resource as:

```text
HTTPRoute/default/nginx-route
```

Its status showed:

```text
Accepted=True
ResolvedRefs=False
reason=BackendNotFound
message=Service "nginx" not found
```

The Service itself existed in the `demo` namespace:

```text
demo/nginx
```

The HTTPRoute used a cross-namespace backend reference:

```yaml
backendRefs:
  - name: nginx
    namespace: demo
    port: 80
```

This requires a `ReferenceGrant` in the backend namespace.

The required resource was:

```yaml
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-gateway-backend
  namespace: demo
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: default
  to:
    - group: ""
      kind: Service
      name: nginx
```

---

## Git Revision Mismatch

The repository already contained the required `ReferenceGrant`, but the remote `main` branch used by Argo CD was still pointing to an older
revision.

Local repository history:

```text
c0d1755 fix Kubernetes reconstruction and Argo CD Gateway health
```

Remote `main` initially pointed to:

```text
d9c0b8b docs: add Kubernetes disaster recovery runbook
```

The updated commits were pushed to the remote repository:

```bash
git push origin main
```

The remote branch then pointed to:

```text
270b13ada3363a781fa6bcb6ba55b6394f96b015
```

Argo CD subsequently detected the new revision.

Validation showed:

```text
dev-gateway
revision: 270b13a...
sync: Synced
health: Healthy
```

The required resource was then present:

```text
demo/allow-gateway-backend
```

The original reconstruction completed successfully.

---

## Repeatability Validation

The reconstruction process was executed again from a clean Kubernetes reset.

Reset:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/cluster-reconstruct.yml \
  -e k8s_reset_confirm=true
```

Full reconstruction:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml
```

The complete workflow finished without Ansible failures.

The GitOps bootstrap successfully reached:

```text
dev-nginx       Synced + Healthy
dev-gateway     Synced + Healthy
dev-monitoring  Synced + Healthy
```

The playbook continued through the etcd backup configuration stage.

---

## Final Validation

## Kubernetes Node Validation

Command:

```bash
kubectl get nodes
```

Result:

```text
NAME           STATUS   ROLES           VERSION
k8s-cp01       Ready    control-plane   v1.34.10
k8s-cp02       Ready    control-plane   v1.34.10
k8s-cp03       Ready    control-plane   v1.34.10
k8s-worker01   Ready    <none>          v1.34.10
k8s-worker02   Ready    <none>          v1.34.10
```

All five Kubernetes nodes were `Ready`.

---

## Argo CD Applications

Command:

```bash
kubectl get applications -n argocd
```

Result:

```text
NAME             SYNC STATUS   HEALTH STATUS
dev-gateway      Synced        Healthy
dev-monitoring   Synced        Healthy
dev-nginx        Synced        Healthy
```

All GitOps-managed applications were synchronized and healthy.

---

## Final Automation Result

The reconstruction workflow completed with:

```text
failed=0
unreachable=0
```

The validated platform components include:

* HAProxy
* Keepalived
* Kubernetes control plane
* Kubernetes worker nodes
* Cilium
* Gateway API
* NFS server
* NFS CSI
* NFS StorageClass
* Argo CD
* GitOps applications
* Prometheus/Grafana monitoring
* etcd backup automation

---

## Key Findings

The validation identified an important GitOps dependency during the initial reconstruction.

A cross-namespace `HTTPRoute` backend requires a corresponding `ReferenceGrant` in the backend namespace.

The failure was initially observed as:

```text
HTTPRoute
    ↓
ResolvedRefs=False
    ↓
BackendNotFound
    ↓
Argo CD Application = Degraded
```

After the required resource was committed to the Git repository and the updated revision reached the remote `main` branch:

```text
ReferenceGrant
    ↓
ResolvedRefs=True
    ↓
Gateway resources healthy
    ↓
Argo CD Application = Healthy
```

This demonstrated the value of validating the complete GitOps workflow rather than validating only individual Kubernetes components.

---

## Validation Result

## Status: PASS

The Kubernetes platform was successfully reconstructed from a reset state using the complete Ansible automation.

The reconstruction process was successfully repeated, demonstrating that the automation is capable of rebuilding the platform consistently.

Final platform state:

```text
5/5 Kubernetes nodes       Ready
3/3 Argo CD applications   Synced + Healthy
Ansible execution          failed=0
```

The reconstruction workflow is therefore considered **validated and repeatable**.
