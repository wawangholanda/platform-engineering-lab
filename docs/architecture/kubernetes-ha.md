# Kubernetes HA Architecture

## Overview

The Platform Engineering Lab runs a highly available Kubernetes cluster
on Proxmox.

High availability is provided at two layers:

- Kubernetes control plane with three nodes
- Kubernetes API load balancing with two HAProxy / Keepalived nodes

## Architecture

```text
                         Kubernetes API
                              |
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
                +-------------+-------------+
                |             |             |
               CP01          CP02          CP03
          192.168.1.20   192.168.1.23   192.168.1.24
                |             |             |
                +-------------+-------------+
                              |
                        Kubernetes Cluster
                         /             \
                        /               \
                   Worker01           Worker02
                 192.168.1.21       192.168.1.22
```

## Components

| Component | Role |
|---|---|
| LB01 | HAProxy + Keepalived |
| LB02 | HAProxy + Keepalived |
| CP01 | Control Plane + etcd |
| CP02 | Control Plane + etcd |
| CP03 | Control Plane + etcd |
| Worker01 | Application workloads |
| Worker02 | Application workloads |
| Cilium | Cluster networking |
| NFS CSI | Persistent storage |
| Argo CD | GitOps |
| Prometheus | Monitoring |

## API High Availability

The Kubernetes API is accessed through:

```text
192.168.1.30:6443
```

HAProxy distributes API traffic across:

```text
192.168.1.20:6443
192.168.1.23:6443
192.168.1.24:6443
```

Keepalived provides failover for the virtual IP between LB01 and LB02.

## Control Plane High Availability

The cluster uses three control-plane nodes.

Each control-plane node runs:

- kube-apiserver
- kube-controller-manager
- kube-scheduler
- etcd
- kubelet
- kube-proxy

Three control-plane nodes allow the cluster to maintain etcd quorum
during a single control-plane failure.

## etcd

The control-plane nodes use stacked etcd:

```text
CP01 ── etcd
CP02 ── etcd
CP03 ── etcd
```

etcd stores Kubernetes cluster state and requires quorum for normal
cluster operation.

For this reason, control-plane recovery must preserve etcd membership
and quorum whenever possible.

## Networking

Cilium provides the cluster networking layer.

```text
Pod
 |
 v
Cilium
 |
 v
Cluster Network
 |
 +---- Pod-to-Pod
 +---- Service Connectivity
 +---- DNS
 +---- NetworkPolicy
```

The current Pod network is:

```text
10.0.0.0/16
```

The Kubernetes Service network is:

```text
10.96.0.0/12
```

## Storage

Persistent storage is provided through NFS:

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

## GitOps and Observability

Argo CD manages Kubernetes resources from Git.

Prometheus, Grafana, and Alertmanager provide platform observability.

```text
Git
 |
 v
Argo CD
 |
 v
Kubernetes
 |
 +---- Applications
 +---- Storage
 +---- Monitoring
```

## Failure Domains

The architecture separates failure domains:

```text
API Access
    |
    +-- LB01
    +-- LB02
          |
          +-- CP01
          +-- CP02
          +-- CP03
```

A single load balancer failure should not remove the API endpoint.

A single control-plane failure should not remove the Kubernetes control
plane as long as etcd quorum and the remaining control-plane nodes remain
healthy.

Worker failure affects workload capacity but should not remove the
control plane.

## Validation

Check the cluster:

```bash
kubectl get nodes -o wide
```

Check the API endpoint:

```bash
curl -k --max-time 5 \
  https://192.168.1.30:6443/readyz
```

Check control-plane nodes:

```bash
kubectl get nodes \
  -l node-role.kubernetes.io/control-plane
```

Validate etcd metrics through Prometheus:

```bash
curl -sG http://localhost:9091/api/v1/query \
  --data-urlencode \
  'query=up{job="kube-etcd"}' |
  jq '.data.result[] | {
    instance: .metric.instance,
    value: .value[1]
  }'
```

All three etcd targets should report:

```text
1
```

## Failure Testing

The HA design should be validated by testing:

- LB01 failure
- LB02 failure
- Worker failure
- Single control-plane failure
- Control-plane recovery
- API availability during failure

Failure testing should be performed one failure domain at a time.

## Design Principles

- No single load balancer should be required for API availability.
- Multiple control-plane nodes provide redundancy.
- etcd quorum must be preserved during recovery.
- Infrastructure and platform configuration are automated.
- Failure scenarios should be validated rather than assumed.
- Monitoring should verify the health of HA components.

## Related Documentation

```text
docs/
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
    ├── control-plane-failure.md
    ├── startup-shutdown.md
    └── validation.md
```
