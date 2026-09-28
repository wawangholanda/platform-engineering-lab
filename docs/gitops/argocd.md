# Argo CD and GitOps

## Overview

Argo CD is used as the GitOps controller for the Kubernetes platform.

Git is the source of truth for Kubernetes application and platform
configuration, while Argo CD continuously reconciles the desired state with
the live Kubernetes cluster.

The GitOps architecture manages both application workloads and platform
resources, including monitoring and Gateway API configuration.

Argo CD is installed and bootstrapped by Ansible. After the platform is
available, Argo CD manages resources defined in the Git repository.

## Architecture

```text
                         Git Repository
                               |
                               v
                            Argo CD
                               |
                    +----------+----------+
                    |          |          |
                    v          v          v
              Applications  Monitoring  Gateway API
                    |          |          |
                    v          v          v
                dev-nginx  dev-monitoring dev-gateway
                               |          |
                               v          v
                      kube-prometheus-   Cilium Gateway
                         stack              |
                                           +-- HTTPRoute
                                           +-- ReferenceGrant
```

Argo CD continuously reconciles these resources against the desired state
defined in Git.

The architecture separates the responsibilities of infrastructure
provisioning, platform installation, and application delivery:

```text
Terraform
    |
    v
Proxmox Infrastructure
    |
    v
Ansible
    |
    +-- Kubernetes
    +-- Cilium
    +-- Argo CD
    |
    v
Argo CD
    |
    +-- Applications
    +-- Monitoring
    +-- Gateway API
```

## Repository Structure

GitOps-managed Kubernetes resources are stored under:

```text
environments/dev/kubernetes/

├── apps/
│   └── nginx/
│       ├── deployment.yaml
│       ├── namespace.yaml
│       └── service.yaml
│
├── monitoring/
│   └── kube-prometheus-stack/
│       └── values.yaml
│
└── gateway/
    ├── cilium-l2-announcement-policy.yaml
    ├── cilium-lb-ip-pool.yaml
    ├── nginx-gateway.yaml
    ├── nginx-route.yaml
    ├── argocd-route.yaml
    ├── argocd-reference-grant.yaml
    ├── grafana-route.yaml
    └── grafana-reference-grant.yaml
```

The structure separates application, monitoring, and networking configuration
while keeping them under the same GitOps repository.

## Applications

### dev-nginx

The NGINX application is deployed from Git manifests into:

```text
namespace: demo
```

The application consists of Kubernetes resources defining the workload,
namespace, and Service.

The application resources are stored under:

```text
environments/dev/kubernetes/apps/nginx/
```

### dev-monitoring

The monitoring stack is deployed using:

```text
kube-prometheus-stack
```

The Helm values are stored in:

```text
environments/dev/kubernetes/monitoring/kube-prometheus-stack/values.yaml
```

The stack provides:

* Prometheus
* Grafana
* Alertmanager
* Kubernetes monitoring components

The monitoring application is managed by the Argo CD application:

```text
dev-monitoring
```

### dev-gateway

The Gateway API resources are managed through:

```text
dev-gateway
```

The source path is:

```text
environments/dev/kubernetes/gateway/
```

The application manages Cilium Gateway configuration and associated HTTP
routing resources.

The Gateway configuration includes:

* `CiliumLoadBalancerIPPool`
* `CiliumL2AnnouncementPolicy`
* `Gateway`
* `HTTPRoute`
* `ReferenceGrant`

The primary application Gateway is:

```text
nginx-gateway
192.168.1.240
```

## GitOps Workflow

The desired state flows from Git into the Kubernetes cluster:

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
      +---- Monitoring
      +---- Gateway API
```

Git therefore acts as the persistent source of truth for GitOps-managed
resources.

Changes to the desired state are represented as version-controlled Git
changes and reconciled by Argo CD.

The normal change flow is:

```text
Developer Change
      |
      v
Git Commit
      |
      v
Git Repository
      |
      v
Argo CD Reconciliation
      |
      v
Kubernetes Resources
      |
      v
Workload / Platform State
```

## Argo CD Configuration

GitOps configuration is defined through:

```text
ansible/inventory/dev/group_vars/k8s.yml
```

The Git repository is:

```text
platform-engineering-lab
```

The target revision is:

```text
main
```

The repository URL configured for the environment is:

```text
https://github.com/wawangholanda/platform-engineering-lab.git
```

Argo CD itself is installed and configured through Ansible, while the
resources managed by Argo CD are defined in Git.

This creates a clear boundary:

```text
Ansible
   |
   +-- Install Argo CD
   +-- Bootstrap Argo CD
   |
   v
Argo CD
   |
   +-- Reconcile GitOps Applications
   |
   v
Kubernetes
```

## Argo CD Installation Architecture

Argo CD is installed using Ansible.

The relevant roles are:

```text
ansible/roles/argocd/
ansible/roles/argocd_bootstrap/
```

The platform playbook is:

```text
ansible/playbooks/site.yml
```

The separation between installation and application management is intentional.

Ansible establishes the Argo CD platform, while Argo CD manages the Kubernetes
resources defined by the Git repository.

This means a cluster reconstruction can follow the same layered process:

```text
Proxmox
   |
   v
Terraform
   |
   v
Ansible
   |
   v
Argo CD
   |
   v
GitOps Resources
```

## External Access

Argo CD is exposed externally through Cilium Gateway API and Nginx Proxy
Manager.

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
  v
argocd-route
  |
  v
argocd/argocd-server:80
```

The public hostname is:

```text
argocd.wawangholanda.biz.id
```

TLS is terminated at Nginx Proxy Manager.

Argo CD is configured to serve HTTP internally:

```yaml
configs:
  params:
    server.insecure: "true"
```

This prevents Argo CD from attempting to terminate TLS again behind the
reverse proxy.

The external access path therefore separates TLS termination from Kubernetes
application routing:

```text
External HTTPS
      |
      v
Nginx Proxy Manager
      |
      v
Cilium Gateway API
      |
      v
Argo CD Service
```

## Gateway API Integration

Argo CD participates in the Gateway API architecture through a dedicated
HTTPRoute:

```text
argocd-route
```

The HTTPRoute is located in the `default` namespace and references the Argo CD
Service in the `argocd` namespace.

Because the backend Service is located in another namespace, the routing
configuration uses:

```text
ReferenceGrant
```

The Argo CD ReferenceGrant is stored at:

```text
environments/dev/kubernetes/gateway/argocd-reference-grant.yaml
```

This creates an explicit cross-namespace permission for the Gateway API
backend reference.

The same Gateway API architecture is also used for Grafana and the NGINX
application.

## Monitoring Integration

The `dev-monitoring` application deploys the observability stack.

The relationship is:

```text
Git
 |
 +-- values.yaml
 |
 v
Argo CD
 |
 v
Helm
 |
 v
kube-prometheus-stack
 |
 +-- Prometheus
 +-- Grafana
 +-- Alertmanager
```

Grafana is also exposed through the Cilium Gateway API.

The routing flow is:

```text
grafana.wawangholanda.biz.id
             |
             v
      Nginx Proxy Manager
             |
             v
       Cilium Gateway
             |
             v
       grafana-route
             |
             v
monitoring/dev-monitoring-grafana
```

The Grafana Gateway configuration is managed by the `dev-gateway`
application.

Monitoring details are documented separately in:

```text
docs/observability/prometheus.md
```

## Configuration Drift

Argo CD represents differences between the desired state in Git and the live
Kubernetes state as synchronization drift.

The conceptual state flow is:

```text
Desired State in Git
        |
        v
      Argo CD
        |
        v
  Live Kubernetes State
```

When the live state differs from the desired Git state, Argo CD can identify
the resource as:

```text
OutOfSync
```

Persistent configuration changes belong in Git so that the desired state
remains reproducible and auditable.

Manual changes to GitOps-managed resources are therefore not considered the
persistent source of truth.

When troubleshooting a resource, the desired state in Git should be checked
before making persistent manual changes to the cluster.

## Self-Healing and Reconciliation

Argo CD continuously compares the desired state with the live cluster.

The reconciliation model is:

```text
Git
 |
 | Desired State
 v
Argo CD
 |
 | Reconciliation
 v
Kubernetes
 |
 | Actual State
 +--------------------+
                      |
                      v
                State Comparison
                      |
             +--------+--------+
             |                 |
             v                 v
          Synced            OutOfSync
                               |
                               v
                         Reconciliation
                               |
                               +-------->
```

This allows GitOps-managed resources to remain aligned with the declared
configuration.

The exact synchronization behavior depends on the Argo CD application
configuration and its configured sync policies.

## Current GitOps Applications

The current environment includes the following major Argo CD applications:

| Application      | Purpose                               |
| ---------------- | ------------------------------------- |
| `dev-nginx`      | NGINX application                     |
| `dev-monitoring` | Prometheus, Grafana, and Alertmanager |
| `dev-gateway`    | Cilium Gateway API resources          |

The applications represent different layers of the Kubernetes platform while
remaining managed through the same GitOps workflow.

The current applications can be inspected with:

```bash
kubectl get applications -n argocd
```

For synchronization and health state:

```bash
kubectl get applications -n argocd \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
```

## Separation of Responsibilities

The platform uses different tools for different management layers:

```text
Terraform
   |
   v
Proxmox Infrastructure
   |
   v
Ansible
   |
   +-- Kubernetes Cluster
   +-- Cilium
   +-- Argo CD
   |
   v
Argo CD
   |
   +-- Applications
   +-- Monitoring
   +-- Gateway API
```

This creates a layered infrastructure model:

* Terraform manages infrastructure.
* Ansible manages cluster and platform installation.
* Argo CD manages Kubernetes application and platform resources.
* Git stores the desired configuration for GitOps-managed resources.

The separation is important during disaster recovery because each layer has a
different recovery responsibility.

## Disaster Recovery Relationship

Argo CD is part of the Kubernetes platform reconstruction process.

During a full Kubernetes reconstruction:

```text
Proxmox Bootstrap
       |
       v
Terraform
       |
       v
Ansible
       |
       v
Kubernetes
       |
       v
Argo CD
       |
       v
GitOps Applications
```

The Git repository allows GitOps-managed resources to be reconstructed after
the Kubernetes cluster has been restored.

Argo CD does not replace etcd backups.

Kubernetes control-plane state and GitOps source state are separate recovery
layers:

```text
etcd
 |
 +-- Kubernetes API objects and control-plane state

Git
 |
 +-- GitOps desired state
```

An etcd restore can restore Kubernetes objects that existed at the snapshot
point, but it does not replace the Git repository as the persistent source of
truth for GitOps-managed configuration.

The full reconstruction procedure is documented in:

```text
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
```

## Operational Principles

The GitOps architecture follows these principles:

* Git is the source of truth for persistent GitOps configuration.
* Argo CD is responsible for reconciliation.
* Kubernetes resources are represented declaratively.
* Configuration changes are version controlled.
* Application and platform resources can be managed through the same GitOps
  workflow.
* Manual changes to GitOps-managed resources should not become the persistent
  configuration.
* Gateway API configuration is managed through Git.
* Monitoring configuration is managed through Git.
* Git history provides an audit trail for configuration changes.
* The desired state remains reproducible.
* Infrastructure provisioning remains separate from application delivery.
* Disaster recovery procedures preserve the separation between etcd state and
  GitOps desired state.

## Future Improvements

Planned GitOps improvements include:

* Automated sync policies
* Pull-request-based deployment workflow
* Environment promotion
* Progressive delivery
* Secret management integration
* Multi-environment GitOps structure
* Automated deployment validation
* Policy-based deployment controls

These improvements should preserve the existing separation between
infrastructure provisioning, platform configuration, and GitOps application
delivery.

## Related Documentation

```text
docs/
├── architecture/
│   └── kubernetes-ha.md
├── ansible/
│   └── architecture.md
├── terraform/
│   └── architecture.md
├── kubernetes/
│   ├── cluster-bootstrap.md
│   ├── networking-cilium.md
│   └── storage-nfs.md
├── observability/
│   └── prometheus.md
├── operations/
│   ├── validation.md
│   ├── control-plane-failure.md
│   └── startup-shutdown.md
└── disaster-recovery/
    ├── kubernetes-disaster-recovery-runbook.md
    ├── control-plane-node-recovery.md
    ├── worker-node-recovery.md
    └── etcd-restore-runbook.md
```
