# Startup and Shutdown Procedures

## Overview

The Kubernetes laboratory runs on Proxmox with two load balancers,
three control-plane nodes, and two worker nodes.

Startup and shutdown should follow a controlled order to reduce the risk
of unnecessary Kubernetes recovery operations.

## Infrastructure Topology

```text
LB01 / LB02
     |
     v
CP01 / CP02 / CP03
     |
     v
Worker01 / Worker02
```

## Startup Order

Recommended startup sequence:

```text
1. Proxmox host
       |
2. Load Balancers
       |
3. Control Plane nodes
       |
4. Worker nodes
       |
5. Kubernetes platform services
       |
6. Argo CD / GitOps
       |
7. Monitoring
```

### 1. Load Balancers

Start:

```text
k8s-lb01
k8s-lb02
```

Verify HAProxy and Keepalived:

```bash
sudo systemctl status haproxy
sudo systemctl status keepalived
```

Verify the VIP:

```bash
ip addr | grep 192.168.1.30
```

Expected:

```text
192.168.1.30
```

### 2. Control Plane

Start:

```text
k8s-cp01
k8s-cp02
k8s-cp03
```

Check kubelet:

```bash
sudo systemctl is-active kubelet
```

Verify the API:

```bash
curl -k --max-time 5 \
  https://192.168.1.30:6443/readyz
```

Expected:

```text
ok
```

### 3. Workers

Start:

```text
k8s-worker01
k8s-worker02
```

Verify:

```bash
kubectl get nodes -o wide
```

All nodes should eventually report:

```text
Ready
```

### 4. Platform Services

Verify core components:

```bash
kubectl get pods -n kube-system
```

Then verify:

```bash
kubectl get applications -n argocd
kubectl get pods -n monitoring
```

## Shutdown Order

Recommended shutdown sequence:

```text
1. Applications / workloads
       |
2. Worker nodes
       |
3. Control Plane nodes
       |
4. Load Balancers
       |
5. Proxmox host
```

The objective is to stop workload nodes before shutting down the
Kubernetes control plane.

## Graceful Shutdown

Before shutting down a worker:

```bash
kubectl drain <NODE_NAME> \
  --ignore-daemonsets \
  --delete-emptydir-data
```

After maintenance:

```bash
kubectl uncordon <NODE_NAME>
```

For planned control-plane maintenance, validate cluster health before
stopping a node.

## Pre-Shutdown Validation

Check:

```bash
kubectl get nodes
kubectl get pods -A
kubectl get applications -n argocd
```

Verify the API:

```bash
curl -k --max-time 5 \
  https://192.168.1.30:6443/readyz
```

Verify etcd and control-plane health through monitoring where available.

## Post-Startup Validation

After the environment is powered on:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

Verify networking:

```bash
kubectl -n kube-system get pods -l k8s-app=cilium
```

Verify storage:

```bash
kubectl get storageclass
kubectl get pvc -A
```

Verify GitOps:

```bash
kubectl get applications -n argocd
```

Verify Prometheus:

```bash
curl -s http://localhost:9091/-/ready
```

Verify target health:

```bash
curl -s http://localhost:9091/api/v1/targets |
  jq '[.data.activeTargets[] | select(.health != "up")] | length'
```

Expected:

```text
0
```

## Proxmox Considerations

The VMs should use appropriate startup ordering so that infrastructure
dependencies are available in the expected sequence.

The intended dependency is:

```text
Load Balancers
      |
      v
Control Plane
      |
      v
Workers
```

VM startup behavior should be managed through Proxmox configuration
rather than relying entirely on manual startup.

## Operational Principles

- Prefer graceful shutdown over forced power-off.
- Preserve etcd quorum during control-plane maintenance.
- Do not shut down multiple control-plane nodes simultaneously.
- Validate the API before and after maintenance.
- Validate Kubernetes, networking, storage, GitOps, and monitoring after
  startup.
- Use node drain for planned worker maintenance.
- Keep startup and shutdown procedures reproducible and documented.

## Related Documentation

```text
docs/
├── architecture/
│   └── kubernetes-ha.md
├── kubernetes/
│   ├── cluster-bootstrap.md
│   ├── networking-cilium.md
│   └── storage-nfs.md
├── observability/
│   └── prometheus.md
└── operations/
    ├── control-plane-failure.md
    ├── startup-shutdown.md
    └── validation.md
```
