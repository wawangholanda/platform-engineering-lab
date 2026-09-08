# Kubernetes Disaster Recovery

## Overview

This document defines the disaster recovery strategy and recovery procedure for the Kubernetes Platform Engineering Lab.

The recovery architecture is based on four principles:

1. Infrastructure is reproducible through Terraform.
2. Kubernetes configuration and bootstrap are automated through Ansible.
3. Application desired state is managed through Git and Argo CD.
4. Kubernetes control-plane state is protected through automated etcd snapshots.

Application data stored outside etcd is treated separately and requires its own backup strategy.

---

## Recovery Architecture

```text
                    Disaster Recovery
                           |
          +----------------+----------------+
          |                |                |
          v                v                v
      Terraform         Ansible            Git
   Infrastructure    Cluster Bootstrap    GitOps
          |                |                |
          +----------------+----------------+
                           |
                           v
                        Argo CD
                           |
                           v
                  Kubernetes Workloads

                           +
                           |
                           v
                    etcd Snapshots
                           |
                           v
                      NFS Backup
```

The recovery model intentionally separates infrastructure, configuration, Kubernetes state, and application data.

---

## Backup and Recovery Matrix

| Component                    | Source of Truth / Backup  | Recovery Method            | Status                 |
| ---------------------------- | ------------------------- | -------------------------- | ---------------------- |
| Proxmox VMs                  | Terraform                 | Recreate infrastructure    | Protected              |
| Kubernetes bootstrap         | Ansible                   | Re-run automation          | Protected              |
| Cilium configuration         | Ansible                   | Re-run automation          | Protected              |
| Argo CD installation         | Ansible + Helm            | Reinstall and bootstrap    | Protected              |
| Application manifests        | Git                       | Argo CD reconciliation     | Protected              |
| Monitoring configuration     | Git + Helm values         | Argo CD reconciliation     | Protected              |
| Kubernetes cluster state     | etcd snapshot             | Restore etcd snapshot      | Protected              |
| etcd snapshots               | NFS                       | Retrieve off-node snapshot | Protected              |
| PVC application data         | Application storage       | Storage-specific backup    | Not currently required |
| Generated Kubernetes Secrets | Component-generated state | Regenerate during rebuild  | Recreated              |
| Critical application secrets | Secret management         | Restore from secret store  | Future work            |

---

## Recovery Principles

### 1. Rebuild Before Restore

The preferred recovery approach is to rebuild infrastructure and Kubernetes components through automation whenever possible.

Manual changes should not be required for normal recovery.

### 2. Git Is the Application Source of Truth

Application workloads are managed through GitOps.

Current Argo CD applications include:

* `dev-nginx`
* `dev-gateway`
* `dev-monitoring`

Their desired configuration is stored in the Git repository.

### 3. etcd Is the Kubernetes State Backup

etcd snapshots protect Kubernetes API state that cannot simply be reconstructed from application manifests.

Snapshots are generated automatically and copied to an off-node NFS location.

### 4. Application Data Is Separate

etcd snapshots do not contain the contents of application volumes.

If stateful workloads using PVCs are introduced, their underlying application data must receive a separate backup strategy.

---

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

The detailed etcd procedure is documented separately in:

```text
docs/operations/etcd-backup-and-restore.md
```

---

## Recovery Order

The recovery approach depends on the type and scope of the failure.

The preferred order is:

1. Recover the affected component when possible.
2. Rebuild infrastructure and cluster components through automation when required.
3. Reconcile desired state through GitOps.
4. Restore etcd only when the existing Kubernetes state cannot be safely recovered.
5. Restore application data separately when applicable.
6. Perform functional validation.

The exact recovery sequence depends on the failure scenario.

---

## etcd Restore Decision Flow

An etcd snapshot should **not** be restored automatically for every Kubernetes failure.

The first objective is to determine whether the existing cluster and etcd state can be recovered safely.

```text
                    Kubernetes Failure
                           |
                           v
                Is Kubernetes API usable?
                    /             \
                  Yes              No
                   |                |
                   v                v
             Is etcd healthy?   Is etcd quorum
                /    \          recoverable?
              Yes     No          /       \
               |       |        Yes        No
               v       v         |          |
          Recover the  Investigate |         v
          affected    existing    |     Restore known-good
          component   etcd        |     etcd snapshot
                                  |
                                  v
                           Recover existing
                           control plane
```

### Decision 1: Kubernetes API and etcd Are Healthy

If the Kubernetes API is available and the etcd cluster is healthy:

* Do not restore an etcd snapshot.
* Investigate the affected component or workload.
* Use the normal Kubernetes recovery procedure.

Examples include:

* Worker node failure
* Application failure
* Cilium issue
* Argo CD synchronization issue
* Single control-plane node failure while etcd quorum remains healthy

---

### Decision 2: Control-Plane Node Failure With Healthy etcd Quorum

If a control-plane node fails but the remaining etcd members maintain quorum:

1. Confirm the remaining control-plane members.
2. Verify etcd quorum.
3. Recover or recreate the failed control-plane node.
4. Validate Kubernetes API availability.
5. Validate etcd membership.
6. Validate Cilium and workloads.

**Do not restore an etcd snapshot.**

The existing etcd cluster already contains the current Kubernetes state, so restoring an older snapshot would introduce unnecessary rollback.

---

### Decision 3: etcd Is Unhealthy but Existing State May Be Recoverable

If etcd is unhealthy, first determine whether the existing etcd cluster can be recovered without restoring a snapshot.

Investigate:

* etcd member health
* quorum status
* disk and filesystem problems
* network connectivity
* failed etcd processes
* control-plane node availability
* recent configuration changes

If the existing etcd state and quorum can be recovered safely:

**Recover the existing etcd cluster instead of restoring a snapshot.**

This avoids unnecessary rollback to an older point in time.

---

### Decision 4: etcd State Is Corrupted or Quorum Is Permanently Lost

An etcd snapshot restore becomes appropriate when the existing etcd state can no longer be safely recovered.

Typical conditions include:

* Irrecoverable etcd quorum loss
* Corrupted etcd data
* Loss of the majority of etcd members
* Confirmed need to recover Kubernetes API state from a known-good point in time

Recovery should then follow this process:

1. Stop or isolate affected control-plane components as required.
2. Identify the most recent valid etcd snapshot.
3. Verify snapshot integrity.
4. Restore the snapshot into an isolated environment first when possible.
5. Verify snapshot status and Kubernetes registry data.
6. Perform the production etcd recovery procedure.
7. Validate Kubernetes API functionality.
8. Validate Cilium.
9. Validate Argo CD.
10. Validate application workloads.

The detailed etcd recovery procedure is documented in:

```text
docs/operations/etcd-backup-and-restore.md
```

---

### Decision 5: Complete Kubernetes Infrastructure Loss

A complete infrastructure loss is different from an etcd corruption scenario.

The preferred recovery path is to rebuild the platform from its declarative sources:

```text
Terraform
    |
    v
Proxmox VMs
    |
    v
Ansible
    |
    v
Kubernetes cluster
    |
    v
Cilium
    |
    v
Argo CD
    |
    v
GitOps applications
```

In this scenario, **do not automatically restore the old etcd snapshot**.

First determine what needs to be recovered.

If the goal is to reconstruct the platform:

1. Recreate Proxmox VMs using Terraform.
2. Reconfigure the operating systems and Kubernetes dependencies using Ansible.
3. Recreate the Kubernetes control plane.
4. Reinstall Cilium.
5. Reinstall Argo CD.
6. Recreate Argo CD Applications using the Ansible bootstrap.
7. Allow Argo CD to reconcile workloads from Git.
8. Restore application data when stateful workloads exist.
9. Perform end-to-end validation.

An etcd snapshot should only be restored if historical Kubernetes cluster state cannot be reconstructed from Terraform, Ansible, and GitOps.

It should only be used when that historical Kubernetes state must also be recovered.

---

## Recovery Scenarios

### Scenario 1: Single Worker Failure

Expected recovery:

1. Detect failed worker.
2. Confirm workloads are rescheduled or remain available.
3. Recover or recreate the worker.
4. Validate Cilium networking.
5. Validate application health.

No etcd restore is normally required.

---

### Scenario 2: Control-Plane Failure

Expected recovery:

1. Confirm remaining control-plane members.
2. Verify etcd quorum.
3. Recover the failed control-plane node.
4. Validate Kubernetes API availability.
5. Validate etcd membership.
6. Validate Cilium and workloads.

A healthy multi-member etcd cluster should normally recover from a single control-plane node failure without restoring a snapshot.

---

### Scenario 3: etcd Data Corruption

Expected recovery:

1. Stop normal changes to the affected cluster.
2. Determine whether the existing etcd state can be recovered safely.
3. If recovery is not possible, identify the most recent valid etcd snapshot.
4. Validate the snapshot.
5. Restore the snapshot into an isolated environment first when possible.
6. Verify snapshot status and Kubernetes registry data.
7. Perform the production etcd recovery procedure.
8. Validate Kubernetes API functionality.
9. Validate Cilium, Argo CD, and workloads.

Detailed snapshot restore procedures are documented in:

```text
docs/operations/etcd-backup-and-restore.md
```

---

### Scenario 4: Complete Kubernetes Cluster Loss

Expected recovery:

1. Recreate Proxmox VMs using Terraform.
2. Reconfigure the operating systems and Kubernetes dependencies using Ansible.
3. Recreate the Kubernetes control plane.
4. Reinstall Cilium.
5. Reinstall Argo CD.
6. Recreate Argo CD Applications using the Ansible bootstrap.
7. Allow Argo CD to reconcile workloads from Git.
8. Restore application data when stateful workloads exist.
9. Restore etcd state only if historical Kubernetes cluster state must be recovered.
10. Perform end-to-end validation.

The goal is to minimize manual configuration and prove that the environment remains reproducible.

---

## etcd Recovery Principle

The operational rule is:

```text
Can the existing cluster recover normally?
        |
       YES
        |
        v
Recover the affected component.
Do NOT restore etcd.

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

An etcd snapshot is therefore a **disaster recovery mechanism**, not the default recovery mechanism for every Kubernetes failure.

The preferred recovery hierarchy is:

1. **Recover the existing component**
2. **Recover the existing etcd state when possible**
3. **Rebuild from automation**
4. **Reconcile from GitOps**
5. **Restore etcd when existing Kubernetes state cannot be recovered**
6. **Restore application data separately when applicable**

---

## RPO and RTO

### Current Target

The current lab uses a daily etcd backup schedule.

Therefore, the theoretical etcd backup Recovery Point Objective is approximately:

```text
RPO: up to 24 hours
```

The actual RPO depends on the most recent successful snapshot.

Recovery Time Objective is currently:

```text
RTO: Not formally benchmarked
```

A future DR exercise should measure the actual time required to rebuild the environment and restore required state.

---

## What Is Not Currently Backed Up

The following are intentionally outside the current automated backup implementation.

### Persistent Application Data

No active PVC/PV currently contains application data requiring backup.

When stateful workloads are introduced, their data must be protected independently from etcd.

### Critical Secrets

Generated Kubernetes Secrets can generally be recreated by their owning components.

However, credentials that represent external systems or application-specific secrets should eventually be managed through a dedicated
secret-management solution.

These credentials require separate protection from generated Kubernetes Secrets.

Examples include:

* External API credentials
* Database credentials
* Application encryption keys
* External service tokens

These should not be committed as plaintext Kubernetes Secrets to Git.

---

## DR Validation

A disaster recovery implementation is considered valid only after recovery has been tested.

Validation should include:

* Terraform infrastructure recreation
* Ansible idempotent configuration
* Kubernetes control-plane health
* etcd cluster health
* Cilium health
* Argo CD synchronization
* Application health
* Gateway/API connectivity
* Persistent data integrity when applicable
* Backup integrity
* Restore integrity

The recovery procedure should be periodically repeated to prevent backup mechanisms from becoming untested assumptions.

---

## Current DR Validation Status

### Completed

* Worker node failure testing
* Control-plane failure testing
* Control-plane recovery validation
* Automated etcd backup
* Off-node etcd backup
* SHA-256 backup verification
* Backup retention testing
* Persistent systemd timer testing
* etcd snapshot status validation
* Isolated etcd restore testing

### Planned

* Complete cluster reconstruction
* End-to-end disaster recovery exercise
* Measured RTO
* Persistent application data recovery
* Critical secret recovery
* Automated failure scenarios
* Automated DR validation

---

## Future Work

The disaster recovery strategy will evolve as the platform becomes more stateful.

Planned improvements include:

* Kubernetes backup strategy for stateful workloads
* PVC/application data backup
* Secret management
* Complete cluster reconstruction testing
* Automated disaster recovery validation
* Failure injection and automated recovery scenarios
* Formal RPO/RTO measurements
