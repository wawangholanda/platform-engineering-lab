# Kubernetes Cluster Bootstrap

## Overview

The Kubernetes cluster is provisioned on Proxmox using Terraform and bootstrapped with Ansible.

Terraform manages the infrastructure layer, while Ansible configures the operating system and initializes the Kubernetes platform.

The bootstrap process establishes the Kubernetes control plane, worker nodes, networking, persistent storage, GitOps, and observability components.

## Bootstrap Flow

```text
Terraform
    |
    v
Proxmox VMs
    |
    v
Load Balancers
    |
    v
Common Kubernetes Configuration
    |
    v
First Control Plane
    |
    v
Additional Control Planes
    |
    v
Control-Plane Metrics
    |
    v
Helm
    |
    v
Cilium
    |
    v
Workers
    |
    v
NFS Server / NFS CSI
    |
    v
Argo CD
    |
    v
GitOps Applications
    |
    v
Monitoring
    |
    v
Gateway API
```

## Cluster Configuration

| Component    | Value              |
| ------------ | ------------------ |
| Kubernetes   | 1.34.10            |
| kubeadm      | 1.34.10            |
| kubelet      | 1.34.10            |
| containerd   | 2.2.1              |
| OS           | Ubuntu 24.04.4 LTS |
| CNI          | Cilium 1.20.0      |
| Pod CIDR     | 10.0.0.0/16        |
| Service CIDR | 10.96.0.0/12       |
| Cluster DNS  | 10.96.0.10         |
| API Endpoint | 192.168.1.30:6443  |

## Node Topology

| Host         | Role          | IP           |
| ------------ | ------------- | ------------ |
| k8s-cp01     | Control Plane | 192.168.1.20 |
| k8s-cp02     | Control Plane | 192.168.1.23 |
| k8s-cp03     | Control Plane | 192.168.1.24 |
| k8s-worker01 | Worker        | 192.168.1.21 |
| k8s-worker02 | Worker        | 192.168.1.22 |
| k8s-lb01     | Load Balancer | 192.168.1.25 |
| k8s-lb02     | Load Balancer | 192.168.1.26 |
| k8s-nfs01    | NFS Server    | 192.168.1.27 |

## Kubernetes API High Availability

The Kubernetes API is exposed through the virtual endpoint:

```text
192.168.1.30:6443
```

The API endpoint is implemented using two load-balancer nodes:

```text
                    192.168.1.30
                    API VIP
                       |
             +---------+---------+
             |                   |
          lb01                 lb02
       192.168.1.25         192.168.1.26
             |                   |
             +---------+---------+
                       |
          +------------+------------+
          |            |            |
        cp01         cp02         cp03
     192.168.1.20  192.168.1.23  192.168.1.24
```

HAProxy distributes API traffic across the control-plane nodes, while Keepalived provides the virtual IP.

The control plane uses a three-member stacked etcd topology.

## Bootstrap Components

### Common Node Configuration

The `k8s_common` role prepares Kubernetes nodes with the required operating-system and container runtime configuration.

Responsibilities include:

* OS prerequisites
* Swap configuration
* Kernel modules
* Sysctl configuration
* containerd
* Kubernetes packages
* kubeadm
* kubelet
* kubectl

This provides a consistent baseline across control-plane and worker nodes.

### Control Plane

The first control-plane node initializes the Kubernetes cluster through:

```text
ansible/roles/k8s_control_plane/
```

Additional control-plane nodes join through:

```text
ansible/roles/k8s_control_plane_join/
```

The control plane consists of three nodes:

```text
k8s-cp01
k8s-cp02
k8s-cp03
```

Control-plane changes are executed serially to reduce the risk of disrupting multiple control-plane nodes simultaneously.

### Workers

Worker nodes are configured through:

```text
ansible/roles/k8s_worker/
```

The worker layer currently consists of:

```text
k8s-worker01
k8s-worker02
```

Worker joins are performed serially to keep the bootstrap process predictable.

### Cilium Networking

Cilium provides the Kubernetes networking layer through:

```text
ansible/roles/cilium/
```

Cilium is configured with:

* Cluster-pool IPAM
* Pod networking
* Service connectivity
* Network policy capabilities
* Network observability
* kube-proxy replacement
* Gateway API support
* L2 announcements
* LoadBalancer IP allocation

The cluster uses:

```text
Pod CIDR:      10.0.0.0/16
Service CIDR:  10.96.0.0/12
```

Cilium replaces the traditional kube-proxy datapath.

### Gateway API

Cilium Gateway API provides the application ingress layer inside the Kubernetes cluster.

The architecture is:

```text
External Client
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
      +--------> nginx
      |
      +--------> Argo CD
      |
      +--------> Grafana
```

The Gateway API configuration includes:

* `GatewayClass` named `cilium`
* `Gateway` named `nginx-gateway`
* Cilium LoadBalancer IP pool `192.168.1.240-192.168.1.250`
* HTTPRoutes for application services
* ReferenceGrants for cross-namespace backend references

Gateway resources are managed through GitOps.

### Helm

Helm provides the package management layer for Kubernetes applications.

The corresponding Ansible role is:

```text
ansible/roles/helm/
```

Helm is used during bootstrap for platform components such as Cilium and Argo CD, while persistent application configuration is managed through GitOps.

### Persistent Storage

Persistent storage is provided through NFS and the Kubernetes NFS CSI driver.

The storage architecture is:

```text
NFS Server
    |
    v
NFS CSI Driver
    |
    v
StorageClass
    |
    v
PersistentVolume
    |
    v
PersistentVolumeClaim
```

Related Ansible roles:

```text
ansible/roles/nfs_server/
ansible/roles/nfs_csi/
```

### GitOps

Argo CD provides the GitOps control plane:

```text
ansible/roles/argocd/
ansible/roles/argocd_bootstrap/
```

After Argo CD is established, Kubernetes application configuration is managed from the Git repository.

Current GitOps-managed platform areas include:

```text
Applications
    |
    +-- nginx
    |
    +-- Monitoring
    |
    +-- Gateway API resources
```

Git remains the source of truth for persistent Kubernetes configuration.

### Monitoring

The observability stack uses `kube-prometheus-stack`.

The monitoring platform includes:

* Prometheus
* Grafana
* Alertmanager
* kube-state-metrics
* node-exporter

The monitoring configuration is managed through Argo CD rather than being maintained independently from Git.

Grafana is exposed externally through the same Gateway architecture:

```text
Nginx Proxy Manager
        |
        v
Cilium Gateway
        |
        v
Grafana Service
```

## Ansible Bootstrap Architecture

The single Ansible entry point is:

```text
ansible/playbooks/site.yml
```

The high-level automation sequence is:

```text
1. Load Balancers
2. Common Kubernetes Configuration
3. First Control Plane
4. Additional Control Planes
5. Control-Plane Metrics
6. Helm
7. Cilium
8. Workers
9. NFS Server
10. NFS CSI
11. Argo CD
12. GitOps Bootstrap
```

Ansible roles encapsulate reusable platform configuration, while `site.yml` provides the orchestration layer.

Role tags allow individual areas of the platform to be targeted when operational changes are required.

Detailed validation and operational commands are documented separately in:

```text
docs/operations/validation.md
```

## Idempotency

The bootstrap automation is designed to be safely re-applied.

Idempotency is supported through:

* Declarative Ansible tasks
* Reusable roles
* Conditional execution
* Kubernetes declarative resources
* Helm release management
* GitOps reconciliation

Targeted role execution can be used when only a specific platform component requires reconciliation.

Validation procedures for idempotency and Ansible execution are maintained separately from this architecture document.

## Control Plane Safety

Kubernetes control-plane components run as static Pods.

Their manifests are located under:

```text
/etc/kubernetes/manifests/
```

Changes to these manifests are automatically processed by kubelet.

The platform therefore follows these principles:

* Change one control-plane node at a time.
* Validate static Pod configuration before making changes.
* Never store backup manifests inside the static Pod directory.
* Check etcd before troubleshooting kube-apiserver.
* Verify etcd membership and quorum before destructive recovery.
* Preserve etcd quorum whenever possible.

Ansible control-plane operations use serial execution to reduce the blast radius of configuration changes.

## Recovery Principles

Control-plane recovery follows a dependency-oriented approach:

```text
API unavailable
      |
      v
kube-apiserver
      |
      v
etcd
      |
      v
etcd quorum
      |
      v
kubelet / static Pods
      |
      v
Affected component
      |
      v
Kubernetes API
      |
      v
Cluster workloads
      |
      v
Monitoring
```

Recovery should begin with state inspection rather than destructive reinitialization.

Operations such as:

```text
kubeadm reset
rm -rf /var/lib/etcd
etcd member remove
etcd member add
```

should not be performed until the current cluster and etcd state are understood.

Detailed failure and recovery procedures are maintained in:

```text
docs/operations/control-plane-failure.md
```

## Design Principles

The bootstrap implementation follows these principles:

* Infrastructure provisioning is separated from platform configuration.
* Reusable logic is encapsulated in Ansible roles.
* `site.yml` is the single Ansible orchestration entry point.
* Tags provide targeted role execution.
* Control-plane changes are executed serially.
* Kubernetes networking is provided by Cilium.
* Cilium provides kube-proxy replacement and Gateway API integration.
* Persistent storage is provided through NFS CSI.
* Git remains the source of truth for persistent GitOps configuration.
* Monitoring is managed through GitOps.
* Recovery procedures prioritize preserving etcd quorum and cluster state.
* Operational validation is separated from architecture documentation.

## Related Documentation

```text
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
└── operations/
    ├── startup-shutdown.md
    ├── validation.md
    └── control-plane-failure.md
```
