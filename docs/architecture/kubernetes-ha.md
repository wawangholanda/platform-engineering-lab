# Kubernetes HA Architecture

## Overview

The Platform Engineering Lab runs a highly available Kubernetes cluster
on Proxmox.

High availability is provided at multiple infrastructure and Kubernetes
layers:

- Kubernetes API load balancing with two HAProxy / Keepalived nodes
- Kubernetes control plane with three nodes
- Three-member stacked etcd cluster
- Multiple worker nodes for workload capacity
- Cilium-based service and application networking

Application access is separated from Kubernetes API access.

The Kubernetes API uses the HA control-plane endpoint:

```text
192.168.1.30:6443
```

Application traffic is exposed through Cilium Gateway API and Nginx Proxy
Manager.

The architecture is designed so that failure of a single load balancer,
control-plane node, or worker node does not directly make the entire
Kubernetes platform unavailable, subject to the relevant quorum,
workload-replica, and dependency requirements.

## Architecture

The Kubernetes API and application traffic use separate network paths.

### Kubernetes API Path

```text
                         Kubernetes API Clients
                                  |
                                  v
                         VIP 192.168.1.30:6443
                                  |
                     +------------+------------+
                     |                         |
                   LB01                      LB02
              192.168.1.25              192.168.1.26
            HAProxy + Keepalived      HAProxy + Keepalived
                     |                         |
                     +------------+------------+
                                  |
                    +-------------+-------------+
                    |             |             |
                   CP01          CP02          CP03
              192.168.1.20  192.168.1.23  192.168.1.24
                    |             |             |
                    +-------------+-------------+
                                  |
                         Kubernetes Cluster
```

HAProxy distributes API traffic across all three control-plane nodes,
while Keepalived provides the virtual IP used by Kubernetes clients.

### Application Traffic Path

```text
Internet / Tailscale
        |
        v
Nginx Proxy Manager
192.168.1.3
        |
        | HTTP
        v
Cilium Gateway
192.168.1.240
        |
        +-------------+-------------+
        |             |             |
        v             v             v
      nginx        Argo CD        Grafana
```

Nginx Proxy Manager provides the external reverse-proxy and TLS
termination layer.

Cilium Gateway API provides Kubernetes-native HTTP routing to application
services.

The API path and application path are intentionally separated:

```text
Kubernetes API
    |
    v
Keepalived VIP
    |
    v
HAProxy
    |
    v
Control Plane

Application Traffic
    |
    v
Nginx Proxy Manager
    |
    v
Cilium Gateway
    |
    v
Kubernetes Services
```

## Components

| Component | Role |
|---|---|
| LB01 | HAProxy + Keepalived |
| LB02 | HAProxy + Keepalived |
| CP01 | Control Plane + stacked etcd |
| CP02 | Control Plane + stacked etcd |
| CP03 | Control Plane + stacked etcd |
| Worker01 | Kubernetes workload capacity |
| Worker02 | Kubernetes workload capacity |
| Cilium | CNI and cluster networking |
| Cilium Gateway API | Application ingress and HTTP routing |
| NFS CSI | Persistent storage integration |
| NFS Server | Persistent storage backend |
| Argo CD | GitOps controller |
| Prometheus | Metrics collection |
| Grafana | Monitoring dashboards |
| Alertmanager | Alert management |
| Nginx Proxy Manager | External reverse proxy and TLS termination |

### Infrastructure Layer

```text
LB01
LB02
CP01
CP02
CP03
Worker01
Worker02
NFS Server
```

These nodes provide the infrastructure and compute capacity required by
the Kubernetes platform.

### Kubernetes Platform Layer

```text
Kubernetes API
etcd
Cilium
Cilium Gateway API
NFS CSI
```

These components provide the Kubernetes control plane, networking,
application ingress, and persistent storage integration.

### Platform Services

```text
Argo CD
Prometheus
Grafana
Alertmanager
```

These services provide GitOps-based configuration and observability.

### External Access

```text
Nginx Proxy Manager
```

Nginx Proxy Manager provides the external reverse-proxy and TLS
termination layer before traffic enters the Kubernetes application
ingress path.

## API High Availability

The Kubernetes API is exposed through a stable virtual IP:

```text
192.168.1.30:6443
```

The virtual IP is managed by Keepalived across two load-balancer nodes:

```text
LB01  192.168.1.25
LB02  192.168.1.26
```

Keepalived provides failover of the virtual IP between the load
balancers.

HAProxy runs on both load-balancer nodes and forwards Kubernetes API
traffic to the control-plane nodes:

```text
192.168.1.20:6443
192.168.1.23:6443
192.168.1.24:6443
```

The request path is:

```text
Kubernetes API Client
        |
        v
192.168.1.30:6443
        |
        v
Keepalived / HAProxy
        |
        +-------------+-------------+
        |             |             |
        v             v             v
      CP01          CP02          CP03
```

This provides a stable Kubernetes API endpoint without requiring clients
to address an individual control-plane node.

API availability depends on the health of the load-balancer pair and
sufficient healthy control-plane members behind HAProxy.

## Control Plane High Availability

The cluster uses three control-plane nodes:

```text
CP01  192.168.1.20
CP02  192.168.1.23
CP03  192.168.1.24
```

Each control-plane node runs the Kubernetes control-plane components and
participates in the stacked etcd cluster.

The control-plane architecture is:

```text
                Kubernetes API
                      |
          +-----------+-----------+
          |           |           |
        CP01        CP02        CP03
          |           |           |
        etcd        etcd        etcd
```

The three control-plane nodes provide redundancy for:

- Kubernetes API server
- Controller Manager
- Scheduler
- etcd cluster membership

A single control-plane failure does not by itself remove the remaining
control-plane nodes from service.

Control-plane availability also depends on maintaining etcd quorum and
having the remaining API servers reachable through the HAProxy layer.

Control-plane recovery procedures are documented separately in the
disaster-recovery documentation.

## etcd

The control-plane nodes use stacked etcd:

```text
CP01 ── etcd
CP02 ── etcd
CP03 ── etcd
```

Each control-plane node hosts an etcd member. The three members form a
single etcd cluster that stores Kubernetes cluster state.

A three-member etcd cluster requires a majority quorum of two members.

Therefore:

```text
3 members
   |
   v
Quorum = 2
   |
   v
Tolerates loss of 1 member
```

If one etcd member fails, the remaining two members can maintain quorum
and continue serving cluster state.

If two members are unavailable, quorum is lost and the cluster cannot
continue normal etcd-backed control-plane operations until quorum is
restored.

Control-plane recovery must therefore preserve etcd membership and
quorum.

etcd backups are maintained separately from the running etcd cluster and
are used for disaster-recovery scenarios.

Related recovery procedures are documented in:

```text
docs/operations/etcd-backup-and-restore.md
docs/disaster-recovery/etcd-restore-runbook.md
```

## Worker Nodes

Application workloads are scheduled across two worker nodes:

```text
Worker01  192.168.1.21
Worker02  192.168.1.22
```

Worker nodes provide compute capacity independently from the Kubernetes
control plane.

The worker architecture is:

```text
             Kubernetes Control Plane
                       |
              +--------+--------+
              |                 |
              v                 v
          Worker01          Worker02
        192.168.1.21      192.168.1.22
              |                 |
              +--------+--------+
                       |
                       v
                Application Pods
```

A worker-node failure does not directly remove the Kubernetes control
plane.

However, a worker failure reduces available workload capacity and may
affect application availability depending on:

- Number of application replicas
- Pod scheduling constraints
- Available capacity on the remaining workers
- Persistent storage availability
- Application-specific redundancy

Workload high availability is therefore determined by the Kubernetes
deployment configuration in addition to the number of worker nodes.

## Networking

Cilium provides the Kubernetes networking layer and operates as the
cluster CNI.

The cluster uses:

```text
Pod Network:       10.0.0.0/16
Service Network:   10.96.0.0/12
Cluster DNS:       10.96.0.10
```

Cilium is configured with kube-proxy replacement and provides:

- Pod networking
- Service connectivity
- Cluster-pool IPAM
- kube-proxy replacement
- Gateway API integration
- LoadBalancer IP management
- L2 announcements

The application ingress path uses Cilium Gateway API:

```text
Client
  |
  v
Nginx Proxy Manager
  |
  v
Cilium Gateway
  |
  v
Kubernetes Service
  |
  v
Application Pod
```

The detailed Cilium networking architecture is documented separately in:

```text
docs/kubernetes/networking-cilium.md
```

## Application Ingress

Application ingress is provided by Cilium Gateway API.

The primary Gateway is:

```text
nginx-gateway
```

The Gateway uses the LoadBalancer address:

```text
192.168.1.240
```

HTTP routing is defined using Kubernetes `HTTPRoute` resources.

Current application routes include:

```text
nginx-route
argocd-route
grafana-route
```

The application ingress flow is:

```text
Cilium Gateway
      |
      +-------------+-------------+
      |             |             |
      v             v             v
    nginx        Argo CD        Grafana
```

The Gateway API configuration is managed through GitOps.

This keeps application routing configuration version-controlled and
separate from the external TLS termination layer provided by Nginx
Proxy Manager.

The detailed Gateway API configuration is documented in:

```text
docs/kubernetes/networking-cilium.md
```

## External Application Access

External application access uses Nginx Proxy Manager together with the
Cilium Gateway.

The traffic flow is:

```text
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
  +-------------+-------------+
  |             |             |
  v             v             v
nginx         Argo CD       Grafana
```

Nginx Proxy Manager provides the external reverse-proxy and public TLS
termination layer.

The connection from Nginx Proxy Manager to the Cilium Gateway uses HTTP
inside the internal network.

This separates:

- External TLS termination
- External reverse-proxy configuration
- Kubernetes-native application routing
- Application services

The Cilium Gateway then routes requests to the corresponding Kubernetes
services using `HTTPRoute` resources.

## Storage

Persistent storage is provided through the NFS server and the Kubernetes
NFS CSI driver.

The storage architecture is:

```text
Application Pod
      |
      v
     PVC
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

Kubernetes workloads consume persistent storage through standard
Kubernetes storage resources:

```text
PersistentVolumeClaim
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

The NFS storage layer is independent from the Kubernetes control-plane
nodes.

A control-plane failure therefore does not directly remove the NFS
backend.

However, application availability for stateful workloads also depends on
the availability of the NFS server and the corresponding storage
resources.

The detailed storage configuration is documented in:

```text
docs/kubernetes/storage-nfs.md
```

## GitOps and Observability

### GitOps

Argo CD manages Kubernetes resources from the Git repository.

The GitOps flow is:

```text
Git Repository
      |
      v
   Argo CD
      |
      v
Kubernetes Cluster
      |
      +---- Applications
      +---- Gateway API
      +---- Storage
      +---- Monitoring
```

Argo CD continuously reconciles the desired Kubernetes state defined in
Git with the state running in the cluster.

This separates platform bootstrap from ongoing Kubernetes application
configuration:

```text
Ansible
    |
    v
Platform Bootstrap
    |
    v
Argo CD
    |
    v
GitOps
    |
    v
Application Resources
```

### Observability

The observability stack consists of:

```text
Prometheus
Grafana
Alertmanager
```

Their responsibilities are:

| Component | Responsibility |
|---|---|
| Prometheus | Metrics collection and querying |
| Grafana | Metrics visualization and dashboards |
| Alertmanager | Alert routing and notification management |

Observability provides visibility into Kubernetes and platform health and
supports operational troubleshooting and failure validation.

## Failure Domains

The architecture separates the primary infrastructure and Kubernetes
failure domains:

```text
Kubernetes API Clients
        |
        v
   API VIP 192.168.1.30
        |
   +----+----+
   |         |
 LB01      LB02
   |         |
   +----+----+
        |
   +----+---------+---------+
   |              |         |
  CP01           CP02      CP03
   |              |         |
   +--------------+---------+
          stacked etcd
               |
        +------+------+
        |             |
     Worker01      Worker02
```

### Load Balancer Failure

The load-balancer layer contains two nodes:

```text
LB01  192.168.1.25
LB02  192.168.1.26
```

A single load-balancer failure should not remove the Kubernetes API
endpoint because Keepalived can move the virtual IP to the remaining
load balancer.

### Control Plane Failure

The control plane contains three members:

```text
CP01
CP02
CP03
```

A single control-plane failure can be tolerated while the remaining
control-plane nodes and etcd quorum remain healthy.

Control-plane availability therefore depends on:

- Remaining API server availability
- etcd quorum
- HAProxy health checks
- Keepalived / load-balancer availability

### Worker Failure

The worker layer contains:

```text
Worker01
Worker02
```

A worker failure does not directly remove the Kubernetes control plane.

It does reduce available workload capacity.

Application availability after a worker failure depends on workload
replicas, scheduling constraints, remaining capacity, and storage
dependencies.

### Storage Failure

NFS is an external dependency of the Kubernetes storage layer.

A failure of the NFS server can affect workloads that depend on NFS-backed
persistent volumes even when the Kubernetes control plane remains healthy.

### Summary

The main failure domains are therefore:

```text
Load Balancer
    |
    +-- LB01
    +-- LB02

Control Plane
    |
    +-- CP01
    +-- CP02
    +-- CP03
         |
        etcd

Worker Capacity
    |
    +-- Worker01
    +-- Worker02

Storage
    |
    +-- NFS Server
```

HA at one layer does not automatically provide end-to-end application
availability. Overall availability depends on the health and redundancy
of each required layer.

## Design Principles

The Kubernetes HA architecture follows these principles:

- No single load balancer is required for Kubernetes API availability.
- Multiple control-plane nodes provide control-plane redundancy.
- Three etcd members provide quorum tolerance for a single member
  failure.
- Worker capacity is separated from the control plane.
- Application availability is determined by workload replicas,
  scheduling, capacity, and required dependencies.
- Kubernetes API access is separated from application ingress.
- Cilium provides the cluster networking datapath.
- Cilium Gateway API provides Kubernetes-native application routing.
- Nginx Proxy Manager provides external reverse-proxy and TLS
  termination.
- Persistent storage is provided through NFS and the NFS CSI driver.
- Infrastructure and platform configuration are managed declaratively.
- GitOps provides version-controlled application and networking
  resources.
- Observability provides visibility into platform health and supports
  operational troubleshooting.
- Failure recovery procedures are documented separately from the
  architecture.

## Related Documentation

### Infrastructure

- [Terraform Architecture](../terraform/architecture.md)
- [Ansible Architecture](../ansible/architecture.md)

### Kubernetes

- [Cluster Bootstrap](../kubernetes/cluster-bootstrap.md)
- [Cilium Networking](../kubernetes/networking-cilium.md)
- [NFS Storage](../kubernetes/storage-nfs.md)

### GitOps and Observability Validation

- [Argo CD](../gitops/argocd.md)
- [Prometheus](../observability/prometheus.md)

### Operations

- [Validation](../operations/validation.md)
- [Control Plane Failure](../operations/control-plane-failure.md)
- [Startup and Shutdown](../operations/startup-shutdown.md)
- [Disaster Recovery](../operations/disaster-recovery.md)
- [etcd Backup and Restore](../operations/etcd-backup-and-restore.md)

### Disaster Recovery

- [Kubernetes Disaster Recovery Runbook](../disaster-recovery/kubernetes-disaster-recovery-runbook.md)
- [Control Plane Node Recovery](../disaster-recovery/control-plane-node-recovery.md)
- [Worker Node Recovery](../disaster-recovery/worker-node-recovery.md)
- [etcd Restore Runbook](../disaster-recovery/etcd-restore-runbook.md)
