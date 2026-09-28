# etcd Backup and Restore

## Overview

This project implements automated Kubernetes etcd backup and isolated restore validation using Ansible, systemd, and an NFS-based off-node backup location.

The design separates production etcd from the restore environment to reduce the risk of accidentally modifying the active Kubernetes control-plane datastore.

The implementation provides:

* Automated etcd snapshot creation
* Local backup storage
* Off-node NFS backup storage
* SHA-256 integrity verification
* Backup retention
* Daily systemd scheduling
* Missed-run recovery through `Persistent=true`
* Isolated etcd snapshot restoration
* Restore safety controls
* Restore validation
* Idempotent Ansible deployment

This document covers **etcd protection and recovery**. It does not replace the broader Kubernetes disaster recovery procedures.

## Architecture

```text
                         Kubernetes Control Plane

                     CP01 / CP02 / CP03
                            |
                            | Production etcd
                            |
                     CP01 backup source
                            |
                            | etcdctl snapshot save
                            v
                    Local Backup Storage
                    /var/backups/etcd
                            |
                            | copy + SHA-256 verification
                            v
                     NFS Backup Storage
              192.168.1.27:/srv/nfs/kubernetes
                            |
                            +-- etcd-backup/
                                snapshots/
```

The current backup job runs from the first control-plane host, `k8s-cp01`.

The NFS destination is located outside the Kubernetes control-plane nodes so that a failure of CP01
does not remove both the production etcd instance and its backup.

The backup is therefore separated into:

1. Production etcd
2. Local snapshot storage
3. Off-node NFS backup storage
4. Isolated restore environment

## Components

The etcd backup implementation is managed through:

```text
ansible/roles/etcd_backup/
```

The role provisions and configures:

* `etcdctl`
* `etcdutl`
* `etcd` binary for isolated restore
* Backup script
* Backup systemd service
* Backup systemd timer
* NFS backup mount
* Restore script
* Isolated restore systemd service

The role is integrated into:

```text
ansible/playbooks/site.yml
```

and can be executed independently using the `etcd_backup` tag.

## Backup Configuration

### Local Backup Directory

```text
/var/backups/etcd
```

Snapshots are first created locally before being copied to NFS.

This provides a local copy for immediate inspection while the NFS copy provides off-node protection.

### NFS Backup Directory

The NFS filesystem is mounted on the control-plane host and the snapshots are stored at:

```text
/mnt/etcd-backup/etcd-backup/snapshots
```

The mount is backed by:

```text
192.168.1.27:/srv/nfs/kubernetes
```

The backup is therefore stored outside the Kubernetes control-plane nodes.

### Retention

The configured retention period is:

```text
7 days
```

Snapshots older than the configured retention period are removed from both local and NFS backup locations.

Retention is intended to limit storage growth while keeping a short history of recent control-plane state.

## Backup Schedule

The backup is executed using a systemd timer.

Current schedule:

```text
03:00 UTC every day
```

The timer is configured with:

```ini
Persistent=true
```

This allows systemd to trigger the missed execution when the host becomes available again after the scheduled time.

The production timer configuration is:

```ini
OnCalendar=*-*-* 03:00:00
Persistent=true
Unit=etcd-backup.service
```

## Backup Process

The backup service performs the following sequence:

```text
Start
  |
  v
Connect to local production etcd
  |
  v
Create snapshot
  |
  v
Store snapshot locally
  |
  v
Copy snapshot to NFS
  |
  v
Calculate SHA-256
  |
  v
Compare local and NFS checksums
  |
  v
Apply retention policy
  |
  v
Complete
```

The production etcd instance remains running during the snapshot operation.

The backup process does not stop or replace the production etcd service.

## etcd Connection

The backup script connects to the local production etcd endpoint:

```text
https://127.0.0.1:2379
```

TLS client authentication uses credentials already present on the Kubernetes control-plane host:

```text
/etc/kubernetes/pki/etcd/ca.crt
/etc/kubernetes/pki/etcd/peer.crt
/etc/kubernetes/pki/etcd/peer.key
```

No credentials or private keys are stored in the repository.

## Snapshot Naming

Snapshots use timestamped filenames:

```text
etcd-snapshot-YYYY-MM-DD-HHMMSS.db
```

Example:

```text
etcd-snapshot-2026-09-08-051923.db
```

Timestamped filenames allow multiple snapshots to coexist and make backup history easier to inspect.

## Integrity Verification

After the snapshot is copied to NFS, SHA-256 checksums are calculated for both copies.

The backup succeeds only when:

```text
Local SHA-256 == NFS SHA-256
```

A checksum mismatch causes the backup service to fail.

This provides an integrity check for the transfer between CP01 and the NFS storage.

The checksum verifies the copied snapshot bytes. It does not by itself prove that the snapshot is a logically restorable
Kubernetes state, which is why snapshot metadata inspection and isolated restore validation are also performed.

## Snapshot Validation

Snapshot metadata can be inspected using:

```bash
etcdutl snapshot status <snapshot>
```

Validation includes:

* Snapshot revision
* Total key count
* Database size
* etcd storage version

The local and NFS copies should report equivalent snapshot metadata.

Snapshot metadata validation and isolated restore testing provide a stronger validation of backup usability than checksum verification alone.

## Restore Architecture

Restore operations are deliberately isolated from production etcd.

Production etcd uses:

```text
/var/lib/etcd
```

The isolated restore environment uses:

```text
/var/lib/etcd-restore
```

The restored etcd instance uses dedicated localhost ports:

```text
Client: 127.0.0.1:12379
Peer:   127.0.0.1:12380
```

The restore environment therefore does not bind to the production etcd ports:

```text
2379
2380
```

The isolated restore systemd service is disabled by default and is started only when an explicit restore exercise is required.

The restore environment is intended for:

* Backup validation
* Restore testing
* Snapshot inspection
* Recovery procedure validation

It is **not** intended to replace production etcd automatically.

## Restore Process

The restore process is:

```text
Select snapshot
      |
      v
Verify snapshot exists
      |
      v
Verify production etcd state
      |
      v
Verify restore directory is empty
      |
      v
Restore snapshot with etcdutl
      |
      v
Start isolated etcd
      |
      v
Validate endpoint health
      |
      v
Validate restored data
      |
      v
Stop isolated etcd
      |
      v
Remove restore environment
```

An isolated restore should be treated as a validation or recovery exercise, not as a normal operational action.

A production etcd restore requires the separate etcd restore runbook and appropriate recovery authorization.

## Restore Safety Controls

The restore implementation contains several safeguards.

### Production Data Directory Protection

The restore directory must not be:

```text
/var/lib/etcd
```

The restore script explicitly rejects this path.

The intended restore target is:

```text
/var/lib/etcd-restore
```

### Production etcd Health Check

Before restoring, the restore script checks the production etcd endpoint.

If production etcd is healthy, the isolated restore operation is refused.

This provides an additional safety barrier against running an isolated restore exercise when the script detects an operational production etcd instance.

This check is an application-level safety control and should not be treated as authorization for a production restore.

### Restore Directory Protection

The restore operation refuses to continue when the restore directory already contains data.

This prevents an existing restore environment from being silently overwritten.

### Snapshot Filename Restriction

The restore command accepts a snapshot filename rather than an arbitrary filesystem path.

The snapshot is therefore resolved inside the configured NFS backup directory.

This reduces the risk of accidentally restoring an unintended filesystem path.

### Production Port Isolation

The isolated etcd instance uses:

```text
127.0.0.1:12379
127.0.0.1:12380
```

instead of the production ports:

```text
2379
2380
```

This prevents the restore instance from attempting to bind to the production etcd endpoints.

## Validation

The implementation was validated against the Kubernetes environment after deployment through Ansible.

### Ansible Syntax Validation

The complete Ansible playbook passed syntax validation:

```bash
ansible-playbook ansible/playbooks/site.yml --syntax-check
```

Result:

```text
PASS
```

### Ansible Idempotency

The etcd backup role was executed normally more than once.

The second execution reported:

```text
k8s-cp01 : ok=29 changed=0 failed=0 skipped=2
k8s-cp02 : ok=3 changed=0 failed=0
k8s-cp03 : ok=3 changed=0 failed=0
k8s-lb01 : ok=1 changed=0 failed=0
k8s-lb02 : ok=1 changed=0 failed=0
k8s-nfs01 : ok=1 changed=0 failed=0
k8s-worker01 : ok=2 changed=0 failed=0
k8s-worker02 : ok=2 changed=0 failed=0
```

Result:

```text
PASS - no changes were required on the second run.
```

### Backup Directory Validation

The following directories were created:

```text
/var/backups/etcd

/mnt/etcd-backup/etcd-backup/snapshots
```

Both backup directories use restrictive permissions:

```text
0700
```

Result:

```text
PASS
```

### NFS Mount Validation

The configured NFS export was successfully mounted:

```text
192.168.1.27:/srv/nfs/kubernetes
```

The mount was verified as NFSv4.

Result:

```text
PASS
```

### Backup Script Validation

The rendered backup script was checked with:

```bash
bash -n /usr/local/sbin/etcd-backup.sh
```

Result:

```text
PASS
```

### etcd Snapshot Creation

A real production etcd snapshot was successfully created.

Example snapshot:

```text
etcd-snapshot-2026-09-08-051923.db
```

The snapshot was approximately 41 MB.

Result:

```text
PASS
```

### Snapshot Metadata Validation

The snapshot was inspected using `etcdutl snapshot status`.

Source snapshot metadata included:

```text
Revision:        648156
Total Keys:      814
Storage Size:    41 MB
Storage Version: 3.6.0
```

Result:

```text
PASS
```

### NFS Copy Validation

The snapshot was copied from CP01 to the NFS backup location.

The local and NFS copies reported equivalent snapshot metadata.

Result:

```text
PASS
```

### SHA-256 Integrity Validation

The local and NFS snapshot copies were compared using SHA-256.

Example checksum:

```text
460ad32f6027b1a36d49b1d387927ad190a1e786c99dd6394c13e743d4ecee13
```

The checksums matched.

Result:

```text
PASS
```

### Retention Validation

An artificial snapshot older than the configured retention period was created in both backup locations.

The retention process removed the expired snapshot.

Result:

```text
PASS
```

### Systemd Service Validation

The backup systemd service was executed manually.

The service successfully:

1. Created an etcd snapshot.
2. Copied the snapshot to NFS.
3. Verified the checksum.
4. Applied retention.
5. Completed with exit code `0`.

Result:

```text
PASS
```

### Systemd Timer Validation

The production timer is configured as:

```ini
OnCalendar=*-*-* 03:00:00
Persistent=true
Unit=etcd-backup.service
```

The timer was enabled and started successfully.

Result:

```text
PASS
```

### Persistent Timer Validation

A separate temporary timer was used to validate the `Persistent=true` behavior without modifying the production schedule.

The host missed the scheduled execution window.

After the timer was started again, systemd detected the missed execution and automatically triggered the backup service.

A new snapshot was created successfully.

Result:

```text
PASS - Persistent=true behavior confirmed.
```

The temporary validation timer was removed afterward.

The production timer remained enabled.

## Isolated Restore Validation

A real etcd snapshot was restored into the isolated restore directory:

```text
/var/lib/etcd-restore
```

Production etcd was not used as the restore target.

### Restore Database Validation

The restored database was created at:

```text
/var/lib/etcd-restore/member/snap/db
```

The restored snapshot metadata was inspected using:

```bash
etcdutl snapshot status <snapshot>
```

The restored snapshot preserved the expected snapshot revision, key count, storage size, and storage version.

Result:

```text
PASS
```

### Restored etcd Startup

The restored etcd instance was started using:

```text
127.0.0.1:12379
```

for the client endpoint and:

```text
127.0.0.1:12380
```

for the peer endpoint.

The restored etcd reported:

```text
version: 3.6.5
storage version: 3.6.0
leader: true
learner: false
errors: none
```

Result:

```text
PASS
```

### Restored Kubernetes Data Validation

The restored etcd database was queried through the isolated endpoint.

The Kubernetes `/registry` keyspace was readable.

The validation returned approximately:

```text
810 keys
```

Result:

```text
PASS
```

The `/registry` validation confirms that Kubernetes objects were present in the restored datastore.
It does not by itself validate application data stored outside etcd, such as persistent volume contents.

### Production Isolation Validation

During the restore exercise:

* `/var/lib/etcd` was not modified.
* Production etcd ports `2379` and `2380` were not used by the restore.
* The restored instance used only localhost ports `12379` and `12380`.
* The production etcd instance remained separate from the restore process.

Result:

```text
PASS
```

### Restore Cleanup

After validation:

* The isolated etcd service was stopped.
* Ports `12379` and `12380` were released.
* The restore directory was removed.
* Production etcd remained operational.

Result:

```text
PASS
```

## Validation Summary

| Validation                            | Result |
| ------------------------------------- | ------ |
| Ansible syntax check                  | PASS   |
| Ansible idempotency                   | PASS   |
| NFS mount                             | PASS   |
| Backup directory permissions          | PASS   |
| Backup script syntax                  | PASS   |
| etcd snapshot creation                | PASS   |
| Snapshot metadata validation          | PASS   |
| NFS snapshot copy                     | PASS   |
| SHA-256 verification                  | PASS   |
| Retention policy                      | PASS   |
| Systemd backup service                | PASS   |
| Systemd daily timer                   | PASS   |
| `Persistent=true` missed-run behavior | PASS   |
| Isolated snapshot restore             | PASS   |
| Restored etcd health                  | PASS   |
| `/registry` data validation           | PASS   |
| Production etcd isolation             | PASS   |
| Restore cleanup                       | PASS   |

## Operational Considerations

The current implementation provides automated etcd snapshot protection and validated isolated restore capability.

It does **not** implement complete Kubernetes disaster recovery.

The etcd backup protects Kubernetes control-plane state stored in etcd, but it does not automatically recover:

* Control-plane VM infrastructure
* Kubernetes PKI and node-local configuration
* Worker nodes
* CNI installation
* NFS server or persistent application data
* External DNS
* External access infrastructure
* Git repository availability
* Application data stored outside etcd
* Critical secrets stored outside the backed-up etcd state

Those areas are covered by the broader Kubernetes disaster recovery architecture and related recovery procedures.

## Recovery Decision

The etcd snapshot should not automatically be the first recovery action.

The general recovery hierarchy is:

```text
1. Recover the affected component
          |
          v
2. Recover existing etcd state if possible
          |
          v
3. Rebuild infrastructure/platform through automation
          |
          v
4. Reconcile workloads through GitOps
          |
          v
5. Restore etcd snapshot when existing state cannot be recovered
          |
          v
6. Recover persistent application data separately
```

A single control-plane node failure with remaining etcd quorum does not normally require an etcd snapshot restore.

A production etcd restore is appropriate when existing etcd state or quorum is no longer recoverable and a known-good snapshot is available.

See:

```text
docs/disaster-recovery/control-plane-node-recovery.md
docs/disaster-recovery/etcd-restore-runbook.md
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
docs/operations/disaster-recovery.md
```

## RPO Consideration

The current backup schedule is daily.

Therefore, the theoretical maximum etcd backup gap is approximately:

```text
24 hours
```

The effective recovery point depends on the most recent **successful and validated** snapshot available at the time of recovery.

The current implementation does not yet provide continuous or hourly etcd backups.

## Backup Availability

The current design provides two backup locations:

```text
Local:
    /var/backups/etcd

Off-node:
    192.168.1.27:/srv/nfs/kubernetes
```

The off-node copy protects against loss of the CP01 host.

However, the NFS server is still part of the same homelab environment.
This means the current design should not be considered protection against every possible site-level or storage-level disaster.

Additional independent backup storage can be introduced as part of future DR improvements.

## Security

Backup files are created with restrictive permissions.

Backup directories:

```text
0700
```

Snapshot files:

```text
0600
```

The repository does not contain:

* etcd private keys
* Kubernetes credentials
* passwords
* tokens
* sensitive runtime data

The TLS credentials used by the backup process remain on the Kubernetes control-plane host.

Because etcd snapshots contain Kubernetes control-plane state, access to snapshot files should be treated as sensitive.

## Related Automation

The implementation is managed through:

```text
ansible/roles/etcd_backup/
```

The main playbook includes the role through:

```text
ansible/playbooks/site.yml
```

The role is tagged:

```text
etcd_backup
```

This allows the backup capability to be deployed independently:

```bash
ansible-playbook ansible/playbooks/site.yml --tags etcd_backup
```

## Disaster Recovery Relationship

The responsibilities are intentionally separated:

```text
Proxmox Bootstrap
        |
        v
Terraform
        |
        v
Infrastructure
        |
        v
Ansible
        |
        v
Kubernetes Platform
        |
        +--------------------+
        |                    |
        v                    v
      etcd                GitOps
        |                    |
        v                    v
   Backup/Restore       Applications
        |
        v
 NFS Off-node Backup
```

The etcd backup layer protects Kubernetes control-plane state.

Terraform and Ansible reconstruct the infrastructure and platform.

Argo CD and Git provide the desired application configuration.

Persistent application data requires a separate backup and recovery strategy.

## Future Work

The following improvements remain outside the current etcd backup implementation:

* More frequent etcd snapshots
* Additional independent backup destinations
* Persistent application data backup and recovery
* Critical secret recovery
* End-to-end disaster recovery validation
* Automated failure scenarios
* Automated DR validation
* Measured RPO and RTO
* Recovery monitoring and alerting

These improvements are tracked as part of the broader Kubernetes disaster recovery roadmap.

## Related Documentation

```text
docs/
├── operations/
│   ├── etcd-backup-and-restore.md
│   ├── disaster-recovery.md
│   └── control-plane-failure.md
│
└── disaster-recovery/
    ├── control-plane-node-recovery.md
    ├── etcd-restore-runbook.md
    ├── kubernetes-disaster-recovery-runbook.md
    └── worker-node-recovery.md
```
