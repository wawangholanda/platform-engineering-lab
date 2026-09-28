# etcd Restore Runbook

## Purpose

This runbook describes the recovery procedure for restoring the Kubernetes
control-plane state from an etcd snapshot in the `platform-engineering-lab`
environment.

The procedure is intended for disaster-recovery scenarios where the existing
etcd cluster cannot maintain quorum or its data cannot be recovered through
normal control-plane node replacement.

The environment uses a three-member stacked etcd cluster:

* `k8s-cp01` — `192.168.1.20`
* `k8s-cp02` — `192.168.1.23`
* `k8s-cp03` — `192.168.1.24`

The Kubernetes API is exposed through the shared control-plane endpoint:

```text
192.168.1.30:6443
```

An etcd snapshot restore is a **disaster recovery operation**. It should not
be used for normal single-node control-plane or worker-node replacement.

Before performing a restore, preserve the available cluster state and verify
that normal etcd recovery is not possible.

This procedure focuses on restoring Kubernetes control-plane state from a
known-good etcd snapshot while minimizing unnecessary changes to the
surviving infrastructure.

---

## Recovery Scenario

The normal etcd disaster-recovery scenario is:

```text id="h3p7qk"
etcd failure / quorum loss
          |
          v
verify remaining cluster state
          |
          v
identify known-good snapshot
          |
          v
preserve existing etcd data
          |
          v
stop affected control-plane services
          |
          v
restore etcd snapshot
          |
          v
reconstruct etcd membership
          |
          v
restore Kubernetes API access
          |
          v
validate control plane
          |
          v
validate Cilium, workloads,
storage, and GitOps
```

The three-member etcd cluster normally requires at least two healthy members
to maintain quorum.

A single etcd-member failure should therefore normally be handled through
control-plane node replacement rather than snapshot restoration.

Use this runbook when:

* etcd quorum has been lost.
* Remaining etcd members cannot form a healthy cluster.
* etcd data is corrupted or otherwise unusable.
* A known-good snapshot is required to recover the Kubernetes control-plane
  state.

Before restoring a snapshot, do not unnecessarily reset healthy control-plane
nodes or modify etcd membership.

The restore process must preserve the relationship between the restored etcd
state and the Kubernetes control-plane configuration. After the restore,
validate the Kubernetes API, control-plane components, Cilium, workloads,
persistent storage, and GitOps-managed resources.

---

## When to Use This Runbook

Use this runbook when the Kubernetes control-plane state stored in etcd
cannot be recovered through normal etcd or control-plane recovery.

Typical situations include:

* etcd data is corrupted or unusable.
* etcd quorum has been lost and cannot be recovered normally.
* Kubernetes control-plane state has been lost.
* A known-good point-in-time etcd snapshot is required to restore the
  Kubernetes control-plane state.

Do not use this procedure for a normal single worker-node failure.

For a single control-plane node failure, use:

```text
docs/disaster-recovery/control-plane-node-recovery.md
```

provided that the remaining control-plane nodes and etcd quorum are healthy.

Use this runbook only when restoring the existing etcd state is required.
Restoring etcd does not restore application data stored outside Kubernetes
state, such as files stored on the NFS server.

For a broader Kubernetes reconstruction scenario, use:

```text
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
```

---

## Prerequisites

Before performing an etcd restore, confirm that snapshot recovery is actually
required and identify the snapshot to restore.

### Verify Cluster State

Check the current cluster state:

```bash
kubectl get nodes -o wide
```

Check API server readiness:

```bash
kubectl get --raw='/readyz?verbose'
```

If the Kubernetes API is still healthy and the etcd cluster can be recovered
normally, do not perform a snapshot restore.

### Identify Available Snapshots

Check the configured etcd backup location:

```bash
ls -lah /var/backups/etcd
```

If backups are stored on NFS or another mounted filesystem, verify the mount:

```bash
mount | grep nfs
```

Confirm that the intended snapshot exists and record:

* Snapshot filename.
* Snapshot timestamp.
* Snapshot size.
* Backup location.
* Expected recovery point.

### Verify Backup Integrity

Use the installed `etcdctl` tooling to inspect the snapshot when supported:

```bash
ETCDCTL_API=3 etcdctl snapshot status <snapshot-file>
```

The snapshot should be readable and correspond to the intended recovery
point.

### Preserve Existing State

Before making destructive changes, preserve the existing etcd configuration
and data where possible.

Important paths include:

```text
/etc/kubernetes/
/var/lib/etcd/
```

Do not overwrite the existing etcd data directory until the selected snapshot
has been verified and the restore procedure is ready to proceed.

### Verify Recovery Requirements

Confirm that application data recovery is understood separately from etcd
recovery.

An etcd snapshot contains Kubernetes control-plane state and metadata. It
does not contain application files stored on external s

---

## Recovery Safety

An etcd restore is a **destructive control-plane state operation**. The
selected snapshot becomes the source of the restored Kubernetes state.

Before proceeding:

1. Identify the exact snapshot to restore.
2. Verify that the snapshot is readable.
3. Confirm that the existing etcd cluster cannot be recovered through normal
   quorum recovery.
4. Record the current cluster and failure state.
5. Preserve the existing etcd configuration and data where possible.
6. Confirm that application-data recovery requirements are handled separately.

Do not overwrite a healthy etcd cluster with an older snapshot without first
confirming that snapshot recovery is required.

Be aware that restoring an older snapshot may cause Kubernetes objects created
after the snapshot timestamp to be absent from the restored control-plane
state.

Application data stored outside etcd must also be considered separately. An
etcd restore does not restore files stored on NFS or other external storage.

Before executing the destructive restore operation, record the selected
snapshot and current recovery decision:

```text id="2m8c6v"
Snapshot:

Snapshot timestamp:

Current etcd state:

Reason for restore:

Current API state:

Application data recovery required:

Operator:

Recover
```

---

## Snapshot Validation

Before restoring an etcd snapshot, verify that the selected backup is
readable and corresponds to the intended recovery point.

List the available snapshots:

```bash
ls -lah /var/backups/etcd
```

Select the snapshot that matches the required recovery point and record its
filename and timestamp.

Use `etcdctl` to inspect the snapshot when supported by the installed tooling:

```bash
ETCDCTL_API=3 etcdctl snapshot status <snapshot-file>
```

Confirm:

* The snapshot is readable.
* The snapshot timestamp is appropriate for the recovery requirement.
* The snapshot size is reasonable compared with previous backups.
* The snapshot is the intended backup for this recovery operation.

If the snapshot cannot be inspected or appears incomplete, do not use it for
the restore until its integrity and origin have been verified.

Record the selected snapshot before continuing:

```text id="1x7c4n"
Snapshot file:

Snapshot timestamp:

Snapshot size:

Validation result:

Selected for restore: yes / no
```

---

## Restore Preparation

Before restoring the etcd snapshot, determine the recovery scope and prepare
the affected control-plane components.

The restore procedure differs depending on whether the recovery involves:

* A single etcd member.
* The complete three-member etcd cluster.
* A broader Kubernetes control-plane reconstruction.

The existing etcd configuration and data must be preserved before destructive
changes are made.

Record the current configuration:

```bash id="7y2p4m"
ls -lah /etc/kubernetes/
ls -lah /var/lib/etcd/
```

If the existing etcd data is still accessible, preserve it before proceeding
with the restore:

```bash id="3m8kq7"
cp -a /var/lib/etcd /var/lib/etcd.pre-restore
```

The backup location and preservation method may be adjusted according to the
available disk space and the recovery scenario.

Stop the affected Kubernetes control-plane components as required by the
restore procedure.

For a static-pod control plane, inspect the manifests before making changes:

```bash id="9c4v2n"
ls -lah /etc/kubernetes/manifests/
```

Do not remove or modify control-plane manifests unless required by the
specific restore procedure.

Before proceeding to the destructive restore operation, confirm:

```text id="5f6m2r"
Snapshot validated
       +
Existing state preserved
       +
Recovery scope confirmed
       +
Control-plane services prepared
       |
       v
Ready to restore
```

---

## Restore Snapshot

The project includes etcd backup and restore tooling through the
`etcd_backup` Ansible role.

Inspect the installed restore service:

```bash id="q8x3m1"
systemctl status etcd-restore.service --no-pager
```

Inspect the installed backup and restore tooling:

```bash id="n4k7p2"
ls -lah /usr/local/bin/
```

Before executing the restore, identify the project-provided restore script and
review its configured snapshot path and restore behavior.

The exact restore command must follow the generated project restore tooling
and the installed etcd version.

Do not invent a new restore path manually when the project-provided restore
automation is available.

The restore operation should conceptually perform:

```text id="7c2m9v"
known-good snapshot
        |
        v
etcd snapshot restore
        |
        v
restored etcd data directory
        |
        v
etcd starts with restored state
        |
        v
kube-apiserver reconnects
```

Because restoring a snapshot changes the Kubernetes control-plane state,
verify the selected snapshot one final time immediately before executing the
destructive restore operation.

After the restore completes, do not assume the Kubernetes API or workloads
are healthy. Continue with etcd and Kubernetes validation before considering
the recovery successful.

---

## Restore Data Directory

The etcd restore process reconstructs the etcd data directory from the
selected snapshot.

The existing etcd data directory must not be overwritten until the selected
snapshot has been validated and the current data has been preserved.

The conceptual restore flow is:

```text
known-good snapshot
        |
        v
etcd snapshot restore
        |
        v
new etcd data directory
        |
        v
etcd starts
        |
        v
kube-apiserver reconnects
```

The restore tooling should determine the target data directory and the
required etcd configuration. Follow the project-provided restore script
rather than manually creating a different etcd data layout.

After the restore operation, verify the resulting data directory:

```bash id="k2m7v4"
ls -lah /var/lib/etcd/
```

Verify that the etcd process or static pod is using the expected data
directory and configuration before starting the control-plane components.

If the restore produces an unexpected directory structure, ownership,
permissions, or configuration, stop the recovery and correct the restore
before starting etcd.

Do not delete the preserved pre-restore etcd data until the recovery has been
fully validated.

---

## Start etcd

After the snapshot has been restored and the restored data directory has been
verified, start the etcd component according to the control-plane
configuration.

If etcd is managed as a system service, check its state:

```bash id="7q3m8k"
systemctl status etcd --no-pager
```

If etcd is managed through the Kubernetes static-pod mechanism, inspect the
etcd pod:

```bash id="4m9v2x"
kubectl get pods \
  -n kube-system \
  -l component=etcd \
  -o wide
```

Check the etcd logs if the component does not become healthy:

```bash id="8k5n1p"
journalctl -u etcd --no-pager -n 100
```

For a static-pod deployment, inspect the container logs using the configured
container runtime when required.

The expected recovery flow is:

```text id="6w2r9c"
restored etcd data
        |
        v
etcd starts
        |
        v
etcd becomes healthy
        |
        v
kube-apiserver reconnects
        |
        v
Kubernetes API becomes available
```

Do not proceed to application validation until etcd reports healthy and the
Kubernetes API can communicate with the restored control-plane state.

---

## Validate etcd

After starting etcd, verify that the restored etcd endpoint is healthy.

Use the installed `etcdctl` tooling:

```bash id="2r7m4k"
ETCDCTL_API=3 etcdctl endpoint health
```

The endpoint should report a healthy status.

Check endpoint status:

```bash id="9k3p1v"
ETCDCTL_API=3 etcdctl endpoint status
```

Review the returned endpoint, database size, revision, and leader information
to confirm that etcd is operating normally.

For a three-member stacked etcd cluster, verify the membership when the
cluster is expected to be fully reconstructed:

```bash id="5m8q2x"
ETCDCTL_API=3 etcdctl member list
```

Confirm that the expected etcd members are present and that the cluster has
the required quorum for the recovery scenario.

If etcd is unhealthy, has unexpected membership, or cannot establish the
required quorum, stop the recovery procedure and investigate etcd before
continuing with Kubernetes API validation.

Do not proceed to workload or GitOps validation until the restored etcd stat

---

## Validate Kubernetes API

Once etcd is healthy, verify that the Kubernetes API server can reconnect to
the restored control-plane state.

Check cluster nodes:

```bash id="4n8x2m"
kubectl get nodes -o wide
```

The expected control-plane nodes should be present.

Verify API server readiness:

```bash id="7m3q9v"
kubectl get --raw='/readyz?verbose'
```

The readiness checks should report successful results.

Confirm that the Kubernetes API remains accessible through the shared
control-plane endpoint:

```bash id="6k2p4x"
kubectl cluster-info
```

The expected API endpoint is:

```text id="9v5m1q"
192.168.1.30:6443
```

Verify the API server pods:

```bash id="3x7n8m"
kubectl get pods \
  -n kube-system \
  -l component=kube-apiserver \
  -o wide
```

If the API server is not ready, inspect its logs and the restored etcd
connection before continuing.

A successful etcd restore does not by itself guarantee that every Kubernetes
component or application has returned to its expected state. Continue with
Kubernetes object and platform validation after the API become

---

## Validate Kubernetes State

After the Kubernetes API becomes healthy, verify that the expected Kubernetes
objects are present in the restored control-plane state.

Check namespaces:

```bash id="8q4m2v"
kubectl get namespaces
```

Check workloads:

```bash id="5n7k3x"
kubectl get deployments -A
kubectl get statefulsets -A
```

Check services:

```bash id="2m9p6v"
kubectl get services -A
```

Check configuration and credentials metadata:

```bash id="4x8q1m"
kubectl get secrets -A
kubectl get configmaps -A
```

Check CustomResourceDefinitions:

```bash id="7v3n5k"
kubectl get crds
```

Verify that the expected platform resources are present, including resources
managed by Cilium, Argo CD, monitoring, and storage components.

Check for workloads that are not running normally:

```bash id="6k2m9p"
kubectl get pods -A
```

Pay particular attention to workloads in states such as:

```text id="3q7v1x"
Pending
CrashLoopBackOff
ImagePullBackOff
ContainerCreating
```

An etcd snapshot restores Kubernetes control-plane state as of the snapshot
point in time. Objects created or modified after that point may therefore be
missing or reverted.

Do not recreate missing resources manually until it has been determined
whether they should be restored from GitOps or another source of truth.

Continue with Argo CD validation after confirming that the core Kubernetes
state is presen

---

## Validate Argo CD

Verify that Argo CD is present and that its applications reflect the restored
Kubernetes state.

Check Argo CD applications:

```bash id="7m2q8v"
kubectl get applications -n argocd
```

For this environment, the expected applications include:

```text id="3n6k1p"
dev-gateway
dev-monitoring
dev-nginx
```

Check synchronization and health status:

```bash id="5v9x2m"
kubectl get applications -n argocd \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
```

Expected healthy applications should report:

```text id="8q4m7n"
Synced    Healthy
```

If an application is missing, first determine whether it existed at the
selected snapshot point.

If the application existed in Git but its Kubernetes resource was absent from
the restored etcd state, GitOps can be used to reconstruct the resource.

Do not assume that a successful etcd restore automatically restores the
current GitOps state. The restored Kubernetes state represents the point in
time captured by the selected snapshot.

If Argo CD reports an application as `OutOfSync` or unhealthy, inspect the
application and its managed resources before continuing:

```bash id="2x7k5m"
kubectl describe application <application-na
```

---

## Validate Networking

After restoring the Kubernetes control-plane state, verify that the Cilium
networking layer and Gateway API resources are available.

Check Cilium agents:

```bash id="6m2p8v"
kubectl get pods \
  -n kube-system \
  -l k8s-app=cilium \
  -o wide
```

All expected Cilium agents should be running and healthy.

Check the Cilium Gateway API resources:

```bash id="4x7n1q"
kubectl get gateway -n default
kubectl get httproute -n default
```

The primary Gateway should be present:

```text id="8v3m5k"
nginx-gateway
```

Check the Gateway status:

```bash id="9q2m6x"
kubectl get gateway nginx-gateway \
  -n default \
  -o wide
```

The expected Gateway address is:

```text id="1k7p4n"
192.168.1.240
```

For cross-namespace routing, verify the required `ReferenceGrant` resources:

```bash id="5m8x2q"
kubectl get referencegrant -A
```

If Gateway API resources are missing or unhealthy, compare the restored
Kubernetes state with the GitOps source of truth before recreating resources
manually.

A successful etcd restore should preserve the Kubernetes networking resource
definitions that existed at the selected snapshot point, but it does not
guarantee that every current GitOps resource is present if it w

---

## Validate Storage

After restoring the Kubernetes control-plane state, verify that the storage
metadata and NFS CSI resources are available.

Check StorageClasses:

```bash id="4m7q2x"
kubectl get storageclass
```

Check PersistentVolumes and PersistentVolumeClaims:

```bash id="8v3n5k"
kubectl get pv
kubectl get pvc -A
```

Verify the NFS CSI components:

```bash id="6q2m9v"
kubectl get pods \
  -A \
  -l app.kubernetes.io/name=csi-driver-nfs
```

For workloads using PVCs, verify that the expected claims remain bound:

```bash id="1x5k8m"
kubectl get pvc -A
```

If a PVC is not bound or a workload cannot mount its volume, inspect the
relevant resources and events:

```bash id="3n7q4p"
kubectl describe pvc <pvc-name> -n <namespace>
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

Remember that an etcd snapshot restores Kubernetes storage metadata, not the
actual application files stored on NFS.

```text id="9m2v6x"
etcd snapshot
    |
    +--> Kubernetes metadata
    |    - StorageClasses
    |    - PV/PVC objects
    |    - CSI configuration
    |
    +--> does NOT contain
         application files on NFS
```

Therefore, a successful etcd restore does not prove that the underlying NFS
application data is available.

If the Kubernetes storage objects are restored but the underlying data is
missing, follow the appropriate storage backup and recovery procedu

---

## Validate Monitoring

After restoring the Kubernetes control-plane state, verify that the
monitoring stack and its Kubernetes resources are available.

Check monitoring pods:

```bash id="7m4q2x"
kubectl get pods -n monitoring -o wide
```

Verify the Prometheus resource:

```bash id="3x8n6k"
kubectl get prometheus -n monitoring
```

Check Alertmanager:

```bash id="5q2v9m"
kubectl get alertmanager -n monitoring
```

Check Grafana resources:

```bash id="8n4m1p"
kubectl get deployments -n monitoring
kubectl get services -n monitoring
```

Verify that the expected monitoring components are running:

```text id="6k7x3q"
Prometheus    → Healthy
Grafana       → Available
Alertmanager  → Available
```

If monitoring resources are missing or out of sync after the restore,
compare the restored Kubernetes state with the GitOps source of truth.

An etcd snapshot restores monitoring resources that existed at the snapshot
point, but it does not restore historical monitoring data stored outside
etcd, such as

---

## Application Data Recovery

If application data was also lost or is unavailable after the etcd restore,
follow the appropriate storage backup and recovery procedure separately.

For NFS-backed applications, verify that the Kubernetes storage objects are
present:

```bash id="7m3q8v"
kubectl get pvc -A
```

Then verify that the corresponding data exists on the NFS storage backend.

The recovery layers should be treated separately:

```text id="4x8n2p"
etcd snapshot
    |
    +--> Kubernetes control-plane state
    |
    +--> Kubernetes metadata
          |
          +--> PV/PVC objects
          +--> Services
          +--> Deployments
          +--> Secrets
          +--> ConfigMaps

NFS backup
    |
    +--> Application files
    +--> Persistent application data
```

Restoring etcd does **not** restore files that existed only on the NFS data
volume.

After restoring application data, validate the affected workloads and confirm
that they can successfully mount their PVCs and access the expected files.

A successful etcd restore must therefore not be interpreted as proof that
application data has

---

## Recovery Success Criteria

etcd recovery is considered successful when the restored Kubernetes
control-plane state and required platform components have been validated.

```text
etcd                       → Healthy
Kubernetes API             → Ready
Kubernetes objects         → Present
Control-plane nodes        → Ready
Cilium                     → Healthy
Gateway API                → Available
Storage metadata           → Present
Argo CD                    → Synced + Healthy
Monitoring                 → Healthy
Application workloads      → Running
Application data           → Separately validated
```

The Kubernetes API must remain accessible through the shared control-plane
endpoint:

```text
192.168.1.30:6443
```

The restored Kubernetes objects should represent the expected state at the
selected snapshot recovery point.

Resources created or modified after the snapshot timestamp must be reviewed
against the GitOps source of truth and o

---

## Relationship to Other Recovery Procedures

Use the appropriate recovery procedure according to the failure scope:

```text id="5m8q2x"
Worker node failure
        |
        v
Worker Node Recovery

Single control-plane node failure
        |
        v
Control-Plane Node Recovery

Kubernetes control-plane state lost,
corrupted, or etcd quorum unrecoverable
        |
        v
etcd Restore Runbook

Entire Kubernetes cluster must be reconstructed
        |
        v
Kubernetes Disaster Recovery Runbook
```

The recovery procedures are intentionally separated by failure scope.

A normal worker-node failure should not trigger etcd restoration.

A single control-plane node failure should normally be handled by replacing
and rejoining the affected node when the remaining etcd members maintain
quorum.

An etcd restore is required when the Kubernetes control-plane state cannot be
recovered through normal node replacement or etcd quorum recovery.

If the infrastructure and Kubernetes platform must be reconstructed more
broadly, use:

```text id="8v3n6k"
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
```

---

## Validation Record

Record the recovery activity and validation results after completing the etcd
restore.

```text id="3q8m5v"
Failure date:

Failure cause:

Snapshot selected:

Snapshot timestamp:

Snapshot validation result:

Existing etcd state preserved:

Restore performed:

etcd health:

etcd membership:

Kubernetes API health:

Control-plane state:

Kubernetes objects validated:

Cilium state:

Gateway API state:

GitOps state:

Storage state:

Monitoring state:

Application data state:

Final result:
```

The completed record should be retained as part of the operational history
for the Kubernetes platform.

The record should clearly distinguish between Kubernetes control-plane state
restored from etcd and application data recovered through separate storage
back
