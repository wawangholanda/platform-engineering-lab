# Startup and Shutdown Procedures

## Overview

The Kubernetes laboratory runs on Proxmox with:

* Two load balancers
* Three control-plane nodes
* Two worker nodes
* NFS storage
* Cilium networking
* Argo CD and GitOps
* Prometheus, Grafana, and Alertmanager

Startup and shutdown should follow a controlled order to reduce the risk of unnecessary Kubernetes recovery operations.

The procedure distinguishes between:

* Infrastructure startup and shutdown
* Kubernetes control-plane availability
* Worker availability
* Platform service recovery
* Application and monitoring validation

The objective is to preserve Kubernetes control-plane health and etcd quorum during planned maintenance.

## Infrastructure Topology

```text id="d4x8fz"
                         Proxmox
                            |
              +-------------+-------------+
              |                           |
              v                           v
        Load Balancers                 NFS Server
        LB01 / LB02                   192.168.1.27
              |
              v
      Kubernetes API VIP
       192.168.1.30:6443
              |
      +-------+-------+
      |       |       |
      v       v       v
     CP01   CP02    CP03
      |       |       |
      +-------+-------+
              |
       Kubernetes API
              |
        +-----+-----+
        |           |
        v           v
    Worker01    Worker02
```

Application traffic uses a separate path:

```text id="2s9d9d"
Client
  |
  v
NPM 192.168.1.3
  |
  v
Cilium Gateway 192.168.1.240
  |
  v
Kubernetes Services
```

The Kubernetes API path and application ingress path are therefore separate.

## Startup Order

Recommended startup sequence:

```text id="v7xq0r"
1. Proxmox host
       |
2. NFS server
       |
3. Load Balancers
       |
4. Control Plane nodes
       |
5. Worker nodes
       |
6. Kubernetes platform services
       |
7. Argo CD / GitOps
       |
8. Monitoring and applications
```

The NFS server is included early because persistent workloads may depend on NFS-backed storage.

The exact order in which Kubernetes pods become Ready is controlled by Kubernetes rather than by this document.

## 1. Proxmox Host

Start the Proxmox host and verify that the virtualization platform is operational.

Check:

```bash id="k7v8qf"
pveversion
qm list
```

Verify that the expected VMs are available.

The infrastructure VMs are:

```text id="0d7p0h"
k8s-lb01
k8s-lb02
k8s-cp01
k8s-cp02
k8s-cp03
k8s-worker01
k8s-worker02
k8s-nfs01
```

VM startup ordering should preferably be configured in Proxmox rather than relying entirely on manual startup.

## 2. NFS Server

Start:

```text id="r2a8nm"
k8s-nfs01
```

Verify the NFS service:

```bash id="p6xvqt"
sudo systemctl status nfs-server
```

Verify the server address:

```text id="3b3v1x"
192.168.1.27
```

The NFS server should be available before persistent Kubernetes workloads are expected to become fully operational.

## 3. Load Balancers

Start:

```text id="9x9s3v"
k8s-lb01
k8s-lb02
```

Verify HAProxy and Keepalived:

```bash id="b0e6d3"
sudo systemctl status haproxy
sudo systemctl status keepalived
```

Verify the Kubernetes API VIP:

```bash id="u4a1jh"
ip addr | grep 192.168.1.30
```

Expected:

```text id="r3q5e8"
192.168.1.30
```

The API endpoint is:

```text id="p4s7o3"
192.168.1.30:6443
```

The VIP should be owned by the currently active Keepalived node.

## 4. Control Plane

Start:

```text id="a7v6hm"
k8s-cp01
k8s-cp02
k8s-cp03
```

Verify kubelet on each control-plane node:

```bash id="w6d3kv"
sudo systemctl is-active kubelet
```

Verify the Kubernetes API through the HA endpoint:

```bash id="x2g0sn"
curl -k --max-time 5 \
  https://192.168.1.30:6443/readyz
```

Expected:

```text id="j8f1qe"
ok
```

Verify cluster membership:

```bash id="y7u4mf"
kubectl get nodes -o wide
```

Verify etcd health:

```bash id="p3w2qs"
kubectl get --raw='/readyz?verbose'
```

For detailed etcd validation, use the procedures documented in:

```text id="6v5y0e"
docs/operations/etcd-backup-and-restore.md
docs/disaster-recovery/etcd-restore-runbook.md
```

## 5. Workers

Start:

```text id="8z1h4n"
k8s-worker01
k8s-worker02
```

Verify:

```bash id="r9g5sw"
kubectl get nodes -o wide
```

All nodes should eventually report:

```text id="x3v8ka"
Ready
```

A worker may take some time to become Ready while kubelet, containerd, Cilium, and other node-level components initialize.

## 6. Kubernetes Platform Services

Verify system pods:

```bash id="d0t8yf"
kubectl get pods -n kube-system
```

Verify Cilium:

```bash id="m3n7kc"
kubectl -n kube-system get pods -l k8s-app=cilium
```

Verify storage:

```bash id="q4c6rm"
kubectl get storageclass
kubectl get pvc -A
```

Persistent workloads may remain Pending until the NFS server and NFS CSI components are available.

## 7. Argo CD and GitOps

Verify Argo CD:

```bash id="f7v2pj"
kubectl get pods -n argocd
kubectl get applications -n argocd
```

Applications should eventually reconcile toward the Git-defined desired state.

Verify application status:

```bash id="h1c8zn"
kubectl get applications -n argocd \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
```

The expected state is normally:

```text
SYNC    Synced
HEALTH  Healthy
```

Individual applications may require additional time to become Healthy after a full infrastructure startup.

## 8. Monitoring and Applications

Verify monitoring:

```bash id="m9w4dc"
kubectl get pods -n monitoring
```

Verify Prometheus readiness:

```bash id="e8q1pz"
curl -s http://localhost:9091/-/ready
```

Expected:

```text
Prometheus Server is Ready.
```

Verify Prometheus target health:

```bash id="s6x3jd"
curl -s http://localhost:9091/api/v1/targets |
  jq '[.data.activeTargets[] | select(.health != "up")] | length'
```

Expected:

```text
0
```

Monitoring components may take longer to become fully operational than the Kubernetes API itself.

## Shutdown Order

Recommended planned shutdown sequence:

```text id="z4m5kr"
1. Applications / workloads
       |
2. Worker nodes
       |
3. Control Plane nodes
       |
4. Load Balancers
       |
5. NFS server
       |
6. Proxmox host
```

The objective is to stop workload nodes before shutting down the Kubernetes control plane.

The control plane should be shut down in a way that preserves etcd quorum for as long as possible.

## Graceful Worker Shutdown

Before planned worker maintenance:

```bash id="b4j6tw"
kubectl drain <NODE_NAME> \
  --ignore-daemonsets \
  --delete-emptydir-data
```

Verify that the node is drained as expected:

```bash id="k8p2yd"
kubectl get nodes
kubectl get pods -A -o wide
```

After maintenance:

```bash id="c5s8vq"
kubectl uncordon <NODE_NAME>
```

Verify:

```bash id="n3f6xa"
kubectl get nodes -o wide
```

A worker shutdown does not directly affect etcd quorum, but it can reduce workload capacity.

## Graceful Control-Plane Shutdown

Before shutting down a control-plane node:

1. Verify the API is healthy.
2. Verify the other control-plane nodes are healthy.
3. Verify etcd quorum.
4. Avoid shutting down multiple control-plane nodes simultaneously.
5. Confirm the remaining API endpoints are reachable.

Check:

```bash id="x6m0pt"
kubectl get nodes -o wide
```

Check API availability:

```bash id="k3z8vu"
curl -k --max-time 5 \
  https://192.168.1.30:6443/readyz
```

For a three-member etcd cluster:

```text id="j7p4cs"
Members:  3
Quorum:   2
```

Therefore, a planned shutdown must not intentionally take two control-plane/etcd members offline at the same time.

For control-plane maintenance procedures and node replacement, see:

```text id="s2k6vd"
docs/disaster-recovery/control-plane-node-recovery.md
docs/operations/control-plane-failure.md
```

## Load Balancer Shutdown

Before shutting down a load balancer, verify that the other load balancer is operational.

Check on the active/remaining node:

```bash id="h9m3qx"
sudo systemctl is-active haproxy
sudo systemctl is-active keepalived
```

Verify the API VIP:

```bash id="v5r1kc"
ip addr | grep 192.168.1.30
```

The Kubernetes API should remain reachable through:

```text id="e3q8hn"
192.168.1.30:6443
```

Do not shut down both load balancers while the Kubernetes control plane is expected to remain available through the HA API endpoint.

## NFS Server Shutdown

Before shutting down the NFS server:

* Stop or safely quiesce workloads that depend on NFS-backed persistent storage.
* Verify that no critical write operation is in progress.
* Confirm that the Kubernetes control plane can remain available independently.

Check PVCs:

```bash id="r8m4wb"
kubectl get pvc -A
```

Check workloads using persistent storage:

```bash id="w2n6sf"
kubectl get pods -A -o wide
```

NFS availability is separate from Kubernetes API availability.
A Kubernetes control plane can remain healthy while workloads using NFS-backed storage experience storage failures.

## Pre-Shutdown Validation

Before a planned full environment shutdown, check:

```bash id="k6r3yz"
kubectl get nodes -o wide
kubectl get pods -A
kubectl get applications -n argocd
kubectl get pvc -A
```

Verify the API:

```bash id="v9x1mf"
curl -k --max-time 5 \
  https://192.168.1.30:6443/readyz
```

Verify etcd/control-plane health through the available Kubernetes and monitoring checks.

If an etcd backup is due or a known-good backup should be created before maintenance, verify the backup status according to:

```text id="n4t7pk"
docs/operations/etcd-backup-and-restore.md
```

## Post-Startup Validation

After the environment is powered on, perform validation in stages.

### Infrastructure

Verify the expected VMs:

```bash id="z8w3rc"
qm list
```

### Kubernetes Nodes

```bash id="h6m2vn"
kubectl get nodes -o wide
```

Expected:

```text
Ready
```

### Kubernetes System Pods

```bash id="q9s4jf"
kubectl get pods -n kube-system
```

### Cilium

```bash id="r5v8kx"
kubectl -n kube-system get pods -l k8s-app=cilium
```

### Storage

```bash id="t1y6sp"
kubectl get storageclass
kubectl get pvc -A
```

### GitOps

```bash id="c7n2mz"
kubectl get applications -n argocd
```

### Monitoring

```bash id="w4q8jd"
kubectl get pods -n monitoring
```

Prometheus readiness:

```bash id="e1m7xf"
curl -s http://localhost:9091/-/ready
```

Prometheus target health:

```bash id="p8v3ck"
curl -s http://localhost:9091/api/v1/targets |
  jq '[.data.activeTargets[] | select(.health != "up")] | length'
```

Expected:

```text id="a5d9qk"
0
```

### Gateway API

Verify the Gateway:

```bash id="m6x2rt"
kubectl get gateway -A
```

Verify HTTPRoutes:

```bash id="y3k7nf"
kubectl get httproute -A
```

Verify the Gateway LoadBalancer address:

```bash id="u8p4sv"
kubectl get gateway nginx-gateway -A
```

The expected application Gateway address is:

```text id="r7c5hx"
192.168.1.240
```

### Application Access

Application access uses:

```text id="d9q2vm"
Client
  |
  v
NPM 192.168.1.3
  |
  v
Cilium Gateway 192.168.1.240
  |
  v
Kubernetes Services
```

Verify the relevant applications through their normal external endpoints after the Gateway and application services are Ready.

## Proxmox Considerations

VM startup ordering should be configured through Proxmox where practical.

The intended dependency order is:

```text id="g5r8wp"
Proxmox
   |
   +--> NFS
   |
   +--> Load Balancers
           |
           v
       Control Plane
           |
           v
         Workers
```

Kubernetes itself handles pod scheduling and service recovery after the nodes become available.

Proxmox startup ordering should therefore establish infrastructure availability without attempting to replace Kubernetes reconciliation.

## Forced Shutdown

Forced power-off should be avoided when possible.

If a forced shutdown is unavoidable:

1. Record which VMs were running.
2. Restore Proxmox infrastructure first.
3. Start NFS and load balancers.
4. Start all required control-plane nodes.
5. Verify API and etcd health.
6. Start workers.
7. Validate Cilium, storage, GitOps, Gateway, and monitoring.
8. Investigate any persistent failures before attempting recovery operations.

A forced shutdown does not automatically mean that etcd must be restored.

If control-plane state is unhealthy after startup, follow the appropriate control-plane or etcd recovery procedure
instead of immediately deleting or reinitializing the datastore.

## Operational Principles

* Prefer graceful shutdown over forced power-off.
* Preserve etcd quorum during control-plane maintenance.
* Do not shut down multiple control-plane nodes simultaneously.
* Keep at least two etcd members available in the three-member cluster.
* Verify the API before and after maintenance.
* Use node drain for planned worker maintenance.
* Ensure NFS availability before starting storage-dependent workloads.
* Validate Cilium after startup.
* Validate storage and PVC state after startup.
* Validate Argo CD and GitOps reconciliation.
* Validate Gateway API and external application access.
* Validate Prometheus and monitoring targets.
* Use the dedicated recovery runbooks when normal startup does not restore the expected state.
* Keep startup and shutdown procedures reproducible and documented.

## Troubleshooting After Startup

If the API is unavailable:

```text id="j4c7nx"
Check Load Balancer
        |
        v
Check API VIP
        |
        v
Check kubelet/static pods
        |
        v
Check etcd
        |
        v
Check control-plane quorum
```

Use:

```text id="e2p9mz"
docs/operations/control-plane-failure.md
```

If a single control-plane node cannot recover:

```text id="v6k3ra"
docs/disaster-recovery/control-plane-node-recovery.md
```

If etcd quorum or datastore state cannot be recovered:

```text id="s8m1qx"
docs/disaster-recovery/etcd-restore-runbook.md
```

For complete platform reconstruction:

```text id="p2w7yd"
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
```

## Related Documentation

```text id="q7f3mc"
docs/
├── architecture/
│   └── kubernetes-ha.md
│
├── kubernetes/
│   ├── cluster-bootstrap.md
│   ├── networking-cilium.md
│   └── storage-nfs.md
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
