# etcd Backup and Restore

## Overview

This project implements automated Kubernetes etcd backup and isolated
restore validation using Ansible, systemd, and an NFS-based backup
location.

The design separates production etcd from the restore environment to
reduce the risk of accidentally modifying the active Kubernetes
control-plane datastore.

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

## Architecture

```text
                         Kubernetes Control Plane

                              CP01 / etcd
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

The backup is created from CP01 because the Ansible role targets the
first control-plane host.

The NFS destination is located outside the Kubernetes control-plane
nodes so that a failure of CP01 does not remove both the production etcd
instance and its backup.

## Components

The etcd backup implementation is managed through:

```text
ansible/roles/etcd_backup/
```

The role provisions:

* `etcdctl`
* `etcdutl`
* `etcd` binary for isolated restore
* Backup script
* Backup systemd service
* Backup systemd timer
* NFS backup mount
* Restore script
* Isolated restore systemd service

## Backup Configuration

### Local Backup Directory

```text
/var/backups/etcd
```

Snapshots are first created locally before being copied to NFS.

### NFS Backup Directory

```text
/mnt/etcd-backup/etcd-backup/snapshots
```

The mount is backed by:

```text
192.168.1.27:/srv/nfs/kubernetes
```

The backup is therefore stored outside the Kubernetes control-plane
nodes.

### Retention

The configured retention period is:

```text
7 days
```

Snapshots older than the configured retention period are removed from
both local and NFS backup locations.

## Backup Schedule

The backup is executed using a systemd timer.

Current schedule:

```text
03:00 UTC every day
```

The Kubernetes control-plane host uses UTC.

The timer is configured with:

```ini
Persistent=true
```

This allows systemd to execute a missed backup when the host becomes
available again after the scheduled time.

## Backup Process

The backup service performs the following sequence:

```text
Start
  |
  v
Connect to local etcd
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

The production etcd instance remains running during the snapshot
operation.

## etcd Connection

The backup script connects to the local production etcd endpoint:

```text
https://127.0.0.1:2379
```

TLS client authentication uses:

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

Timestamped filenames allow multiple snapshots to coexist and make
backup history easier to inspect.

## Integrity Verification

After the snapshot is copied to NFS, SHA-256 checksums are calculated
for both copies.

The backup succeeds only when:

```text
Local SHA-256 == NFS SHA-256
```

A checksum mismatch causes the backup service to fail.

This provides an integrity check for the transfer between CP01 and the
NFS storage.

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

The restore environment therefore does not bind to the production etcd
ports:

```text
2379
2380
```

The restore systemd service is disabled by default and is started only
when an explicit restore exercise is required.

## Restore Process

The restore process is:

```text
Select snapshot
      |
      v
Verify snapshot exists
      |
      v
Verify production etcd health
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

## Restore Safety Controls

The restore implementation contains several safeguards.

### Production Data Directory Protection

The restore directory must not be:

```text
/var/lib/etcd
```

The restore script explicitly rejects this path.

### Production etcd Health Check

Before restoring, the script checks the production etcd endpoint.

If production etcd is healthy, the restore operation is refused.

This provides an additional safety barrier against performing an
isolated restore operation under unexpected production conditions.

### Restore Directory Protection

The restore operation refuses to continue when the restore directory
already contains data.

This prevents an existing restore environment from being silently
overwritten.

### Snapshot Filename Restriction

The restore command accepts a snapshot filename rather than an
arbitrary filesystem path.

The snapshot is therefore resolved inside the configured NFS backup
directory.

## Validation

The implementation was validated against the Kubernetes environment
after deployment through Ansible.

### Ansible Syntax Validation

The complete Ansible playbook passed syntax validation:

```text
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
Revision:       648156
Total Keys:     814
Storage Size:   41 MB
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

An artificial snapshot older than the configured retention period was
created in both backup locations.

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

A separate temporary timer was used to validate the `Persistent=true`
behavior without modifying the production schedule.

The host missed the scheduled execution window.

After the timer was started again, systemd detected the missed execution
and automatically triggered the backup service.

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
etcdutl snapshot status
```

The restored database preserved the expected snapshot revision,
key count, storage size, and storage version.

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

The current implementation provides automated etcd snapshot protection
and validated isolated restore capability.

It does not yet implement complete Kubernetes disaster recovery.

A full disaster recovery strategy should additionally address:

* Control-plane host loss
* Kubernetes PKI recovery
* Kubernetes configuration recovery
* Control-plane reconstruction
* Worker node recovery
* CNI recovery
* Persistent application data recovery
* DNS recovery
* External access recovery
* GitOps recovery
* End-to-end cluster reconstruction

These areas remain part of the broader Disaster Recovery roadmap.

## Current Scope

The current implementation provides:

* Automated etcd snapshot backup
* Off-node backup storage
* Backup integrity verification
* Retention management
* Scheduled execution
* Missed-run recovery
* Isolated restore capability
* Restore safety controls
* Validated restore capability
* Idempotent Ansible deployment

This should be considered an **etcd protection and recovery capability**,
not a complete Kubernetes disaster recovery implementation.

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

The TLS credentials used by the backup process remain on the
Kubernetes control-plane host.

## Future Work

The next reliability and disaster recovery improvements include:

* Kubernetes backup strategy
* Full disaster recovery procedure
* Automated failure scenarios
* Persistent application data recovery
* End-to-end cluster reconstruction
* Automated disaster recovery validation

These items remain intentionally separate from the current etcd backup
implementation.
