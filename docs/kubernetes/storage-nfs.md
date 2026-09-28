# Kubernetes Storage with NFS

## Overview

The Kubernetes platform uses NFS-based persistent storage for workloads
that require data to survive Pod recreation or rescheduling.

The storage stack consists of:

* NFS server
* NFS client support
* NFS CSI driver
* StorageClass
* PersistentVolume
* PersistentVolumeClaim

Storage is configured through Ansible and integrated into the Kubernetes
platform bootstrap.

The NFS server provides the storage backend, while the NFS CSI driver
integrates the backend with Kubernetes storage resources.

Persistent storage and backup are separate concerns. NFS provides
persistent data storage but does not by itself provide backup or disaster
recovery protection.

## Storage Architecture

The storage flow is:

```text id="5jz1sc"
Kubernetes Workload
        |
        v
PersistentVolumeClaim
        |
        v
PersistentVolume
        |
        v
StorageClass
        |
        v
NFS CSI Driver
        |
        v
NFS Server
```

Kubernetes interacts with the NFS backend through the CSI driver rather
than managing NFS directly.

The storage architecture separates the Kubernetes storage abstraction from
the underlying NFS infrastructure.

## NFS Server

The NFS server is configured using:

```text id="aw3c8g"
ansible/roles/nfs_server/
```

The role manages the NFS server package, export directory, exports, and
required services.

The current NFS server is:

```text id="b9plmz"
k8s-nfs01
192.168.1.27
```

The NFS server is provisioned as part of the infrastructure and configured
through Ansible.

## NFS Client and CSI

Kubernetes nodes require NFS client support so that NFS-backed volumes can
be mounted.

The NFS CSI integration is configured using:

```text id="h2y8vb"
ansible/roles/nfs_csi/
```

The CSI driver allows Kubernetes to provision and mount NFS-backed
persistent storage through standard Kubernetes storage resources.

The storage integration is therefore:

```text
Kubernetes
    |
    v
NFS CSI Driver
    |
    v
NFS Server
```

## Kubernetes Storage Resources

Storage manifests are maintained as part of the Kubernetes configuration
and are reconciled through the platform's GitOps workflow where applicable.

The storage configuration should be located under the repository's
Kubernetes environment configuration.

The relevant resources include:

```text id="yqypz0"
StorageClass
PersistentVolume
PersistentVolumeClaim
```

Inspect the repository before changing storage resources so that Git remains
the source of truth for persistent Kubernetes configuration.

## StorageClass

The StorageClass defines how Kubernetes provisions persistent storage.

List available StorageClasses:

```bash id="9y51d8"
kubectl get storageclass
```

Inspect a StorageClass when required:

```bash id="j4j4fk"
kubectl describe storageclass <STORAGE_CLASS_NAME>
```

The StorageClass should reference the NFS CSI provisioner used by the
cluster.

## PersistentVolumes

PersistentVolumes represent persistent storage resources available to
Kubernetes.

List PersistentVolumes:

```bash id="fr3zv0"
kubectl get pv
```

Inspect a specific PersistentVolume:

```bash id="kpfwzq"
kubectl describe pv <PV_NAME>
```

A successfully provisioned volume should transition to the expected
binding state when it is associated with a PersistentVolumeClaim.

## PersistentVolumeClaims

PersistentVolumeClaims provide workloads with a Kubernetes request for
persistent storage.

List PersistentVolumeClaims:

```bash id="z0j7fj"
kubectl get pvc -A
```

Inspect a specific PVC:

```bash id="r7f4j5"
kubectl describe pvc <PVC_NAME> -n <NAMESPACE>
```

A successfully provisioned PVC should report:

```text id="l0y2p9"
Bound
```

A PVC remaining in `Pending` state requires investigation of the
StorageClass, CSI driver, requested capacity, access mode, and related
events.

## Storage Lifecycle

The normal storage lifecycle is:

```text id="x5tx0f"
PVC Created
    |
    v
StorageClass
    |
    v
NFS CSI Provisioner
    |
    v
PersistentVolume
    |
    v
NFS Directory / Export
    |
    v
Pod Mount
```

The exact lifecycle depends on the CSI provisioner and StorageClass
configuration.

Deleting or recreating a Pod does not inherently remove the persistent
storage represented by its PVC.

## Validation

Storage validation should verify:

* NFS connectivity
* CSI controller health
* CSI node component health
* StorageClass availability
* PersistentVolume provisioning
* PersistentVolumeClaim binding
* Persistent read/write operations
* Persistence after Pod recreation
* Persistence after workload rescheduling

## NFS Connectivity Validation

From a Kubernetes node, verify that the NFS server is reachable:

```bash id="m7g0y2"
showmount -e <NFS_SERVER_IP>
```

The expected NFS export should be visible.

Basic network connectivity can also be checked with:

```bash id="t8c4j1"
ping <NFS_SERVER_IP>
```

The NFS server address in the current environment is:

```text id="p1j8gc"
192.168.1.27
```

## CSI Driver Validation

Check the NFS CSI components:

```bash id="s2n5kq"
kubectl get pods -A | grep -i nfs
```

The NFS CSI controller and node components should be running.

When troubleshooting, inspect the affected CSI Pod and its logs as
appropriate.

## Persistent Read and Write

Deploy the NFS storage test workload if the test manifest is available in
the repository.

For example:

```bash id="4o6l0a"
kubectl apply -f <NFS_TEST_MANIFEST>
```

Check the Pod:

```bash id="3e9h2k"
kubectl get pod -o wide
```

Write test data:

```bash id="6q2m0b"
kubectl exec <POD_NAME> -- \
  sh -c 'echo "persistent-storage-test" > /mnt/data/test.txt'
```

Read the data back:

```bash id="r3x8qk"
kubectl exec <POD_NAME> -- \
  cat /mnt/data/test.txt
```

Expected result:

```text id="1f6d2c"
persistent-storage-test
```

This confirms that the workload can write to and read from the mounted
persistent volume.

## Persistence After Pod Recreation

Delete and recreate the test Pod:

```bash id="1t5z3m"
kubectl delete pod <POD_NAME>
```

Recreate the workload using the repository's storage test manifest.

Then verify the previously written data:

```bash id="q0x8nv"
kubectl exec <POD_NAME> -- \
  cat /mnt/data/test.txt
```

Expected result:

```text id="9k3v2a"
persistent-storage-test
```

This confirms that the data survives the Pod lifecycle when the same
persistent volume remains attached through its PVC.

## Cross-Node Validation

Check the current Pod placement:

```bash id="8b6x2m"
kubectl get pod <POD_NAME> -o wide
```

Recreate or reschedule the workload and check its placement again:

```bash id="0r4m9c"
kubectl get pod <POD_NAME> -o wide
```

If the workload is scheduled onto another Kubernetes node, verify that the
previously written data remains available.

This validates that the persistent storage is independent from the
lifecycle and location of an individual Pod.

The result depends on normal Kubernetes scheduling and the workload's
resource requirements. A Pod is not guaranteed to move to another node
simply because it is recreated.

## Validation Summary

| Validation                | Expected Result   |
| ------------------------- | ----------------- |
| NFS export                | Reachable         |
| StorageClass              | Available         |
| PV                        | Available / Bound |
| PVC                       | Bound             |
| NFS CSI controller        | Running           |
| NFS CSI node components   | Running           |
| Persistent write          | Successful        |
| Persistent read           | Successful        |
| Data after Pod recreation | Preserved         |
| Data after rescheduling   | Preserved         |

## Troubleshooting

### PVC Pending

Check the PVC:

```bash id="c4x6vb"
kubectl describe pvc <PVC_NAME> -n <NAMESPACE>
```

Check StorageClasses:

```bash id="z7p1mc"
kubectl get storageclass
```

Check CSI components:

```bash id="x8v4nd"
kubectl get pods -A | grep -i nfs
```

Review PVC events for provisioning or mount errors.

### NFS Connectivity

From a Kubernetes node:

```bash id="r2m5pk"
ping <NFS_SERVER_IP>

showmount -e <NFS_SERVER_IP>
```

Verify:

* NFS server availability
* NFS exports
* Network connectivity
* Firewall configuration
* NFS client support

### Mount Failure

Inspect the affected Pod:

```bash id="n5q7yc"
kubectl describe pod <POD_NAME> -n <NAMESPACE>
```

Check the associated PVC and PV:

```bash id="a4k2hs"
kubectl describe pvc <PVC_NAME> -n <NAMESPACE>

kubectl describe pv <PV_NAME>
```

Check CSI components:

```bash id="e1v6mz"
kubectl get pods -A | grep -i nfs
```

If the problem persists, inspect the CSI controller and node logs.

## Operational Considerations

NFS provides persistent shared storage but is not a backup system.

Persistent storage availability and data protection are separate concerns.

A failure of the NFS server can affect workloads that depend on NFS-backed
PersistentVolumes even when the Kubernetes control plane remains healthy.

The platform therefore treats storage as a separate failure domain.

Important operational considerations include:

* NFS server availability
* NFS export configuration
* Network connectivity
* Storage capacity
* CSI driver health
* PVC/PV state
* Backup availability
* Restore procedures
* Restore validation

## Backup and Disaster Recovery

An NFS-backed PVC does not protect the underlying application data from
storage loss, accidental deletion, or other destructive events.

Backup procedures must therefore protect the underlying NFS data separately
from Kubernetes object state.

Kubernetes etcd backups restore Kubernetes control-plane state, but they do
not restore files stored on the NFS server.

The distinction is:

```text id="7n2b6p"
Kubernetes etcd
    |
    +-- Kubernetes object state
    |
    +-- PVC / PV metadata
    |
    +-- Storage configuration

NFS Storage
    |
    +-- Application files
    |
    +-- Persistent workload data
```

A complete recovery procedure may therefore require both Kubernetes state
recovery and separate NFS data recovery.

For control-plane state recovery, see:

```text id="e7v1qz"
docs/disaster-recovery/etcd-restore-runbook.md
```

For full Kubernetes platform reconstruction, see:

```text id="4q0m8s"
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
```

## Security Considerations

NFS exports should be restricted to the required Kubernetes nodes and
networks.

Security considerations include:

* Restricted NFS exports
* Network segmentation
* Access controls
* Storage monitoring
* Backup protection
* Backup encryption where applicable

NFS access should not be exposed beyond the networks and hosts that require
it.

## Failure Domains

The storage architecture introduces a separate storage dependency:

```text id="6d4q9p"
Kubernetes Workload
        |
        v
       PVC
        |
        v
    NFS CSI
        |
        v
   NFS Server
```

A Kubernetes control-plane failure does not inherently imply NFS failure.

Conversely, an NFS server failure can affect persistent workloads while the
Kubernetes API and control plane remain available.

This distinction is important during incident analysis and disaster
recovery.

## Future Improvements

* [ ] Storage monitoring
* [ ] NFS backup automation
* [ ] Restore testing
* [ ] Storage failure testing
* [ ] Storage capacity alerting
* [ ] Storage health alerting
* [ ] Alternative storage backend evaluation

## Related Documentation

```text id="0c7h4m"
docs/

├── architecture/
│   └── kubernetes-ha.md
│
├── ansible/
│   └── architecture.md
│
├── terraform/
│   └── architecture.md
│
├── kubernetes/
│   ├── cluster-bootstrap.md
│   └── networking-cilium.md
│
├── gitops/
│   └── argocd.md
│
├── observability/
│   └── prometheus.md
│
├── operations/
│   ├── startup-shutdown.md
│   ├── validation.md
│   ├── control-plane-failure.md
│   ├── disaster-recovery.md
│   └── etcd-backup-and-restore.md
│
└── disaster-recovery/
    ├── kubernetes-disaster-recovery-runbook.md
    ├── control-plane-node-recovery.md
    ├── worker-node-recovery.md
    └── etcd-restore-runbook.md
```
