# Platform Validation

## Overview

This document provides the platform-level validation checklist for the Platform Engineering Lab.

Validation covers:

* Proxmox infrastructure
* Terraform
* Configuration management
* Kubernetes
* High availability
* Cilium networking
* Gateway API
* DNS and service connectivity
* NFS storage
* GitOps
* Observability
* External application access

The validation process is intended to verify that the platform is operational after:

* Initial deployment
* Infrastructure changes
* Configuration changes
* Kubernetes recovery
* Proxmox startup and shutdown
* Network or storage changes
* GitOps changes

Routine validation is separate from destructive failure testing and disaster recovery exercises.

## Validation Flow

```text id="9k7c1m"
Proxmox Bootstrap
        |
        v
Terraform
        |
        v
Proxmox Infrastructure
        |
        v
Ansible
        |
        v
Kubernetes
        |
        +-- Control Plane
        +-- Workers
        +-- Cilium
        +-- Gateway API
        +-- Storage
        +-- Argo CD
        +-- Monitoring
        |
        v
External Access
        |
        +-- Nginx Proxy Manager
        +-- Argo CD
        +-- Grafana
```

The validation flow follows the dependency hierarchy:

1. Infrastructure
2. Automation
3. Kubernetes
4. Networking
5. Storage
6. GitOps
7. Observability
8. External access

## 1. Proxmox Bootstrap

When the Proxmox environment itself is reconstructed or its Terraform prerequisites are changed, validate the Proxmox bootstrap automation first.

The bootstrap playbook is:

```text id="f4x8n2"
ansible/playbooks/proxmox-bootstrap.yml
```

The associated role is:

```text id="q6m1zr"
ansible/roles/proxmox_bootstrap/
```

Validate syntax:

```bash id="b8p4yd"
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/proxmox-bootstrap.yml \
  --syntax-check
```

Validate check mode:

```bash id="v5k2sx"
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/proxmox-bootstrap.yml \
  --check
```

The bootstrap stage should establish the Terraform prerequisites, including:

* Terraform API user
* Terraform role
* API token
* Required ACL
* Ubuntu VM template

The current Ubuntu template is:

```text id="c3w7ma"
VMID: 9000
Name: ubuntu-2404-template
```

This stage is especially important during full Proxmox reconstruction.

## 2. Terraform

Run Terraform validation from the environment directory:

```text id="a4y6pt"
environments/dev/proxmox/
```

Validate formatting:

```bash id="m8r2vx"
terraform fmt -check -recursive
```

Validate configuration:

```bash id="n6c3kw"
terraform validate
```

Review the infrastructure plan:

```bash id="x9f5qd"
terraform plan
```

Expected:

* Formatting is valid.
* Configuration is valid.
* Provider configuration is valid.
* The plan matches the intended infrastructure state.
* No unexpected destructive changes are present.

Do not apply an unexpected destructive plan without reviewing the affected resources.

## 3. Ansible

The main platform automation entry point is:

```text id="p3v8ka"
ansible/playbooks/site.yml
```

### Syntax Validation

```bash id="s7m1xd"
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --syntax-check
```

Expected:

```text id="c2n8fq"
PASS
```

### Complete Automation

```bash id="t5w9jr"
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml
```

Expected:

```text id="q8d4mv"
failed=0
```

### Check Mode

```bash id="r6k2wp"
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --check
```

Repeated execution should produce no unexpected changes.

### Available Tags

```bash id="h4x7mz"
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --list-tags
```

### Targeted Validation

For control-plane metrics:

```bash id="j8q3vc"
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --tags k8s_control_plane_metrics
```

For etcd backup:

```bash id="d5w9kr"
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --tags etcd_backup
```

### Ansible Lint

Run:

```bash id="m7c2xf"
ansible-lint
```

Expected:

```text id="y4p8qs"
PASS
```

## 4. Kubernetes Cluster

Check all nodes:

```bash id="k6v3mx"
kubectl get nodes -o wide
```

Expected nodes:

```text id="w8q1fr"
k8s-cp01
k8s-cp02
k8s-cp03
k8s-worker01
k8s-worker02
```

All five nodes should eventually report:

```text
Ready
```

Check system workloads:

```bash id="p4m9zt"
kubectl get pods -A
```

Core Kubernetes, networking, storage, GitOps, and monitoring components should be operational.

## 5. Kubernetes API High Availability

The Kubernetes API is exposed through:

```text id="z3f7kv"
192.168.1.30:6443
```

Validate API readiness:

```bash id="n8x2cq"
curl -k --max-time 5 \
  https://192.168.1.30:6443/readyz
```

Expected:

```text id="r5m1jd"
ok
```

The API VIP is provided by:

```text id="b7w4px"
LB01  192.168.1.25
LB02  192.168.1.26
```

The backend control-plane nodes are:

```text id="k2n8ys"
CP01  192.168.1.20
CP02  192.168.1.23
CP03  192.168.1.24
```

Check the API server through the HA endpoint rather than relying only on a single control-plane address.

## 6. Control-Plane and etcd Health

Verify control-plane nodes:

```bash id="v9m3qw"
kubectl get nodes \
  -l 'node-role.kubernetes.io/control-plane' \
  -o wide
```

Verify API readiness in detail:

```bash id="x6r2mk"
kubectl get --raw='/readyz?verbose'
```

The cluster uses three stacked etcd members.

The normal quorum requirement is:

```text id="p7c4zn"
Members: 3
Quorum: 2
```

Do not intentionally take two control-plane/etcd members offline during routine validation.

For detailed etcd validation and backup verification, see:

```text id="e3k8vf"
docs/operations/etcd-backup-and-restore.md
```

## 7. Cilium Networking

Check Cilium pods:

```bash id="m5x9rc"
kubectl -n kube-system get pods \
  -l k8s-app=cilium \
  -o wide
```

Cilium should be running across the Kubernetes nodes.

The current networking configuration includes:

```text id="u8q4sd"
Pod CIDR:      10.0.0.0/16
Service CIDR:  10.96.0.0/12
DNS Service:   10.96.0.10
Cilium:        1.20.0
```

Cilium uses kube-proxy replacement.

Verify the GatewayClass:

```bash id="y7n3kp"
kubectl get gatewayclass
```

The Cilium GatewayClass should report an accepted status.

## 8. Gateway API

Verify the Gateway:

```bash id="a6m2zr"
kubectl get gateway -A
```

The primary Gateway is:

```text id="v3q8xf"
nginx-gateway
```

The expected Gateway LoadBalancer address is:

```text id="n5k1wd"
192.168.1.240
```

Verify HTTPRoutes:

```bash id="r4c7mz"
kubectl get httproute -A
```

The application routes include:

```text id="t8x2qp"
nginx-route
argocd-route
grafana-route
```

Verify ReferenceGrants:

```bash id="k9m4vc"
kubectl get referencegrant -A
```

The Argo CD and Grafana cross-namespace backend references should have corresponding ReferenceGrant resources.

Verify the Cilium load-balancer configuration:

```bash id="w6p3yr"
kubectl get ciliuml2announcementpolicy -A
kubectl get ciliumloadbalancerippools -A
```

## 9. DNS and Service Connectivity

Cluster DNS can be validated using a temporary test Pod:

```bash id="c5x8nf"
kubectl run dns-test \
  --image=busybox:1.36 \
  --restart=Never \
  --rm -it \
  -- nslookup kubernetes.default.svc.cluster.local
```

Expected:

* DNS resolution succeeds.
* The Kubernetes service resolves through cluster DNS.

Service connectivity should also be validated for workloads where application-level connectivity is important.

## 10. Gateway Application Routing

The Cilium Gateway provides the internal application routing layer.

The current routing architecture is:

```text id="q7m3xd"
HTTP Host
    |
    v
Cilium Gateway
192.168.1.240
    |
    +-- nginx-route
    +-- argocd-route
    +-- grafana-route
```

Direct Gateway routing can be tested using the appropriate HTTP `Host` header.

Argo CD:

```bash id="f2k8vz"
curl -v \
  -H 'Host: argocd.wawangholanda.biz.id' \
  http://192.168.1.240/
```

Grafana:

```bash id="j6r4mx"
curl -v \
  -H 'Host: grafana.wawangholanda.biz.id' \
  http://192.168.1.240/
```

A successful response validates the path:

```text id="x8c3mp"
Client
  |
  v
Cilium Gateway
  |
  v
HTTPRoute
  |
  v
Application Service
```

## 11. External Application Access

External access uses Nginx Proxy Manager:

```text id="m4v7qp"
Client
  |
  | HTTPS
  v
Nginx Proxy Manager
192.168.1.3
  |
  | HTTP
  v
Cilium Gateway
192.168.1.240
  |
  +-- Argo CD
  +-- Grafana
  +-- Nginx
```

Validate the public applications:

```text id="z8p2yc"
https://argocd.wawangholanda.biz.id
https://grafana.wawangholanda.biz.id
```

The expected request path is:

1. TLS is terminated at Nginx Proxy Manager.
2. The request is forwarded to the Cilium Gateway.
3. The appropriate HTTPRoute is selected.
4. The request reaches the intended Kubernetes Service.
5. The application returns a valid response.

## 12. Storage

Check the StorageClass:

```bash id="r3m8vf"
kubectl get storageclass
```

Check PersistentVolumes:

```bash id="q7x4kn"
kubectl get pv
```

Check PersistentVolumeClaims:

```bash id="w5c9mz"
kubectl get pvc -A
```

Expected application PVCs should report:

```text
Bound
```

The NFS server is:

```text id="n2v6pr"
k8s-nfs01
192.168.1.27
```

Storage validation should include:

* NFS server availability
* NFS CSI availability
* StorageClass availability
* PV state
* PVC state
* Workload mount availability

Persistent storage should remain available after Pod recreation or rescheduling.

Detailed storage procedures are documented in:

```text id="b4k7xs"
docs/kubernetes/storage-nfs.md
```

## 13. GitOps

Check Argo CD applications:

```bash id="c8m2vf"
kubectl get applications -n argocd
```

The current platform includes:

```text id="h6q3xp"
dev-nginx
dev-monitoring
dev-gateway
```

Check application synchronization and health:

```bash id="y9r4mk"
kubectl get applications -n argocd \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
```

Expected healthy applications should report:

```text
Synced    Healthy
```

For example:

```bash id="m7x2qc"
kubectl get application dev-monitoring -n argocd \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'
```

Expected:

```text
Synced Healthy
```

GitOps validation confirms that the Kubernetes state is converging toward the desired state stored in Git.

## 14. Observability

Prometheus readiness:

```bash id="v4k8ms"
curl -s http://localhost:9091/-/ready
```

Expected:

```text
Prometheus Server is Ready.
```

Check unhealthy active targets:

```bash id="p8x3nr"
curl -s http://localhost:9091/api/v1/targets |
  jq '[.data.activeTargets[] | select(.health != "up")] | length'
```

Expected:

```text
0
```

Validate control-plane metrics:

```bash id="z5m7cq"
curl -sG http://localhost:9091/api/v1/query \
  --data-urlencode \
  'query=up{job=~"kube-etcd|kube-controller-manager|kube-scheduler"}' |
  jq '.data.result[] | {
    job: .metric.job,
    instance: .metric.instance,
    value: .value[1]
  }'
```

The expected control-plane monitoring jobs include:

```text
kube-etcd
kube-controller-manager
kube-scheduler
```

Each expected target should report:

```text
1
```

Because Cilium kube-proxy replacement is enabled, kube-proxy is not expected to appear as an active monitoring target.

## 15. Monitoring Workloads

Check monitoring workloads:

```bash id="x6n3wp"
kubectl get pods -n monitoring -o wide
```

The monitoring namespace should contain healthy instances of:

* Prometheus
* Grafana
* Alertmanager
* kube-state-metrics
* node-exporter
* Prometheus Operator components

Verify the monitoring GitOps application:

```bash id="j2r8mc"
kubectl get application dev-monitoring -n argocd
```

Grafana external access should resolve through:

```text
grafana.wawangholanda.biz.id
```

Detailed monitoring validation is documented in:

```text id="c7m4xf"
docs/observability/prometheus.md
```

## 16. High Availability

The HA architecture should be evaluated across its independent failure domains.

### Load Balancer Layer

```text id="q4n8vp"
LB01  192.168.1.25
LB02  192.168.1.26
```

Both nodes provide redundancy for:

```text
192.168.1.30:6443
```

Routine validation should confirm that the VIP is available and the active load balancer can reach healthy control-plane backends.

### Control Plane Layer

```text id="w3m6kx"
CP01  192.168.1.20
CP02  192.168.1.23
CP03  192.168.1.24
```

The three control-plane nodes provide Kubernetes API and etcd redundancy.

The three-member etcd cluster requires two members for quorum.

### Worker Layer

```text id="p8c2mr"
Worker01  192.168.1.21
Worker02  192.168.1.22
```

Worker failure affects workload capacity but should not remove the Kubernetes control plane.

Actual workload availability also depends on:

* Replica count
* Scheduling constraints
* Available capacity
* Persistent storage
* Application dependencies

## 17. Failure Testing

Failure testing is separate from routine platform validation.

Failure scenarios should be executed deliberately and one failure domain at a time.

Relevant scenarios include:

* LB01 failure
* LB02 failure
* Single control-plane failure
* Control-plane recovery
* Worker failure
* API availability during failure
* NFS/storage failure
* Startup/shutdown recovery

Before performing destructive failure testing, ensure that the appropriate backup and recovery procedures are available.

Relevant procedures include:

```text id="s7k3xp"
docs/operations/control-plane-failure.md
docs/disaster-recovery/control-plane-node-recovery.md
docs/disaster-recovery/worker-node-recovery.md
docs/disaster-recovery/etcd-restore-runbook.md
```

Full platform reconstruction is documented separately in:

```text id="h5m9vc"
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
```

## 18. Post-Recovery Validation

After control-plane, worker, infrastructure, or full-cluster recovery, repeat the relevant validation layers.

Minimum checks:

```bash id="n6x3rm"
kubectl get nodes -o wide
kubectl get pods -A
kubectl get applications -n argocd
kubectl get pvc -A
```

Then validate:

```text id="v2k8sp"
Kubernetes API
      |
      v
Cilium
      |
      v
Gateway API
      |
      v
Storage
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

Recovery is not considered complete solely because the API is reachable.

## Validation Summary

| Layer                   | Expected Result                   |
| ----------------------- | --------------------------------- |
| Proxmox Bootstrap       | Valid / no unexpected changes     |
| Terraform               | Valid / expected plan             |
| Ansible                 | Syntax OK / no unexpected changes |
| Ansible lint            | PASS                              |
| Kubernetes nodes        | 5/5 Ready                         |
| Kubernetes API          | Ready                             |
| Control-plane/etcd      | Healthy / quorum available        |
| Cilium                  | Healthy                           |
| GatewayClass            | Accepted                          |
| Gateway                 | Ready                             |
| Gateway address         | `192.168.1.240`                   |
| HTTPRoutes              | Accepted / resolved               |
| ReferenceGrants         | Present                           |
| DNS                     | Resolves                          |
| StorageClass            | Available                         |
| PVCs                    | Bound where required              |
| Argo CD                 | Synced / Healthy                  |
| Prometheus              | Ready                             |
| Prometheus targets      | 0 unhealthy                       |
| Control-plane metrics   | Expected targets UP               |
| kube-proxy metrics      | No active target                  |
| Grafana external access | Available                         |
| Argo CD external access | Available                         |

## Validation Scope

This document is intended for platform-level validation after:

* Proxmox bootstrap
* Terraform infrastructure changes
* Ansible configuration changes
* Kubernetes cluster deployment
* Control-plane recovery
* Worker recovery
* Cilium configuration changes
* Gateway API changes
* Storage changes
* GitOps changes
* Monitoring changes
* Proxmox startup and shutdown cycles
* Disaster recovery exercises

Detailed destructive recovery procedures are documented separately.

## Validation Principles

* Validate dependencies before dependent services.
* Prefer read-only validation before making changes.
* Review Terraform plans before applying infrastructure changes.
* Preserve etcd quorum during HA validation.
* Do not combine multiple destructive failure scenarios in a single test.
* Validate both control-plane availability and workload availability.
* Validate storage independently from Kubernetes API health.
* Validate GitOps reconciliation after infrastructure recovery.
* Validate external application access after internal routing is healthy.
* Record failure-testing results separately from routine validation.
* Use dedicated recovery runbooks when normal validation identifies a failure requiring recovery.

## Related Documentation

```text id="m8q4vz"
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
│   ├── networking-cilium.md
│   └── storage-nfs.md
│
├── gitops/
│   └── argocd.md
│
├── observability/
│   └── prometheus.md
│
├── disaster-recovery/
│   ├── control-plane-node-recovery.md
│   ├── etcd-restore-runbook.md
│   ├── kubernetes-disaster-recovery-runbook.md
│   └── worker-node-recovery.md
│
└── operations/
    ├── control-plane-failure.md
    ├── disaster-recovery.md
    ├── etcd-backup-and-restore.md
    ├── startup-shutdown.md
    └── validation.md
```
