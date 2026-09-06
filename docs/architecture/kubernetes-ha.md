# Kubernetes HA Architecture

## Overview

The Platform Engineering Lab runs a highly available Kubernetes cluster
on Proxmox.

High availability is provided at multiple layers:

* Kubernetes API load balancing with two HAProxy / Keepalived nodes
* Kubernetes control plane with three nodes
* Three-node stacked etcd cluster
* Redundant worker capacity
* Cilium-based service and application networking

Application access is separated from Kubernetes API access.

The Kubernetes API uses the HA control-plane endpoint:

```text
192.168.1.30:6443
```

Application traffic is exposed through Cilium Gateway API and Nginx Proxy
Manager.

## Architecture

```text
                         Kubernetes API Clients
                                |
                                v
                       VIP 192.168.1.30:6443
                                |
                   +------------+------------+
                   |                         |
                LB01                       LB02
            192.168.1.25               192.168.1.26
          HAProxy + Keepalived       HAProxy + Keepalived
                   |                         |
                   +------------+------------+
                                |
                 +--------------+--------------+
                 |              |              |
                CP01           CP02           CP03
           192.168.1.20   192.168.1.23   192.168.1.24
                 |              |              |
                 +--------------+--------------+
                                |
                         Kubernetes Cluster
                                |
                    +-----------+-----------+
                    |                       |
                 Worker01                Worker02
               192.168.1.21            192.168.1.22


Application Traffic

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

The Kubernetes API path and application traffic path are intentionally
separate.

The API endpoint is protected by the HAProxy / Keepalived layer, while
application traffic is handled by Nginx Proxy Manager and Cilium Gateway
API.

## Components

| Component           | Role                                       |
| ------------------- | ------------------------------------------ |
| LB01                | HAProxy + Keepalived                       |
| LB02                | HAProxy + Keepalived                       |
| CP01                | Control Plane + etcd                       |
| CP02                | Control Plane + etcd                       |
| CP03                | Control Plane + etcd                       |
| Worker01            | Application workloads                      |
| Worker02            | Application workloads                      |
| Cilium              | CNI and cluster networking                 |
| Cilium Gateway API  | Application ingress and HTTP routing       |
| NFS CSI             | Persistent storage                         |
| Argo CD             | GitOps                                     |
| Prometheus          | Metrics and monitoring                     |
| Grafana             | Monitoring dashboards                      |
| Alertmanager        | Alert management                           |
| Nginx Proxy Manager | External reverse proxy and TLS termination |

## API High Availability

The Kubernetes API is accessed through:

```text
192.168.1.30:6443
```

The virtual IP is provided by Keepalived across:

```text
LB01: 192.168.1.25
LB02: 192.168.1.26
```

HAProxy distributes Kubernetes API traffic across the three control-plane
nodes:

```text
192.168.1.20:6443
192.168.1.23:6443
192.168.1.24:6443
```

This creates a stable Kubernetes API endpoint independent of an individual
load balancer or control-plane node.

## Control Plane High Availability

The cluster uses three control-plane nodes.

Each control-plane node provides the Kubernetes control-plane components
and participates in the etcd cluster.

The control-plane nodes are:

```text
CP01  192.168.1.20
CP02  192.168.1.23
CP03  192.168.1.24
```

The three-node control plane provides redundancy for the Kubernetes API,
controller, scheduler, and cluster state.

## etcd

The control-plane nodes use stacked etcd:

```text
CP01 ── etcd
CP02 ── etcd
CP03 ── etcd
```

etcd stores Kubernetes cluster state and operates as a three-member
distributed cluster.

A three-member etcd cluster can tolerate the loss of a single member while
maintaining quorum.

Control-plane recovery therefore needs to preserve etcd membership and
quorum.

## Worker Nodes

Application workloads are distributed across two worker nodes:

```text
Worker01  192.168.1.21
Worker02  192.168.1.22
```

Worker nodes provide workload capacity independently from the Kubernetes
control plane.

A worker-node failure reduces available workload capacity but does not
directly remove the Kubernetes control plane.

## Networking

Cilium provides the Kubernetes networking layer.

The cluster uses:

```text
Pod Network:       10.0.0.0/16
Service Network:   10.96.0.0/12
Cluster DNS:       10.96.0.10
```

Cilium provides:

* Pod networking
* Service connectivity
* Cluster-pool IPAM
* kube-proxy replacement
* Gateway API integration
* LoadBalancer IP management
* L2 announcements

The detailed networking architecture is documented separately in:

```text
docs/kubernetes/networking-cilium.md
```

## Application Ingress

Application ingress is provided by Cilium Gateway API.

The primary Gateway is:

```text
nginx-gateway
```

The Gateway receives the LoadBalancer address:

```text
192.168.1.240
```

Application routing is implemented using HTTPRoute resources.

Current application routes include:

```text
nginx-route
argocd-route
grafana-route
```

The Gateway API configuration is managed through GitOps.

## External Application Access

External application access uses Nginx Proxy Manager together with the
Cilium Gateway.

The architecture is:

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

Nginx Proxy Manager provides the public TLS termination layer.

The internal connection between Nginx Proxy Manager and the Cilium Gateway
uses HTTP.

This separates public TLS handling from Kubernetes application routing.

## Storage

Persistent storage is provided through NFS and the Kubernetes NFS CSI
driver.

The storage architecture is:

```text
Application
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

Persistent storage is independent of the Kubernetes control-plane
architecture and is consumed by workloads through Kubernetes storage
resources.

## GitOps and Observability

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

The observability stack consists of:

```text
Prometheus
Grafana
Alertmanager
```

Prometheus provides metrics collection, Grafana provides visualization,
and Alertmanager provides alert management.

## Failure Domains

The architecture separates the primary failure domains:

```text
Kubernetes API
      |
      +-- LB01
      +-- LB02
            |
            +-- CP01
            +-- CP02
            +-- CP03
                  |
                  +-- Worker01
                  +-- Worker02
```

The load-balancer layer protects access to the Kubernetes API.

The control-plane layer provides redundancy for Kubernetes control-plane
services and etcd.

The worker layer provides workload capacity independently from the control
plane.

A single load-balancer failure should not remove the Kubernetes API
endpoint.

A single control-plane failure should not remove the Kubernetes control
plane as long as etcd quorum and the remaining control-plane nodes remain
healthy.

A worker failure affects workload capacity but does not directly remove
the Kubernetes control plane.

## Design Principles

The Kubernetes HA architecture follows these principles:

* No single load balancer is required for API availability.
* Multiple control-plane nodes provide control-plane redundancy.
* Three etcd members provide quorum tolerance for a single member failure.
* Worker capacity is separated from the control plane.
* Kubernetes API access is separated from application ingress.
* Cilium provides the cluster networking datapath.
* Application ingress is handled through Gateway API.
* Public TLS termination is handled by Nginx Proxy Manager.
* Infrastructure and platform configuration are managed declaratively.
* GitOps provides version-controlled application and networking resources.
* Monitoring provides visibility into platform health.

## Related Documentation

```text
docs/
├── ansible/
│   └── architecture.md
├── terraform/
│   └── architecture.md
├── architecture/
│   └── kubernetes-ha.md
├── kubernetes/
│   ├── cluster-bootstrap.md
│   ├── networking-cilium.md
│   └── storage-nfs.md
├── gitops/
│   └── argocd.md
├── observability/
│   └── prometheus.md
└── operations/
    ├── control-plane-failure.md
    ├── startup-shutdown.md
    └── validation.md
```
