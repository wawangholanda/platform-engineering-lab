# Kubernetes Disaster Recovery

## Overview

This document defines the disaster recovery strategy for the Kubernetes
Platform Engineering Lab.

The recovery architecture is based on four primary principles:

1. Infrastructure is reproducible through Terraform.
2. Kubernetes platform configuration is automated through Ansible.
3. Application and Kubernetes resource desired state is managed through Git
   and Argo CD.
4. Kubernetes control-plane state is protected through automated etcd
   snapshots.

Application data stored outside etcd is treated separately and requires its
own backup strategy.

The recovery model separates:

* Proxmox infrastructure
* Kubernetes platform configuration
* Kubernetes control-plane state
* GitOps application configuration
* Persistent application data

## Recovery Architecture

```text
                    Disaster Recovery

                           |
          +----------------+----------------+
          |                |                |
          v                v                v
      Terraform         Ansible            Git
   Infrastructure    Platform Config     GitOps State
          |                |                |
          +----------------+----------------+
                           |
                           v
                    Kubernetes Platform
                           |
             +-------------+-------------+
             |             |             |
             v             v             v
          Cilium        Argo CD      Monitoring
                           |
                           v
                    Kubernetes Workloads

                    Control Plane State
                           |
                           v
                     etcd Snapshots
                           |
                           v
                     NFS Backup

                    Application Data
                           |
                           v
                Separate Storage Backup
```

The recovery model intentionally separates infrastructure, platform
configuration, Kubernetes state, and application data.

## Backup and Recovery Matrix

| Component                           | Source of Truth / Backup    | Recovery Method                      | Status      |
| ----------------------------------- | --------------------------- | ------------------------------------ | ----------- |
| Proxmox VMs                         | Terraform                   | Recreate infrastructure              | Protected   |
| Proxmox Terraform API prerequisites | Ansible Proxmox bootstrap   | Re-run bootstrap                     | Protected   |
| Ubuntu VM template                  | Proxmox bootstrap           | Recreate template                    | Protected   |
| Kubernetes bootstrap                | Ansible                     | Re-run automation                    | Protected   |
| Cilium configuration                | Ansible + GitOps            | Re-run automation / reconcile GitOps | Protected   |
| Argo CD installation                | Ansible + Helm              | Reinstall and bootstrap              | Protected   |
| Application manifests               | Git                         | Argo CD reconciliation               | Protected   |
| Gateway API configuration           | Git + Argo CD               | Argo CD reconciliation               | Protected   |
| Monitoring configuration            | Git + Helm values           | Argo CD reconciliation               | Protected   |
| Kubernetes cluster state            | etcd snapshot               | Restore etcd snapshot                | Protected   |
| etcd snapshots                      | Local + NFS backup          | Retrieve and restore snapshot        | Protected   |
| Persistent application data         | Application storage         | Storage-specific backup              | Separate    |
| Generated Kubernetes Secrets        | Component-generated state   | Regenerate during rebuild            | Recreated   |
| Critical application secrets        | Dedicated secret management | Restore from secret store            | Future work |

## Recovery Principles

### Rebuild Before Restore

The preferred recovery approach is to rebuild infrastructure and Kubernetes
components through automation whenever possible.

Manual changes should not be required for normal platform reconstruction.

The automation chain is:

```text
Proxmox Bootstrap
        |
        v
    Terraform
        |
        v
 Proxmox VMs
        |
        v
     Ansible
        |
        v
Kubernetes Platform
        |
        v
    Argo CD
        |
        v
    GitOps
```

### Git Is the Application Source of Truth

Application and platform Kubernetes resources managed through GitOps are
stored in the repository and reconciled by Argo CD.

Current Argo CD applications include:

```text
dev-nginx
dev-gateway
dev-monitoring
```

Their desired configuration is stored in the Git repository.

GitOps therefore provides the reproducible desired state for application,
Gateway API, and monitoring resources.

### etcd Is the Kubernetes State Backup

etcd snapshots protect Kubernetes API state that cannot simply be
reconstructed from application manifests.

Examples include Kubernetes control-plane object state that existed at the
time of the snapshot.

The current backup implementation creates snapshots automatically and
stores copies outside the control-plane node.

An etcd snapshot represents a point-in-time state and may not contain
objects created after the snapshot was taken.

### Application Data Is Separate

etcd snapshots do not contain the contents of application volumes or files
stored on external storage.

Persistent application data therefore requires a separate backup and
restore strategy.

This distinction is particularly important for workloads using NFS or
other storage systems.

## Current Backup Implementation

The etcd backup system provides:

* Automated etcd snapshot creation
* Daily systemd timer
* Persistent timer execution
* Local backup storage
* Off-node NFS storage
* SHA-256 checksum verification
* Seven-day retention
* Snapshot status validation
* Isolated restore capability

Local backup location:

```text
/var/backups/etcd
```

Off-node backup location:

```text
/srv/nfs/kubernetes/etcd-backup/snapshots
```

The detailed backup and restore procedure is documented separately in:

```text
docs/operations/etcd-backup-and-restore.md
```

## Recovery Order

The recovery approach depends on the type and scope of the failure.

The general recovery hierarchy is:

1. Recover the affected component when possible.
2. Rebuild infrastructure through Terraform when required.
3. Reconfigure the platform through Ansible.
4. Reconcile Kubernetes resources through Argo CD and GitOps.
5. Restore etcd only when the existing Kubernetes state cannot be safely
   recovered.
6. Restore application data separately when applicable.
7. Perform functional and infrastructure validation.

The exact recovery sequence depends on the failure scenario.

## etcd Restore Decision Flow

An etcd snapshot should not be restored automatically for every Kubernetes
failure.

The first objective is to determine whether the existing cluster and etcd
state can be recovered safely.

```text
                    Kubernetes Failure
                           |
                           v
                Is Kubernetes API usable?
                    /             \
                  Yes              No
                   |                |
                   v                v
             Is etcd healthy?   Is etcd state/quorum
                /    \          recoverable?
              Yes     No          /       \
               |       |        Yes        No
               v       v         |          |
          Recover the  Investigate          v
          affected    existing etcd   Restore known-good
          component        |           etcd snapshot
                          |
                          v
                  Recover existing
                    control plane
```

### Decision 1: Kubernetes API and etcd Are Healthy

If the Kubernetes API is available and etcd is healthy:

* Do not restore an etcd snapshot.
* Investigate the affected component or workload.
* Use the normal Kubernetes recovery procedure.

Examples include:

* Worker-node failure
* Application failure
* Cilium issue
* Argo CD synchronization issue
* Single control-plane node failure while etcd quorum remains healthy

### Decision 2: Control-Plane Node Failure With Healthy etcd Quorum

If a control-plane node fails but the remaining etcd members maintain
quorum:

1. Confirm the remaining control-plane members.
2. Verify etcd quorum.
3. Recover or recreate the failed control-plane node.
4. Rejoin the control plane using the documented automation.
5. Validate Kubernetes API availability.
6. Validate etcd membership.
7. Validate Cilium and workloads.

Do not restore an etcd snapshot.

The existing etcd cluster already contains the current Kubernetes state, so
restoring an older snapshot would introduce an unnecessary rollback.

Use:

```text
docs/disaster-recovery/control-plane-node-recovery.md
```

### Decision 3: etcd Is Unhealthy but Existing State May Be Recoverable

If etcd is unhealthy, first determine whether the existing etcd cluster can
be recovered without restoring a snapshot.

Investigate:

* etcd member health
* quorum status
* disk and filesystem problems
* network connectivity
* failed etcd processes
* control-plane node availability
* recent configuration changes

If the existing etcd state and quorum can be recovered safely, recover the
existing etcd cluster instead of restoring a snapshot.

This avoids unnecessary rollback to an older point in time.

### Decision 4: etcd State Is Corrupted or Quorum Is Permanently Lost

An etcd snapshot restore becomes appropriate when the existing etcd state can
no longer be safely recovered.

Typical conditions include:

* Irrecoverable etcd quorum loss
* Corrupted etcd data
* Loss of the majority of etcd members
* Confirmed need to recover Kubernetes API state from a known-good point in
  time

Recovery should then follow this process:

1. Stop or isolate affected control-plane components as required.
2. Identify the most recent valid etcd snapshot.
3. Verify snapshot integrity.
4. Preserve the existing control-plane state before destructive operations.
5. Restore the snapshot using the documented etcd recovery procedure.
6. Validate etcd membership and health.
7. Validate Kubernetes API functionality.
8. Validate Cilium.
9. Validate Argo CD.
10. Validate application workloads.
11. Validate application data separately.

The detailed procedure is documented in:

```text
docs/disaster-recovery/etcd-restore-runbook.md
```

## Complete Kubernetes Infrastructure Loss

A complete infrastructure loss is different from an etcd corruption
scenario.

The preferred recovery path is to reconstruct the platform from its
declarative sources:

```text
Git Repository
      |
      +------------------+
      |                  |
      v                  v
Proxmox Bootstrap     GitOps State
      |
      v
  Terraform
      |
      v
 Proxmox VMs
      |
      v
   Ansible
      |
      v
Kubernetes Platform
      |
      +-- Cilium
      +-- NFS / CSI
      +-- Argo CD
      +-- Monitoring
      |
      v
GitOps Reconciliation
      |
      v
Kubernetes Workloads
```

For complete infrastructure loss:

1. Recover or prepare the Proxmox host.
2. Run the Proxmox bootstrap automation.
3. Recreate the required Proxmox infrastructure with Terraform.
4. Reconfigure the operating systems and Kubernetes dependencies with
   Ansible.
5. Recreate the Kubernetes control plane.
6. Configure Cilium and cluster networking.
7. Configure NFS and NFS CSI where required.
8. Install and bootstrap Argo CD.
9. Reconcile applications and Gateway resources from Git.
10. Validate monitoring and platform services.
11. Restore application data when stateful workloads require it.
12. Perform end-to-end validation.

The detailed full reconstruction procedure is documented in:

```text
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
```

An etcd snapshot should only be restored during complete reconstruction if
historical Kubernetes cluster state is explicitly required and cannot be
reconstructed from the declarative sources.

## Recovery Scenarios

### Scenario 1: Single Worker Failure

Expected recovery:

1. Detect the failed worker.
2. Confirm workload availability and scheduling.
3. Recover or recreate the worker.
4. Rejoin the worker to the cluster.
5. Validate Cilium networking.
6. Validate persistent storage where applicable.
7. Validate application health.

No etcd restore is normally required.

Use:

```text
docs/disaster-recovery/worker-node-recovery.md
```

### Scenario 2: Single Control-Plane Failure

Expected recovery:

1. Confirm the remaining control-plane members.
2. Verify etcd quorum.
3. Recover or recreate the failed control-plane node.
4. Rejoin the control plane.
5. Validate Kubernetes API availability.
6. Validate etcd membership.
7. Validate Cilium and workloads.
8. Validate GitOps and monitoring.

A healthy multi-member etcd cluster should normally recover from a single
control-plane node failure without restoring a snapshot.

Use:

```text
docs/disaster-recovery/control-plane-node-recovery.md
```

### Scenario 3: etcd Data Corruption

Expected recovery:

1. Stop normal changes to the affected cluster.
2. Determine whether the existing etcd state can be recovered safely.
3. If recovery is not possible, identify the most recent valid etcd snapshot.
4. Validate the snapshot.
5. Preserve the existing etcd data before restoration.
6. Perform the documented etcd recovery procedure.
7. Validate etcd membership and health.
8. Validate Kubernetes API functionality.
9. Validate Cilium, Argo CD, and workloads.
10. Validate application data separately.

Use:

```text
docs/disaster-recovery/etcd-restore-runbook.md
```

### Scenario 4: Complete Kubernetes Cluster Loss

Expected recovery:

1. Recreate Proxmox prerequisites.
2. Run Proxmox bootstrap.
3. Recreate Proxmox VMs using Terraform.
4. Reconfigure the operating systems and dependencies using Ansible.
5. Recreate the Kubernetes control plane.
6. Configure Cilium.
7. Configure NFS and NFS CSI.
8. Install and bootstrap Argo CD.
9. Recreate GitOps-managed applications.
10. Validate monitoring and Gateway API.
11. Restore application data when required.
12. Restore etcd state only if historical Kubernetes state is explicitly
    required.
13. Perform end-to-end validation.

The goal is to minimize manual configuration and prove that the environment
remains reproducible.

## etcd Recovery Principle

The operational rule is:

```text
Can the existing component recover normally?
        |
       YES
        |
        v
Recover the affected component.
Do NOT restore etcd.
        |
       NO
        |
        v
Can the existing etcd state/quorum
be recovered safely?
        |
      /   \
    YES    NO
     |      |
     v      v
 Recover   Restore
 existing  known-good
 etcd      etcd snapshot
```

For complete infrastructure loss:

```text
Rebuild from Terraform + Ansible + GitOps
                    |
                    v
        Is historical Kubernetes
        state required?
              /       \
            NO         YES
             |          |
             v          v
       Keep rebuilt   Restore etcd
       cluster state  snapshot as
                      required
```

An etcd snapshot is a disaster recovery mechanism, not the default recovery
mechanism for every Kubernetes failure.

The preferred recovery hierarchy is:

1. Recover the existing component.
2. Recover the existing etcd state when possible.
3. Rebuild infrastructure and platform components through automation.
4. Reconcile Kubernetes resources through GitOps.
5. Restore etcd when existing Kubernetes state cannot be recovered.
6. Restore application data separately when applicable.

## RPO and RTO

### Current RPO Target

The current lab uses a daily etcd backup schedule.

Therefore, the theoretical etcd backup Recovery Point Objective is:

```text
RPO: up to 24 hours
```

The actual RPO depends on the timestamp and success of the most recent
valid snapshot.

This RPO applies to Kubernetes control-plane state protected by the etcd
backup mechanism. It does not represent the RPO for external application
data.

### Current RTO Target

Recovery Time Objective is currently:

```text
RTO: Not formally benchmarked
```

The actual recovery time depends on:

* Failure scope
* Proxmox availability
* Terraform provisioning time
* Ansible execution time
* Kubernetes bootstrap time
* Argo CD reconciliation time
* etcd restoration requirements
* Application data restoration requirements

A future DR exercise should measure the actual time required for each
recovery scenario.

## Application Data Recovery

Kubernetes control-plane recovery and application-data recovery are
separate operations.

etcd snapshots restore Kubernetes API state but do not restore files stored
on external storage.

For workloads using NFS:

```text
Kubernetes PVC
      |
      v
NFS CSI
      |
      v
NFS Server
      |
      v
Application Data
```

The NFS data must therefore be protected through a separate storage backup
strategy.

Application data recovery should validate:

* NFS availability
* StorageClass availability
* PV/PVC state
* Underlying filesystem data
* Application access to restored data
* Application-level data integrity

## What Is Not Currently Covered by the Automated DR System

### Persistent Application Data

The Kubernetes DR system does not treat external application data as part
of the etcd backup.

When stateful Kubernetes workloads require protection, their data must be
backed up independently.

### Critical Secrets

Generated Kubernetes Secrets can generally be recreated by their owning
components.

However, credentials representing external systems or application-specific
secrets require separate protection.

Examples include:

* External API credentials
* Database credentials
* Application encryption keys
* External service tokens

These should not be committed as plaintext secrets to Git.

A dedicated secret-management solution remains future work.

## DR Validation

A disaster recovery implementation is considered valid only after recovery
has been tested.

Validation should include:

* Terraform infrastructure recreation
* Proxmox bootstrap
* Ansible configuration
* Ansible idempotency
* Kubernetes control-plane health
* etcd cluster health
* Cilium health
* Argo CD synchronization
* Gateway API connectivity
* Application health
* Persistent data integrity when applicable
* Backup integrity
* Restore integrity

The recovery procedure should be periodically repeated to prevent backup
mechanisms from becoming untested assumptions.

## Current DR Validation Status

### Completed

The following recovery and backup capabilities have been validated:

* Worker-node failure testing
* Control-plane failure testing
* Control-plane recovery validation
* Automated etcd backup
* Off-node etcd backup
* SHA-256 backup verification
* Backup retention testing
* Persistent systemd timer testing
* etcd snapshot status validation
* Isolated etcd restore testing
* Kubernetes cluster reconstruction
* Proxmox bootstrap automation
* Terraform infrastructure reconstruction
* Ansible platform reconstruction
* Argo CD and GitOps reconciliation after reconstruction

### Planned

Remaining DR validation work includes:

* End-to-end measured disaster recovery exercise
* Measured RTO
* Persistent application data recovery
* Critical secret recovery
* Automated failure scenarios
* Automated DR validation

## Future Work

The disaster recovery strategy will evolve as the platform becomes more
stateful.

Planned improvements include:

* Kubernetes backup strategy for stateful workloads
* PVC and application-data backup
* Secret management
* Measured RPO/RTO for complete reconstruction
* Automated disaster recovery validation
* Failure injection and automated recovery scenarios
* Expanded infrastructure failure validation
* Recovery monitoring and alerting

## Related Documentation

```text
docs/
├── architecture/
│   └── kubernetes-ha.md
├── ansible/
│   └── architecture.md
├── kubernetes/
│   ├── cluster-bootstrap.md
│   ├── networking-cilium.md
│   └── storage-nfs.md
├── gitops/
│   └── argocd.md
├── observability/
│   └── prometheus.md
├── operations/
│   ├── control-plane-failure.md
│   ├── disaster-recovery.md
│   ├── etcd-backup-and-restore.md
│   ├── startup-shutdown.md
│   └── validation.md
└── disaster-recovery/
    ├── control-plane-node-recovery.md
    ├── worker-node-recovery.md
    ├── etcd-restore-runbook.md
    └── kubernetes-disaster-recovery-runbook.md
```
