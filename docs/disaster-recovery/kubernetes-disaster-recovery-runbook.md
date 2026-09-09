# Kubernetes Disaster Recovery Runbook

## Purpose

This runbook describes the controlled procedure for reconstructing the Kubernetes platform using the infrastructure and automation defined
in the `platform-engineering-lab` repository.

It is intended for lab disaster-recovery exercises and full Kubernetes cluster reconstruction.

The procedure is designed to:

* Protect persistent application data.
* Require explicit confirmation before destructive operations.
* Rebuild the Kubernetes control plane and workers.
* Restore platform services through Ansible.
* Restore GitOps-managed applications through Argo CD.
* Validate the reconstructed platform.

---

## Architecture

```text
                    ┌───────────────────┐
                    │   Git Repository  │
                    │ platform-eng-lab  │
                    └─────────┬─────────┘
                              │
                              ▼
                    ┌───────────────────┐
                    │      Ansible      │
                    │      site.yml     │
                    └─────────┬─────────┘
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
          ▼                   ▼                   ▼
   HAProxy/Keepalived     Kubernetes            NFS
          │                   │                   │
          │                   ▼                   │
          │                Cilium                 │
          │                   │                   │
          │                   ▼                   │
          │                Argo CD                │
          │                   │                   │
          │                   ▼                   │
          │             GitOps Applications      │
          │                                       │
          └───────────────────────────────────────┘
```

---

## Safety Requirements

## Persistent Data

Before performing any destructive reconstruction, verify that no persistent Kubernetes resources contain data that must be preserved.

Check:

```bash
kubectl get pv
kubectl get pvc -A
```

The automated safety gate performs this validation:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/cluster-reconstruct.yml
```

Do not continue with destructive reconstruction when persistent data has not been backed up or intentionally preserved.

---

## Step 1 — Verify Repository State

Check the repository:

```bash
git status --short
```

Expected:

```text
(no output)
```

Verify branch and recent commits:

```bash
git branch --show-current
git log --oneline -3
```

Confirm that the expected recovery automation and Kubernetes manifests are available.

---

## Step 2 — Run the Safety Gate

Execute:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/cluster-reconstruct.yml
```

The safety gate checks:

* PersistentVolumes
* PersistentVolumeClaims
* Kubernetes configuration
* kubeadm installation
* reset capability

Expected persistent-storage validation:

```text
Existing PVs: []
Existing PVCs: []
No PV/PVC resources detected. Reconstruction safety gate passed.
```

The playbook should stop before destructive action unless explicit confirmation is supplied.

---

## Step 3 — Authorize Destructive Reset

After confirming that reconstruction is safe:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/cluster-reconstruct.yml \
  -e k8s_reset_confirm=true
```

The controlled reset is performed on:

```text
k8s-cp01
k8s-cp02
k8s-cp03
k8s-worker01
k8s-worker02
```

Expected:

```text
failed=0
unreachable=0
```

---

## Step 4 — Rebuild the Platform

Run the complete playbook:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml
```

The full automation reconstructs:

1. HAProxy
2. Keepalived
3. Kubernetes common configuration
4. First control plane
5. Additional control planes
6. Workstation kubeconfig
7. Control-plane metrics
8. Helm
9. Cilium
10. Kubernetes workers
11. NFS server
12. NFS CSI
13. Argo CD
14. GitOps applications
15. Monitoring
16. etcd backup

---

## Step 5 — Validate Kubernetes

Check nodes:

```bash
kubectl get nodes
```

Expected:

```text
k8s-cp01       Ready
k8s-cp02       Ready
k8s-cp03       Ready
k8s-worker01   Ready
k8s-worker02   Ready
```

Confirm the Kubernetes version:

```bash
kubectl version
```

---

## Step 6 — Validate Cilium

Check Cilium pods:

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
```

Expected result: all expected Cilium pods are `Running`.

When required:

```bash
cilium status
```

---

## Step 7 — Validate Gateway API

Check the Gateway:

```bash
kubectl get gateway -n default
```

Inspect Gateway conditions:

```bash
kubectl get gateway nginx-gateway -n default -o yaml
```

Expected conditions:

```text
Accepted=True
Programmed=True
```

Check HTTPRoutes:

```bash
kubectl get httproute -n default
```

Inspect route conditions when troubleshooting:

```bash
kubectl get httproute <route-name> -n default -o yaml
```

For cross-namespace backend references, verify the required `ReferenceGrant` exists in the backend namespace:

```bash
kubectl get referencegrant -n <backend-namespace>
```

---

## Step 8 — Validate Storage

Check the NFS CSI driver:

```bash
kubectl get pods -A | grep nfs
```

Check StorageClasses:

```bash
kubectl get storageclass
```

Expected NFS StorageClass:

```text
nfs
```

Run PVC/PV creation and read/write tests when validating storage recovery.

---

## Step 9 — Validate Argo CD

Check Argo CD components:

```bash
kubectl get pods -n argocd
```

Check Applications:

```bash
kubectl get applications -n argocd
```

Expected:

```text
NAME             SYNC STATUS   HEALTH STATUS
dev-gateway      Synced        Healthy
dev-monitoring   Synced        Healthy
dev-nginx        Synced        Healthy
```

---

## Step 10 — Validate Monitoring

Check the monitoring namespace:

```bash
kubectl get pods -n monitoring
```

Expected components include:

* Prometheus
* Grafana
* Alertmanager
* kube-prometheus-stack operator
* node exporters

Verify Prometheus readiness:

```bash
kubectl get pods -n monitoring
```

Then query the Prometheus readiness endpoint from the Prometheus pod:

```bash
kubectl exec -n monitoring <prometheus-pod> -- \
  wget -qO- http://localhost:9090/-/ready
```

Expected:

```text
Prometheus Server is Ready.
```

---

## Step 11 — Validate etcd Backup

Check the backup timer:

```bash
systemctl status etcd-backup.timer
```

Check the schedule:

```bash
systemctl list-timers | grep etcd-backup
```

Inspect local backup storage:

```bash
ls -lah /var/backups/etcd
```

Verify the NFS mount:

```bash
mount | grep nfs
```

---

## Step 12 — Final Validation

Run the following:

```bash
kubectl get nodes
kubectl get applications -n argocd
kubectl get storageclass
kubectl get gateway -n default
kubectl get httproute -n default
```

Recovery should only be considered successful when:

```text
Kubernetes nodes          → Ready
Control plane             → HA and reachable through VIP
Cilium                    → Running
Gateway                   → Accepted + Programmed
NFS StorageClass          → Present
Argo CD                   → Running
GitOps applications       → Synced + Healthy
Monitoring                → Running
etcd backup automation    → Enabled
Ansible execution         → failed=0
```

---

## Troubleshooting

## HAProxy Reports No Backend Available

During reconstruction, HAProxy may temporarily report:

```text
backend kubernetes-control-plane has no server available
```

This may occur while Kubernetes API servers are being rebuilt.

Verify the Kubernetes API through the VIP:

```bash
curl -k https://192.168.1.30:6443/healthz
```

A temporary message during reconstruction does not necessarily indicate a failed recovery.

---

## Argo CD Application Is Degraded

Identify the application:

```bash
kubectl get applications -n argocd
```

Inspect the application:

```bash
kubectl get application <application-name> -n argocd -o yaml
```

For Gateway-related applications, inspect:

```bash
kubectl get gateway -n default
kubectl get httproute -n default -o yaml
```

For cross-namespace references, verify:

```bash
kubectl get referencegrant -n <backend-namespace>
```

A route using a Service in another namespace requires the appropriate `ReferenceGrant`.

---

## GitOps Application Uses an Unexpected Revision

Check the Application:

```bash
kubectl get application <application-name> -n argocd \
  -o jsonpath='{.spec.source.targetRevision}{"\n"}{.status.sync.revision}{"\n"}'
```

Verify the remote branch:

```bash
git ls-remote origin refs/heads/main
```

The revision consumed by Argo CD should correspond to the intended Git commit.

---

## Recovery Principles

The following principles should be maintained during future recovery procedures:

1. Never bypass the persistent-storage safety gate.
2. Never perform destructive reset without explicit authorization.
3. Use the complete `site.yml` for full platform reconstruction.
4. Prefer declarative changes through Ansible and Git rather than manual configuration.
5. Investigate Kubernetes resource status before changing Argo CD configuration.
6. Validate the platform after reconstruction rather than relying only on Ansible completion.
7. Treat Git as the source of truth for GitOps-managed resources.

---

## Recovery Success Criteria

The recovery is considered successful when the Kubernetes platform can be reconstructed from the documented starting state and all critical
services return to a healthy state.

Minimum acceptance criteria:

```text
Kubernetes nodes          → Ready
Control plane             → HA and accessible through VIP
Cilium                    → Running
Gateway API               → Healthy
NFS CSI                   → Available
Argo CD                   → Running
GitOps applications       → Synced + Healthy
Monitoring                → Running
etcd backup               → Configured
Ansible execution         → failed=0
```

---

## Repository References

Primary automation:

```text
ansible/playbooks/site.yml
ansible/playbooks/cluster-reconstruct.yml
```

Kubernetes reset role:

```text
ansible/roles/k8s_reset/
```

GitOps configuration:

```text
environments/dev/kubernetes/
```

The runbook should be updated whenever the cluster topology, recovery process, or automation interfaces change.
