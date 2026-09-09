# etcd Restore Runbook

## Purpose

This runbook describes the recovery procedure for restoring Kubernetes control-plane state from an etcd snapshot.

An etcd restore is intended for a situation where the Kubernetes control-plane state stored in etcd has been lost, corrupted, or is
otherwise unrecoverable from the existing etcd members.

This is different from rebuilding an individual Kubernetes node or reconstructing the entire platform from Ansible and GitOps.

---

## Recovery Scope

```text
etcd state failure
        ↓
restore known-good snapshot
        ↓
restore Kubernetes control-plane state
        ↓
validate API server
        ↓
validate Kubernetes objects
        ↓
validate workloads
```

The restore operates on Kubernetes **control-plane state**.

It does not replace application data stored on external storage such as NFS.

---

## When to Use This Runbook

Use an etcd restore when:

* etcd data is corrupted.
* etcd quorum cannot be recovered normally.
* Kubernetes API state has been lost.
* A known-good point-in-time etcd snapshot must be restored.

Do not use this procedure for a normal single worker-node failure.

Do not use this procedure for a normal single control-plane node replacement when the remaining control-plane/etcd quorum is healthy.

---

## Prerequisites

Before performing an etcd restore, identify the snapshot to restore.

Check available backups:

```bash
ls -lah /var/backups/etcd
```

If backups are stored on NFS:

```bash
mount | grep nfs
```

Verify the backup file exists and is the intended recovery point.

---

## Recovery Safety

An etcd restore is a destructive control-plane state operation.

Before proceeding:

1. Identify the correct snapshot.
2. Confirm that the snapshot is readable.
3. Confirm that the existing etcd state cannot be recovered through normal quorum recovery.
4. Record the current failure state.
5. Ensure application data recovery requirements are understood separately.

Do not overwrite a healthy etcd cluster with an old snapshot without first confirming that snapshot recovery is required.

---

## Snapshot Validation

List snapshot files:

```bash
ls -lah /var/backups/etcd
```

Use `etcdctl` to inspect the snapshot when supported by the installed tooling.

Example:

```bash
ETCDCTL_API=3 etcdctl snapshot status <snapshot-file>
```

Confirm:

* snapshot is readable
* snapshot belongs to the expected cluster
* snapshot timestamp is appropriate
* snapshot size is reasonable

---

## Restore Preparation

Stop the affected Kubernetes control-plane components as required by the restore procedure.

The exact sequence depends on whether the restore is:

* a single-member recovery
* a full etcd cluster recovery
* a complete control-plane reconstruction

Record the existing etcd configuration before destructive changes.

Important paths typically include:

```text
/etc/kubernetes/
/var/lib/etcd/
```

---

## Restore Snapshot

The project includes etcd restore tooling through the `etcd_backup` role.

Inspect the installed restore tooling:

```bash
systemctl status etcd-restore.service
```

Inspect the restore script:

```bash
ls -lah /usr/local/bin/
```

The exact restore command should follow the generated project restore script and the installed etcd version.

Do not invent a new restore path manually when the project-provided restore automation is available.

---

## Restore Data Directory

The restore process replaces the etcd data directory with data reconstructed from the selected snapshot.

Because this is destructive, verify the snapshot one final time before executing the restore.

Expected conceptual flow:

```text
known-good snapshot
        ↓
etcd snapshot restore
        ↓
new etcd data directory
        ↓
etcd starts
        ↓
kube-apiserver reconnects
```

---

## Start etcd

After the snapshot has been restored, start the etcd service or Kubernetes-managed etcd component according to the control-plane
configuration.

Check:

```bash
systemctl status etcd
```

If etcd is managed through the Kubernetes static pod mechanism, inspect:

```bash
kubectl get pods -n kube-system -l component=etcd
```

---

## Validate etcd

Check etcd health using the available `etcdctl` tooling.

Example:

```bash
ETCDCTL_API=3 etcdctl endpoint health
```

Confirm the restored etcd endpoint reports healthy.

Check endpoint status:

```bash
ETCDCTL_API=3 etcdctl endpoint status
```

---

## Validate Kubernetes API

Once etcd is healthy, validate the API server:

```bash
kubectl get nodes
```

Then:

```bash
kubectl get --raw='/readyz?verbose'
```

The API server should return a healthy readiness response.

---

## Validate Kubernetes State

Check critical objects:

```bash
kubectl get namespaces
kubectl get deployments -A
kubectl get services -A
kubectl get secrets -A
kubectl get configmaps -A
```

Check CRDs:

```bash
kubectl get crds
```

Verify that expected platform objects are present.

---

## Validate Argo CD

Check Argo CD:

```bash
kubectl get applications -n argocd
```

Expected applications should return to their expected state.

For this environment:

```text
dev-gateway      Synced    Healthy
dev-monitoring   Synced    Healthy
dev-nginx        Synced    Healthy
```

If Argo CD applications are missing because they were not included in the restored state, GitOps can be used to reconstruct them.

---

## Validate Networking

Check Cilium:

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
```

Check Gateway API:

```bash
kubectl get gateway -n default
kubectl get httproute -n default
```

For cross-namespace routes:

```bash
kubectl get referencegrant -A
```

---

## Validate Storage

Check StorageClasses:

```bash
kubectl get storageclass
```

Check PV/PVC state:

```bash
kubectl get pv
kubectl get pvc -A
```

Remember:

```text
etcd snapshot
    = Kubernetes metadata/state

NFS storage
    = application data
```

Restoring etcd does not restore files that existed only on the NFS data volume.

---

## Validate Monitoring

Check:

```bash
kubectl get pods -n monitoring
```

Verify Prometheus:

```bash
kubectl get prometheus -n monitoring
```

Confirm Grafana and Alertmanager are available.

---

## Application Data Recovery

If application data was also lost, follow the appropriate storage backup/recovery procedure separately.

For NFS-backed applications, verify:

```bash
kubectl get pvc -A
```

and confirm the corresponding NFS data is available.

A successful etcd restore should not be interpreted as proof that application data has been restored.

---

## Recovery Success Criteria

etcd recovery is successful when:

```text
etcd                       → Healthy
Kubernetes API             → Ready
Kubernetes objects         → Present
Control-plane nodes        → Ready
Cilium                     → Healthy
Storage metadata           → Present
Argo CD                    → Synced + Healthy
Monitoring                 → Healthy
Application data           → Separately validated
```

---

## Relationship to Other Recovery Procedures

Use the appropriate recovery mechanism according to the failure scope:

```text
Worker node failure
        ↓
Worker node recovery

Single control-plane failure
        ↓
Control-plane node recovery

Kubernetes control-plane state lost/corrupted
        ↓
etcd restore

Entire Kubernetes cluster must be reconstructed
        ↓
Kubernetes Disaster Recovery Runbook
```

---

## Validation Record

Record:

```text
Failure date:
Snapshot selected:
Snapshot timestamp:
Snapshot validation result:
Restore performed:
etcd health:
Kubernetes API health:
Control-plane state:
GitOps state:
Networking state:
Storage state:
Application data state:
Final result:
```
