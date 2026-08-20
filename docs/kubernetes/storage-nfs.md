# Kubernetes Storage with NFS

## Overview

The Kubernetes platform uses NFS-based persistent storage for workloads
that require data to survive Pod recreation or rescheduling.

The storage stack consists of:

- NFS server
- NFS client support
- NFS CSI driver
- StorageClass
- PersistentVolume
- PersistentVolumeClaim

Storage is configured through Ansible and integrated into the Kubernetes
platform bootstrap.

## Storage Architecture

```text
Kubernetes Workload
        |
        v
       PVC
        |
        v
       PV
        |
        v
 StorageClass
        |
        v
    NFS CSI
        |
        v
   NFS Server
```

Kubernetes interacts with the NFS backend through the CSI driver rather
than managing NFS directly.

## Configuration

### NFS Server

The NFS server is configured using:

```text
ansible/roles/nfs_server/
```

The role manages the NFS package, export directory, exports, and
required services.

### NFS Client and CSI

Kubernetes nodes require NFS client support.

The NFS CSI integration is configured using:

```text
ansible/roles/nfs_csi/
```

This allows Kubernetes to provision and mount NFS-backed persistent
storage through standard Kubernetes storage resources.

### Kubernetes Storage

Storage manifests are stored under:

```text
kubernetes/storage/nfs/
```

Including:

```text
storageclass.yaml
pvc.yaml
test/
```

## Persistent Storage

The StorageClass defines the storage provisioning behavior:

```bash
kubectl get storageclass
```

Inspect it when required:

```bash
kubectl describe storageclass <STORAGE_CLASS_NAME>
```

Check PersistentVolumes:

```bash
kubectl get pv
```

Check PersistentVolumeClaims:

```bash
kubectl get pvc -A
```

A successfully provisioned PVC should report:

```text
Bound
```

## Validation

### NFS Connectivity Troubleshooting

From a Kubernetes node:

```bash
showmount -e <NFS_SERVER_IP>
```

The expected NFS export should be visible.

### CSI Driver

```bash
kubectl get pods -A | grep -i nfs
```

NFS CSI controller and node components should be running.

### Persistent Read / Write

Deploy the test workload:

```bash
kubectl apply -f kubernetes/storage/nfs/test/pod.yaml
```

Check the Pod:

```bash
kubectl get pod -o wide
```

Write data:

```bash
kubectl exec <POD_NAME> -- \
  sh -c 'echo "persistent-storage-test" > /mnt/data/test.txt'
```

Read it back:

```bash
kubectl exec <POD_NAME> -- \
  cat /mnt/data/test.txt
```

Expected:

```text
persistent-storage-test
```

### Persistence After Pod Recreation

Delete and recreate the test Pod:

```bash
kubectl delete pod <POD_NAME>

kubectl apply -f kubernetes/storage/nfs/test/pod.yaml
```

Verify the data:

```bash
kubectl exec <POD_NAME> -- \
  cat /mnt/data/test.txt
```

Expected:

```text
persistent-storage-test
```

This confirms that the data survives the Pod lifecycle.

### Cross-Node Validation

Check the current node:

```bash
kubectl get pod <POD_NAME> -o wide
```

Recreate the Pod and verify whether it can be scheduled on another
node:

```bash
kubectl delete pod <POD_NAME>

kubectl apply -f kubernetes/storage/nfs/test/pod.yaml

kubectl get pod <POD_NAME> -o wide
```

The previously written data should remain available.

This validates that the persistent storage is independent from the
lifecycle and location of an individual Pod.

## Validation Summary

| Validation | Expected Result |
|---|---|
| NFS export | Reachable |
| StorageClass | Available |
| PV | Available / Bound |
| PVC | Bound |
| NFS CSI controller | Running |
| NFS CSI node components | Running |
| Persistent write | Successful |
| Persistent read | Successful |
| Data after Pod recreation | Preserved |
| Data after rescheduling | Preserved |

## Troubleshooting

### PVC Pending

Check:

```bash
kubectl describe pvc <PVC_NAME> -n <NAMESPACE>
kubectl get storageclass
kubectl get pods -A | grep -i nfs
```

### NFS Connectivity

From a Kubernetes node:

```bash
ping <NFS_SERVER_IP>
showmount -e <NFS_SERVER_IP>
```

Verify the NFS server, exports, network connectivity, and firewall
configuration.

### Mount Failure

Inspect the affected Pod:

```bash
kubectl describe pod <POD_NAME>
```

Check CSI components:

```bash
kubectl get pods -A | grep -i nfs
```

## Operational Considerations

NFS provides persistent shared storage but is not a backup system.

A future backup and disaster recovery strategy should cover:

- NFS data
- Kubernetes objects
- Restore procedures
- Restore validation
- Storage failure scenarios

Availability and data protection should be treated as separate
concerns.

## Security Considerations

NFS exports should be restricted to the required Kubernetes nodes and
networks.

Future hardening includes:

- Restricted NFS exports
- Network segmentation
- Access controls
- Backup encryption
- Storage monitoring

## Future Improvements

- [ ] Storage monitoring
- [ ] NFS backup automation
- [ ] Restore testing
- [ ] Disaster recovery procedure
- [ ] Storage failure testing
- [ ] Storage capacity alerting
- [ ] Alternative storage backend

## Related Documentation

```text
docs/
├── architecture/
│   └── kubernetes-ha.md
├── ansible/
│   └── architecture.md
├── terraform/
│   └── architecture.md
├── kubernetes/
│   ├── cluster-bootstrap.md
│   ├── networking-cilium.md
│   └── storage-nfs.md
├── gitops/
│   └── argocd.md
├── observability/
│   └── prometheus.md
└── operations/
    ├── startup-shutdown.md
    ├── validation.md
    └── control-plane-failure.md
```
