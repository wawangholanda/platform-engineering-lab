# Kubernetes Cluster Bootstrap

## Overview

The Kubernetes cluster is provisioned on Proxmox using Terraform and
configured with Ansible.

The bootstrap process is divided into infrastructure provisioning,
platform configuration, and application delivery:

```text
Proxmox Bootstrap
        |
        v
Terraform
        |
        v
Proxmox VMs
        |
        v
Ansible Platform Bootstrap
        |
        +-------------------+
        |                   |
        v                   v
Load Balancers       Kubernetes Nodes
                            |
                            v
                         kubeadm
                            |
                            v
                         Cilium
                            |
                            v
                       NFS / CSI
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
                         Validation
```

Proxmox Bootstrap prepares the Proxmox environment required by Terraform,
including the Terraform API credentials and the Ubuntu VM template.

Terraform provisions the virtual machines.

Ansible configures the operating system and Kubernetes platform.

Argo CD then manages persistent Kubernetes application and platform
resources from Git.

The Ansible platform bootstrap also configures etcd backup automation and
performs Kubernetes platform validation after the platform has been
established.

This separation allows infrastructure, platform configuration, and
application configuration to be managed independently.

## Bootstrap Flow

The complete reconstruction flow is:

```text
Proxmox Bootstrap
        |
        v
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
Workstation Kubeconfig
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
NFS Server
        |
        v
NFS CSI
        |
        v
Argo CD
        |
        v
GitOps Bootstrap
        |
        v
etcd Backup
        |
        v
Kubernetes Platform Validation
```

The bootstrap sequence is intentionally ordered so that the Kubernetes
control plane is established before workers and higher-level platform
services are configured.

## Infrastructure Bootstrap

Before Terraform can provision the Kubernetes infrastructure, the Proxmox
host is prepared through:

```text
ansible/playbooks/proxmox-bootstrap.yml
```

The corresponding role is:

```text
ansible/roles/proxmox_bootstrap/
```

The Proxmox bootstrap prepares the Terraform provisioning prerequisites:

* Terraform API user
* Terraform API role
* Terraform API token
* Required Proxmox ACLs
* Ubuntu 24.04 VM template
* Cloud-init configuration required by the template

The current Kubernetes VM template is:

```text
VMID: 9000
Name: ubuntu-2404-template
```

The infrastructure provisioning stage is then handled by Terraform under:

```text
environments/dev/proxmox/
```

The Terraform lifecycle is:

```text
Proxmox Bootstrap
        |
        v
Terraform init
        |
        v
Terraform validate
        |
        v
Terraform plan
        |
        v
Terraform apply
        |
        v
Proxmox VMs
```

Terraform is responsible for infrastructure state, while Ansible is
responsible for operating-system and platform configuration.

## Cluster Configuration

| Component    | Value             |
| ------------ | ----------------- |
| Kubernetes   | 1.34.11           |
| kubeadm      | 1.34.11           |
| kubelet      | 1.34.11           |
| containerd   | 2.2.1             |
| OS           | Ubuntu 24.04.5    |
| CNI          | Cilium 1.20.0     |
| Helm         | 3.21.4            |
| Pod CIDR     | 10.0.0.0/16       |
| Service CIDR | 10.96.0.0/12      |
| Cluster DNS  | 10.96.0.10        |
| API Endpoint | 192.168.1.30:6443 |

## Node Topology

| Host         | Role          | IP           |
| ------------ | ------------- | ------------ |
| k8s-cp01     | Control Plane | 192.168.1.20 |
| k8s-worker01 | Worker        | 192.168.1.21 |
| k8s-worker02 | Worker        | 192.168.1.22 |
| k8s-cp02     | Control Plane | 192.168.1.23 |
| k8s-cp03     | Control Plane | 192.168.1.24 |
| k8s-lb01     | Load Balancer | 192.168.1.25 |
| k8s-lb02     | Load Balancer | 192.168.1.26 |
| k8s-nfs01    | NFS Server    | 192.168.1.27 |

The Kubernetes API uses a virtual endpoint at:

```text
192.168.1.30:6443
```

## Kubernetes API High Availability

The Kubernetes API is exposed through a highly available virtual endpoint:

```text
192.168.1.30:6443
```

The endpoint is implemented using two load-balancer nodes:

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
        192.168.1.20 192.168.1.23 192.168.1.24
```

HAProxy distributes Kubernetes API traffic across the control-plane nodes.

Keepalived provides the virtual IP and failover between the two load
balancers.

The control plane uses a three-member stacked etcd topology.

## Ansible Platform Bootstrap

The main Ansible entry point is:

```text
ansible/playbooks/site.yml
```

The playbook configures the Kubernetes platform after Terraform has
provisioned the required virtual machines.

The execution order implemented by `site.yml` is:

```text
1. Load Balancers
2. Common Kubernetes Configuration
3. First Control Plane
4. Workstation Kubeconfig
5. Additional Control Planes
6. Control-Plane Metrics
7. Helm
8. Cilium
9. Workers
10. NFS Server
11. NFS CSI
12. Argo CD
13. GitOps Bootstrap
14. etcd Backup
15. Kubernetes Platform Validation
```

The platform configuration is implemented through reusable Ansible roles.

### Workstation Kubeconfig

After the first control plane is bootstrapped, the `kubeconfig` role
configures access to the Kubernetes cluster from the Ansible control
workstation.

The corresponding role is:

```text
ansible/roles/kubeconfig/
```

This step is executed immediately after the first control plane is
initialized and before additional control planes join the cluster.

## Common Node Configuration

The `k8s_common` role prepares Kubernetes nodes with the required
operating-system and container-runtime configuration.

Responsibilities include:

* OS prerequisites
* Swap configuration
* Kernel modules
* Sysctl configuration
* containerd
* Kubernetes package repository
* kubeadm
* kubelet
* kubectl

This provides a consistent baseline across control-plane and worker nodes.

## Control Plane

The first control-plane node initializes the Kubernetes cluster through:

```text
ansible/roles/k8s_control_plane/
```

Additional control-plane nodes join through:

```text
ansible/roles/k8s_control_plane_join/
```

The control plane consists of:

```text
k8s-cp01
k8s-cp02
k8s-cp03
```

The first control plane establishes the initial Kubernetes control-plane
state.

Additional control planes join the existing cluster and participate in
the three-member stacked etcd topology.

Control-plane changes are executed serially to reduce the risk of
disrupting multiple control-plane nodes simultaneously.

## Control-Plane Metrics

Control-plane metrics configuration is handled through:

```text
ansible/roles/k8s_control_plane_metrics/
```

This role configures the metrics-related settings required for the
observability stack to monitor Kubernetes control-plane components.

Control-plane metrics configuration is performed after the control plane
has been established.

The role runs serially across the control-plane nodes.

## Workers

Worker nodes are configured through:

```text
ansible/roles/k8s_worker/
```

The worker layer currently consists of:

```text
k8s-worker01
k8s-worker02
```

Worker nodes join the existing Kubernetes cluster after Cilium networking
is available.

Worker joins are performed serially to keep the bootstrap process
predictable and to reduce operational blast radius.

## Helm

Helm provides the package-management layer for Kubernetes platform
components.

The corresponding Ansible role is:

```text
ansible/roles/helm/
```

Helm is installed before components that depend on Helm-based deployment,
including Cilium and Argo CD.

Helm is primarily used as the package-management mechanism during platform
bootstrap, while persistent application configuration is managed through
GitOps.

## Cilium Networking

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

The detailed Cilium architecture and configuration are documented in:

```text
docs/kubernetes/networking-cilium.md
```

## Gateway API

Cilium Gateway API provides the application ingress layer inside the
Kubernetes cluster.

The application traffic path is:

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

Gateway resources are managed through GitOps after the initial platform
bootstrap.

The detailed networking configuration is documented in:

```text
docs/kubernetes/networking-cilium.md
```

## Persistent Storage

Persistent storage is provided through the NFS server and the Kubernetes
NFS CSI driver.

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
    |
    v
Application Pod
```

The corresponding Ansible roles are:

```text
ansible/roles/nfs_server/

ansible/roles/nfs_csi/
```

The NFS server is provisioned as part of the infrastructure and configured
by Ansible.

The NFS CSI driver integrates the NFS backend with Kubernetes persistent
storage.

The detailed storage configuration is documented in:

```text
docs/kubernetes/storage-nfs.md
```

## Argo CD and GitOps

Argo CD provides the GitOps control plane through:

```text
ansible/roles/argocd/

ansible/roles/argocd_bootstrap/
```

Ansible installs and bootstraps Argo CD.

After Argo CD is established, persistent Kubernetes application and
platform configuration is managed from the Git repository.

Current GitOps-managed areas include:

```text
Applications
    |
    +-- nginx
    |
    +-- Monitoring
    |
    +-- Gateway API resources
```

Git remains the source of truth for persistent GitOps configuration.

The detailed Argo CD architecture is documented in:

```text
docs/gitops/argocd.md
```

## etcd Backup

The etcd backup automation is configured through:

```text
ansible/roles/etcd_backup/
```

The role configures the automated backup mechanism for Kubernetes etcd
state, including the backup schedule, local backup storage, and off-node
backup integration where configured.

The backup stage runs after the Kubernetes platform and GitOps bootstrap
have been established.

Detailed backup and restore procedures are documented in:

```text
docs/operations/etcd-backup-and-restore.md
docs/operations/disaster-recovery.md
```

## Monitoring

The observability stack uses `kube-prometheus-stack`.

The monitoring platform includes:

* Prometheus
* Grafana
* Alertmanager
* kube-state-metrics
* node-exporter

Monitoring configuration is managed through Argo CD rather than being
maintained independently from Git.

Grafana is exposed through the same application Gateway architecture:

```text
Nginx Proxy Manager
        |
        v
Cilium Gateway
        |
        v
Grafana Service
```

The detailed Prometheus and monitoring configuration is documented in:

```text
docs/observability/prometheus.md
```

## Kubernetes Platform Validation

The final platform validation stage is handled through:

```text
ansible/roles/k8s_validation/
```

The role runs against the first control-plane node after the platform
bootstrap has completed.

Validation verifies the reconstructed Kubernetes platform and provides
an automated post-bootstrap check.

The dedicated validation procedures are documented in:

```text
docs/operations/validation.md
docs/validation/kubernetes-cluster-reconstruction.md
```

## Bootstrap Responsibilities

The bootstrap architecture separates responsibilities across the platform:

| Layer                 | Tool      | Responsibility                               |
| --------------------- | --------- | -------------------------------------------- |
| Proxmox bootstrap     | Ansible   | Prepare Terraform API access and VM template |
| Infrastructure        | Terraform | Provision Proxmox VMs                        |
| OS and platform       | Ansible   | Configure nodes and Kubernetes platform      |
| Kubernetes networking | Cilium    | Provide cluster networking and Gateway API   |
| Storage               | NFS CSI   | Provide Kubernetes persistent storage        |
| Application delivery  | Argo CD   | Reconcile Git-managed resources              |
| Monitoring            | Argo CD   | Deploy and manage monitoring configuration   |
| Backup                | Ansible   | Configure automated etcd backup              |
| Validation            | Ansible   | Validate the Kubernetes platform             |

This separation prevents infrastructure provisioning logic from being
mixed with Kubernetes application configuration.

## Idempotency

The bootstrap automation is designed to be safely re-applied.

Idempotency is supported through:

* Declarative Ansible tasks
* Reusable roles
* Conditional execution
* Kubernetes declarative resources
* Helm release management
* GitOps reconciliation
* Terraform state management

The Proxmox bootstrap can be re-run when the Terraform provisioning
prerequisites need to be reconstructed.

The platform playbook can be re-run when Kubernetes nodes or platform
components require reconciliation.

Targeted role execution can be used when only a specific platform
component requires reconciliation.

Validation procedures for Ansible execution and idempotency are maintained
separately from this architecture document.

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

Ansible control-plane operations use serial execution to reduce the blast
radius of configuration changes.

## Recovery Principles

Control-plane recovery follows a dependency-oriented approach:

```text
API unavailable
      |
      v
Load Balancer / API Endpoint
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
```

Recovery should begin with state inspection rather than destructive
reinitialization.

Operations such as:

```text
kubeadm reset

rm -rf /var/lib/etcd

etcd member remove

etcd member add
```

should not be performed until the current cluster and etcd state are
understood.

Single control-plane node recovery is documented in:

```text
docs/disaster-recovery/control-plane-node-recovery.md
```

etcd state recovery is documented in:

```text
docs/disaster-recovery/etcd-restore-runbook.md
```

Full Kubernetes platform reconstruction is documented in:

```text
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
```

## Design Principles

The bootstrap implementation follows these principles:

* Infrastructure provisioning is separated from platform configuration.
* Proxmox prerequisites are prepared before Terraform provisioning.
* Reusable logic is encapsulated in Ansible roles.
* `site.yml` is the main Ansible platform orchestration entry point.
* Terraform manages infrastructure state.
* Tags provide targeted Ansible role execution.
* Control-plane changes are executed serially.
* Kubernetes networking is provided by Cilium.
* Cilium provides kube-proxy replacement and Gateway API integration.
* Persistent storage is provided through NFS CSI.
* Git remains the source of truth for persistent GitOps configuration.
* Monitoring is managed through GitOps.
* Automated etcd backup is part of the platform bootstrap.
* Automated Kubernetes platform validation is part of the platform bootstrap.
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
├── operations/
│   ├── startup-shutdown.md
│   ├── validation.md
│   ├── control-plane-failure.md
│   ├── disaster-recovery.md
│   └── etcd-backup-and-restore.md
│
└── disaster-recovery/
    ├── kubernetes-disaster-recovery-runbook.md
    ├── control-plane-node-recovery.md
    ├── worker-node-recovery.md
    └── etcd-restore-runbook.md
```
