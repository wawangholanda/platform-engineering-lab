# Kubernetes Disaster Recovery Runbook

## 1. Purpose

This runbook defines the recovery procedure for a **full Kubernetes platform reconstruction**
when the existing Kubernetes control-plane state is no longer considered reliable
or the cluster must be rebuilt from infrastructure upward.

This procedure is different from:

* single control-plane node recovery
* single worker-node recovery
* etcd snapshot restore
* application data recovery

The objective is to reconstruct the Kubernetes platform from the repository-defined infrastructure and automation,
then restore the GitOps-managed platform configuration.

---

## 2. Scope

This runbook covers:

* Proxmox infrastructure validation and reconstruction
* Terraform VM provisioning
* Kubernetes state reset when required
* Kubernetes control-plane reconstruction
* control-plane and worker configuration
* Cilium networking
* Gateway API
* NFS and NFS CSI
* Argo CD
* GitOps bootstrap
* automated etcd backup configuration
* automated Kubernetes platform validation
* final platform verification

This runbook does **not** replace:

* [Control Plane Node Recovery](control-plane-node-recovery.md)
* [Worker Node Recovery](worker-node-recovery.md)
* [etcd Restore Runbook](etcd-restore-runbook.md)

Application data, persistent data, credentials, and external service data must be handled according to their own backup and recovery procedures.

---

## 3. Recovery Architecture

The recovery model follows the repository's infrastructure and configuration layers:

```text
Proxmox
   |
   v
Terraform
   |
   v
VM Infrastructure
   |
   v
Kubernetes State Reconstruction
   |
   v
Ansible Platform Configuration
   |
   +--> HAProxy + Keepalived
   +--> Kubernetes Control Plane
   +--> Control-Plane Metrics
   +--> Helm
   +--> Cilium
   +--> Workers
   +--> NFS / CSI
   +--> Argo CD
   +--> GitOps Bootstrap
   +--> etcd Backup
   +--> Kubernetes Validation
   |
   v
Argo CD / GitOps
   |
   v
Platform Applications
   |
   v
Monitoring / Gateway / Workloads
```

The repository remains the source of truth for infrastructure and platform configuration.

---

## 4. Current Platform Architecture

The reconstructed cluster consists of:

### Control plane

| Node | IP           |
| ---- | ------------ |
| cp01 | 192.168.1.20 |
| cp02 | 192.168.1.23 |
| cp03 | 192.168.1.24 |

### Workers

| Node     | IP           |
| -------- | ------------ |
| worker01 | 192.168.1.21 |
| worker02 | 192.168.1.22 |

### Load balancers

| Node | IP           | Role              |
| ---- | ------------ | ----------------- |
| lb01 | 192.168.1.25 | Keepalived MASTER |
| lb02 | 192.168.1.26 | Keepalived BACKUP |

### Kubernetes API

```text
192.168.1.30:6443
```

The API endpoint is provided by HAProxy and Keepalived.

### NFS

```text
192.168.1.27
```

### Kubernetes networking

* Cilium 1.20.0
* kube-proxy replacement
* Pod CIDR: `10.0.0.0/16`
* Service CIDR: `10.96.0.0/12`
* Cluster DNS: `10.96.0.10`

### Gateway

```text
Gateway: nginx-gateway
LoadBalancer IP: 192.168.1.240
```

### External application path

```text
Client
  |
  v
NPM
192.168.1.3
  |
  v
Gateway
192.168.1.240
  |
  +--> nginx-route
  +--> argocd-route
  +--> grafana-route
```

---

## 5. Prerequisites

Before starting a full reconstruction, verify:

* Proxmox is operational.
* Required storage is available.
* Terraform state is available.
* Ansible inventory is available.
* Git repository is available.
* GitOps repository is available.
* NFS infrastructure is available.
* Persistent application data has been identified.
* etcd backup availability has been assessed.
* The recovery scope has been explicitly approved.

A full reconstruction can destroy Kubernetes state. Do not perform the reset step merely because a node is unhealthy.

For a single-node failure, use the appropriate node recovery runbook instead.

---

## 6. Repository Requirements

The recovery procedure depends on the following repository paths.

## Infrastructure

```text
environments/dev/proxmox/
```

Terraform configuration is maintained under the environment-specific directory rather than a repository-root `terraform/` directory.

## Ansible playbooks

```text
ansible/playbooks/proxmox-bootstrap.yml
ansible/playbooks/cluster-reconstruct.yml
ansible/playbooks/site.yml
```

## Important Ansible roles

```text
ansible/roles/proxmox_bootstrap/
ansible/roles/load_balancer/
ansible/roles/k8s_common/
ansible/roles/k8s_control_plane/
ansible/roles/k8s_control_plane_join/
ansible/roles/k8s_control_plane_metrics/
ansible/roles/k8s_worker/
ansible/roles/kubeconfig/
ansible/roles/helm/
ansible/roles/cilium/
ansible/roles/nfs_server/
ansible/roles/nfs_csi/
ansible/roles/argocd/
ansible/roles/argocd_bootstrap/
ansible/roles/etcd_backup/
ansible/roles/k8s_reset/
ansible/roles/k8s_validation/
```

## GitOps configuration

```text
environments/dev/kubernetes/
```

Monitoring configuration is maintained under:

```text
environments/dev/kubernetes/monitoring/kube-prometheus-stack/values.yaml
```

---

## 7. Recovery Procedure

## 7.1 Step 1 — Verify Repository State

Start from a clean and known repository state.

```bash
cd /home/teachme/Documents/repo/repoku/platform-engineering-lab

git status
git branch --show-current
git log -1 --oneline
```

Confirm that the intended revision contains the infrastructure, Ansible, and GitOps configuration required for reconstruction.

Do not start a destructive reconstruction from an unknown working tree.

---

## 8. Step 2 — Verify Persistent Data and Backups

Before resetting Kubernetes state, identify all persistent workloads.

Check:

```bash
kubectl get pv
kubectl get pvc -A
```

Also verify the availability of:

* application backups
* NFS data
* etcd snapshots
* database backups
* external storage
* GitOps repository state

The existence of PV/PVC objects is treated as a safety signal by the repository reconstruction automation.

---

## 9. Step 3 — Run the Reconstruction Safety Gate

The repository provides a dedicated reconstruction playbook:

```text
ansible/playbooks/cluster-reconstruct.yml
```

Its first play runs a safety gate against the first control-plane node.

The safety gate checks for existing PV/PVC state before allowing the destructive Kubernetes reset.

The default behavior is intentionally conservative:

```yaml
reconstruction_allow_persistent_data: false
k8s_reset_confirm: false
```

Therefore, running:

```bash
ansible-playbook ansible/playbooks/cluster-reconstruct.yml
```

does not automatically authorize a destructive reset.

The operator must explicitly confirm the reset when it is appropriate.

---

## 10. Step 4 — Controlled Kubernetes State Reset

If the cluster must be reconstructed from an existing Kubernetes installation, the reset is performed through the repository's `k8s_reset` role.

The explicit reset command is:

```bash
ansible-playbook ansible/playbooks/cluster-reconstruct.yml \
  -e k8s_reset_confirm=true
```

This command should only be executed after:

1. the recovery scope has been approved;
2. persistent data has been identified;
3. required backups have been verified;
4. the existing cluster state is no longer required;
5. the consequences of resetting Kubernetes state are understood.

If PV/PVC objects intentionally exist and the reconstruction is explicitly authorized to proceed despite them,
the safety gate requires an additional explicit override:

```bash
ansible-playbook ansible/playbooks/cluster-reconstruct.yml \
  -e k8s_reset_confirm=true \
  -e reconstruction_allow_persistent_data=true
```

This override should not be used as a shortcut around backup verification.

---

## 11. Step 5 — Reconstruct Proxmox Infrastructure

If the VM infrastructure itself must be rebuilt, initialize the Proxmox environment first.

Run:

```bash
ansible-playbook ansible/playbooks/proxmox-bootstrap.yml
```

Verify the Proxmox environment and required VM template before continuing.

The environment uses the repository-defined Ubuntu VM template and Proxmox Terraform configuration.

---

## 12. Step 6 — Recreate VMs with Terraform

Change to the development Proxmox environment:

```bash
cd environments/dev/proxmox
```

Initialize Terraform:

```bash
terraform init
```

Validate the configuration:

```bash
terraform validate
```

Review the execution plan:

```bash
terraform plan
```

Only after reviewing the plan should infrastructure be applied:

```bash
terraform apply
```

Terraform is responsible for infrastructure provisioning. Kubernetes configuration is handled by Ansible.

---

## 13. Step 7 — Rebuild the Kubernetes Platform

After the required VMs are available and the Kubernetes state has been reset when required, run the main Ansible site playbook:

```bash
cd /home/teachme/Documents/repo/repoku/platform-engineering-lab

ansible-playbook ansible/playbooks/site.yml
```

The actual play order is:

```text
1.  Load Balancers
2.  Kubernetes Common Configuration
3.  First Control Plane
4.  Workstation Kubeconfig
5.  Additional Control Planes
6.  Control-Plane Metrics
7.  Helm
8.  Cilium
9.  Workers
10. NFS Server
11. NFS CSI
12. Argo CD
13. GitOps Bootstrap
14. etcd Backup
15. Kubernetes Platform Validation
```

This order is important because later layers depend on earlier infrastructure and Kubernetes services.

---

## 14. Step 8 — Verify Kubernetes Control Plane

After the control-plane configuration completes:

```bash
kubectl get nodes -o wide
```

Verify the expected control-plane nodes:

```text
cp01
cp02
cp03
```

Check the Kubernetes API:

```bash
kubectl cluster-info
```

Check system workloads:

```bash
kubectl get pods -A
```

Verify the control-plane nodes eventually reach:

```text
Ready
```

Do not continue to application-level validation if the Kubernetes control plane is not healthy.

---

## 15. Step 9 — Verify Workstation Kubeconfig

The `kubeconfig` role is part of the main Ansible site execution.

Verify that the operator workstation can access the reconstructed cluster:

```bash
kubectl cluster-info
```

Then:

```bash
kubectl get nodes
```

The kubeconfig must reference the Kubernetes API VIP rather than an individual control-plane node for normal HA operation:

```text
192.168.1.30:6443
```

---

## 16. Step 10 — Verify Cilium Networking

Check Cilium:

```bash
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
```

Check Cilium nodes:

```bash
kubectl get ciliumnodes
```

Verify that Cilium is operating on the expected nodes.

Because Cilium is configured as the kube-proxy replacement, a separate kube-proxy DaemonSet is not expected.

---

## 17. Step 11 — Verify Gateway API

Verify the Gateway:

```bash
kubectl get gateway -A
```

Expected Gateway:

```text
nginx-gateway
```

Expected LoadBalancer address:

```text
192.168.1.240
```

Verify HTTPRoutes:

```bash
kubectl get httproute -A
```

Expected application routes include:

```text
nginx-route
argocd-route
grafana-route
```

Inspect the nginx route if required:

```bash
kubectl describe httproute nginx-route -n default
```

Verify that Gateway and HTTPRoute status conditions are healthy, including `ResolvedRefs=True` where cross-namespace references are used.

---

## 18. Step 12 — Verify NFS and CSI

Verify the NFS server:

```text
192.168.1.27
```

Check StorageClasses:

```bash
kubectl get storageclass
```

Check PVs and PVCs:

```bash
kubectl get pv
kubectl get pvc -A
```

Verify the NFS CSI components:

```bash
kubectl get pods -A | grep -i nfs
```

Validate an actual read/write operation when the recovery test includes persistent workloads.

Remember that recreating Kubernetes objects does not recreate application data. Persistent data must come from the appropriate backup or retained storage.

---

## 19. Step 13 — Verify Argo CD

Check Argo CD components:

```bash
kubectl get pods -n argocd
```

Verify the Argo CD applications:

```bash
kubectl get applications -n argocd
```

Expected applications include:

```text
dev-gateway
dev-monitoring
dev-nginx
```

The expected state is:

```text
Synced
Healthy
```

Verify that the GitOps repository and configured application paths are accessible.

---

## 20. Step 14 — Verify GitOps-Managed Gateway Configuration

The Gateway configuration is managed through GitOps.

Expected manifests include:

```text
argocd-reference-grant.yaml
argocd-route.yaml
cilium-l2-announcement-policy.yaml
cilium-lb-ip-pool.yaml
grafana-reference-grant.yaml
grafana-route.yaml
nginx-gateway.yaml
nginx-reference-grant.yaml
nginx-route.yaml
```

Cross-namespace Gateway references must have the corresponding `ReferenceGrant`.

For example, if a route references a backend service in another namespace, verify both:

```bash
kubectl get httproute -A
kubectl get referencegrant -A
```

A route with:

```text
ResolvedRefs=False
```

should be investigated before considering the GitOps layer recovered.

---

## 21. Step 15 — Verify Monitoring

Monitoring is deployed through Argo CD using the kube-prometheus-stack configuration.

Check the monitoring namespace:

```bash
kubectl get pods -n monitoring -o wide
```

Check monitoring services:

```bash
kubectl get svc -n monitoring
```

Verify the Prometheus resource:

```bash
kubectl get prometheus -n monitoring
```

Verify that monitoring workloads become Ready.

The expected external traffic path is:

```text
Client
  |
  v
NPM 192.168.1.3
  |
  v
Gateway 192.168.1.240
  |
  v
grafana-route
  |
  v
Grafana
```

---

## 22. Step 16 — Verify etcd Backup

The `etcd_backup` role is part of the main Ansible platform configuration.

Verify the backup directory:

```bash
ls -lah /var/backups/etcd
```

Verify the service:

```bash
systemctl status etcd-backup.service --no-pager
```

Verify the timer:

```bash
systemctl status etcd-backup.timer --no-pager
```

Verify that the timer is enabled and active:

```bash
systemctl is-enabled etcd-backup.timer
systemctl is-active etcd-backup.timer
```

The backup design includes:

* local etcd snapshots
* off-node backup storage
* retention management
* integrity verification
* isolated restore validation

The existence of an automated backup configuration does not by itself prove that a valid backup exists. Inspect the latest snapshot and backup logs.

---

## 23. Step 17 — Run Automated Platform Validation

The final role in `site.yml` is:

```text
k8s_validation
```

It performs automated Kubernetes platform validation after the platform components have been configured.

The full validation can be rerun independently:

```bash
ansible-playbook ansible/playbooks/site.yml --tags k8s_validation
```

Before rerunning validation, verify Ansible connectivity and inventory state.

Additional platform checks should include:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get storageclass
kubectl get pv
kubectl get pvc -A
kubectl get gateway -A
kubectl get httproute -A
kubectl get applications -n argocd
```

Automated validation confirms the expected platform state but does not replace end-to-end disaster recovery testing.

---

## 24. Step 18 — Validate External Access

Validate the complete application path:

```text
Client
  |
  v
NPM
  |
  v
Kubernetes Gateway
  |
  v
HTTPRoute
  |
  v
Service
  |
  v
Pod
```

Validate:

* nginx
* Argo CD
* Grafana

Confirm that:

* DNS resolves correctly;
* TLS terminates correctly at NPM;
* NPM can reach the Gateway;
* Gateway routes are resolved;
* backend services are available;
* applications return expected responses.

For nginx, the expected integration response is:

```text
Welcome to nginx!
```

---

## 25. Step 19 — Validate HA Components

Verify Keepalived:

```bash
systemctl status keepalived --no-pager
```

Verify HAProxy:

```bash
systemctl status haproxy --no-pager
```

Verify the API VIP:

```text
192.168.1.30:6443
```

Verify the control-plane nodes:

```bash
kubectl get nodes -o wide
```

The normal operating state should contain:

```text
3 control-plane nodes
2 worker nodes
```

with all expected nodes in `Ready` state.

A full disaster recovery validation should additionally include controlled failure scenarios when those tests are explicitly within scope.

---

## 26. Step 20 — Final Platform Checklist

The reconstruction is considered operational only after the following areas have been checked.

## Infrastructure Checklist

* [ ] Proxmox available
* [ ] Required VM storage available
* [ ] Terraform configuration validated
* [ ] Expected VMs available

## Load balancing

* [ ] lb01 available
* [ ] lb02 available
* [ ] HAProxy running
* [ ] Keepalived running
* [ ] API VIP `192.168.1.30` available

## Kubernetes

* [ ] cp01 Ready
* [ ] cp02 Ready
* [ ] cp03 Ready
* [ ] worker01 Ready
* [ ] worker02 Ready
* [ ] Kubernetes API healthy
* [ ] system pods healthy

## Networking

* [ ] Cilium pods healthy
* [ ] Cilium nodes available
* [ ] kube-proxy replacement operational
* [ ] Gateway available
* [ ] Gateway LoadBalancer IP `192.168.1.240` available
* [ ] HTTPRoutes resolved

## Storage

* [ ] NFS server available
* [ ] NFS CSI components healthy
* [ ] StorageClass available
* [ ] PV/PVC state verified
* [ ] Persistent read/write test completed when applicable

## GitOps

* [ ] Argo CD available
* [ ] `dev-gateway` Synced and Healthy
* [ ] `dev-monitoring` Synced and Healthy
* [ ] `dev-nginx` Synced and Healthy
* [ ] ReferenceGrants present where required

## Observability

* [ ] Monitoring namespace healthy
* [ ] Prometheus available
* [ ] Grafana available
* [ ] Control-plane metrics available
* [ ] Expected monitoring targets available

## Backup

* [ ] etcd backup service configured
* [ ] etcd backup timer enabled
* [ ] recent etcd snapshot exists
* [ ] off-node backup available
* [ ] backup integrity verified

## Validation

* [ ] `k8s_validation` completed successfully
* [ ] Kubernetes validation completed
* [ ] Gateway validation completed
* [ ] GitOps validation completed
* [ ] monitoring validation completed
* [ ] external access validated

---

## 27. Success Criteria

A successful Kubernetes disaster recovery reconstruction results in:

1. Proxmox infrastructure available.
2. Terraform-managed VMs recreated successfully.
3. Kubernetes control plane rebuilt successfully.
4. Three control-plane nodes are `Ready`.
5. Two worker nodes are `Ready`.
6. Kubernetes API is reachable through `192.168.1.30:6443`.
7. Cilium networking is operational.
8. Gateway API is operational.
9. Gateway LoadBalancer IP `192.168.1.240` is available.
10. NFS and NFS CSI are operational.
11. Argo CD is operational.
12. GitOps applications are `Synced` and `Healthy`.
13. Monitoring is operational.
14. Automated etcd backup is configured and producing valid backups.
15. Automated Kubernetes validation succeeds.
16. External application access works through the expected NPM -> Gateway -> HTTPRoute path.

---

## 28. Recovery Decision Path

Use the following decision path before choosing this runbook:

```text
Kubernetes problem
       |
       v
Is the failure limited to one node?
       |
    +--+--+
    |     |
   Yes    No
    |     |
    v     v
Node    Is etcd state still
Recovery recoverable?
          |
       +--+--+
       |     |
      Yes    No
       |     |
       v     v
Control  etcd restore
Plane    or full
Recovery reconstruction
```

Use the appropriate recovery procedure:

| Situation                                                   | Procedure                             |
| ----------------------------------------------------------- | ------------------------------------- |
| Single worker failure                                       | Worker node recovery                  |
| Single control-plane failure                                | Control-plane node recovery           |
| Multiple control-plane failures with recoverable etcd state | Control-plane recovery                |
| etcd state must be restored from snapshot                   | etcd restore                          |
| Kubernetes state must be rebuilt                            | This runbook                          |
| Application data must be restored                           | Application-specific backup procedure |

---

## 29. Operational Safety Rules

## 29.1 Do not reset a healthy cluster unnecessarily

A node-level failure does not automatically justify a full cluster reconstruction.

Use node recovery procedures whenever the remaining cluster state is healthy and recoverable.

## 29.2 Protect persistent data

Before destructive reconstruction:

```bash
kubectl get pv
kubectl get pvc -A
```

Understand which workloads use persistent storage.

## 29.3 Do not bypass the reconstruction safety gate casually

The reconstruction playbook intentionally defaults to:

```yaml
reconstruction_allow_persistent_data: false
k8s_reset_confirm: false
```

Explicit overrides represent operator authorization and should only be used after verifying the recovery scope.

## 29.4 Preserve independent backups

GitOps can recreate Kubernetes objects, but it does not replace:

* database backups
* media backups
* persistent application data
* secrets
* external system data

## 29.5 Validate after every major layer

Do not wait until the end to discover that an earlier layer failed.

Recommended progression:

```text
Infrastructure
    |
    v
Load Balancers
    |
    v
Kubernetes API
    |
    v
Cilium
    |
    v
Workers
    |
    v
Storage
    |
    v
Argo CD
    |
    v
GitOps
    |
    v
Monitoring
    |
    v
External Access
```

---

## 30. Validation Record

For each reconstruction exercise, record:

```text
Date:
Operator:
Repository commit:
Terraform commit/state:
Infrastructure status:
Control-plane status:
Worker status:
Cilium status:
Gateway status:
NFS/CSI status:
Argo CD status:
GitOps status:
Monitoring status:
etcd backup status:
Automated validation result:
External access result:
Issues found:
Corrective actions:
Final result:
```

Historical validation results should be recorded separately from the current live cluster state.

---

## 31. Related Documentation

* [Ansible Architecture](../ansible/architecture.md)
* [Kubernetes HA Architecture](../architecture/kubernetes-ha.md)
* [Cluster Bootstrap](../kubernetes/cluster-bootstrap.md)
* [Cilium Networking](../kubernetes/networking-cilium.md)
* [NFS Storage](../kubernetes/storage-nfs.md)
* [Argo CD / GitOps](../gitops/argocd.md)
* [Prometheus and Monitoring](../observability/prometheus.md)
* [Control Plane Node Recovery](control-plane-node-recovery.md)
* [Worker Node Recovery](worker-node-recovery.md)
* [etcd Restore Runbook](etcd-restore-runbook.md)
* [Disaster Recovery Operations](../operations/disaster-recovery.md)
* [etcd Backup and Restore](../operations/etcd-backup-and-restore.md)
* [Platform Validation](../operations/validation.md)
* [Cluster Reconstruction Validation](../validation/kubernetes-cluster-reconstruction.md)

---

## 32. Recovery Philosophy

The platform is designed around layered recovery:

```text
Infrastructure as Code
        +
Configuration as Code
        +
GitOps
        +
etcd Backups
        +
Application Backups
        =
Recoverable Platform
```

Terraform reconstructs infrastructure.

Ansible reconstructs the Kubernetes platform.

Cilium provides cluster networking.

NFS and CSI provide persistent storage integration.

Argo CD restores GitOps-managed desired state.

etcd backups preserve Kubernetes control-plane state for cases where snapshot restoration is appropriate.

Application-specific backups protect data that cannot be recreated from Kubernetes manifests alone.

The recovery process therefore separates **infrastructure recovery**, **Kubernetes state recovery**,
**platform configuration recovery**, and **application data recovery**
rather than treating them as a single operation.
