# Argo CD and GitOps

## Overview

Argo CD is used as the GitOps controller for the Kubernetes platform.

Git is the source of truth for Kubernetes application and platform
configuration, while Argo CD continuously reconciles the desired state
with the live Kubernetes cluster.

The GitOps architecture manages both application workloads and platform
resources, including monitoring and Gateway API configuration.

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

This structure separates application, monitoring, and networking
configuration while keeping them under the same GitOps repository.

## Applications

### dev-nginx

The NGINX application is deployed from Git manifests into:

```text
namespace: demo
```

The application consists of Kubernetes resources defining the workload
and its Service.

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

### dev-gateway

The Gateway API resources are managed through the GitOps application:

```text
dev-gateway
```

The source path is:

```text
environments/dev/kubernetes/gateway
```

The application manages the Cilium Gateway configuration and associated
HTTP routing resources.

The Gateway configuration includes:

* CiliumLoadBalancerIPPool
* CiliumL2AnnouncementPolicy
* Gateway
* HTTPRoute
* ReferenceGrant

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

## Argo CD Installation Architecture

Argo CD is installed using Ansible.

The relevant roles are:

```text
ansible/roles/argocd/
ansible/roles/argocd_bootstrap/
```

The separation between installation and application management is
intentional:

```text
Ansible
   |
   v
Argo CD
   |
   v
GitOps Resources
```

Ansible establishes the Argo CD platform, while Argo CD manages the
Kubernetes resources defined by the Git repository.

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

## Gateway API Integration

Argo CD participates in the Gateway API architecture through a dedicated
HTTPRoute:

```text
argocd-route
```

The HTTPRoute is located in the `default` namespace and references the
Argo CD Service in the `argocd` namespace.

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

Argo CD represents differences between the desired state in Git and the
live Kubernetes state as synchronization drift.

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

When the live state differs from the desired Git state, Argo CD can
identify the resource as `OutOfSync`.

Persistent configuration changes belong in Git so that the desired state
remains reproducible and auditable.

Manual changes to GitOps-managed resources are therefore not considered
the persistent source of truth.

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
             |                 |
             |                 v
             |             Reconciliation
             |                 |
             +--------<--------+
```

This allows GitOps-managed resources to remain aligned with the declared
configuration.

## Current GitOps Applications

The current environment includes the following major Argo CD applications:

| Application      | Purpose                              |
| ---------------- | ------------------------------------ |
| `dev-nginx`      | NGINX application                    |
| `dev-monitoring` | Prometheus, Grafana and Alertmanager |
| `dev-gateway`    | Cilium Gateway API resources         |

The applications represent different layers of the Kubernetes platform
while remaining managed through the same GitOps workflow.

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
* Git stores the desired configuration.

## Operational Principles

The GitOps architecture follows these principles:

* Git is the source of truth for persistent GitOps configuration.
* Argo CD is responsible for reconciliation.
* Kubernetes resources are represented declaratively.
* Configuration changes are version controlled.
* Application and platform resources can be managed through the same
  GitOps workflow.
* Manual changes to GitOps-managed resources should not become the
  persistent configuration.
* Gateway API configuration is managed through Git.
* Monitoring configuration is managed through Git.
* Git history provides an audit trail for configuration changes.
* The desired state remains reproducible.

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
└── operations/
    ├── validation.md
    ├── control-plane-failure.md
    └── startup-shutdown.md
```
