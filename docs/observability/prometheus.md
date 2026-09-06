# Prometheus and Kubernetes Observability

## Overview

The Platform Engineering Lab uses `kube-prometheus-stack` to provide
Kubernetes monitoring and observability.

The monitoring stack is deployed through Helm, managed by Argo CD, and
configured through Git.

The stack runs in the:

```text
monitoring
```

namespace.

The primary configuration is stored at:

```text
environments/dev/kubernetes/monitoring/kube-prometheus-stack/values.yaml
```

The monitoring architecture provides metrics collection, visualization,
alert management, Kubernetes object metrics, and node-level metrics.

## Architecture

```text
Git Repository
      |
      v
   Argo CD
      |
      v
kube-prometheus-stack
      |
      +-------------------+
      |                   |
      v                   v
 Prometheus            Grafana
      |                   |
      |                   |
      v                   v
Kubernetes Metrics   Cilium Gateway
                          |
                          v
                   Nginx Proxy Manager
                          |
                          v
                     HTTPS Client
```

Prometheus provides the metrics collection and query layer, while Grafana
provides visualization.

Alertmanager provides alert management for Prometheus-generated alerts.

## Components

The monitoring stack includes:

| Component             | Role                                   |
| --------------------- | -------------------------------------- |
| Prometheus            | Metrics collection and querying        |
| Grafana               | Visualization and dashboards           |
| Alertmanager          | Alert management                       |
| kube-state-metrics    | Kubernetes object and resource metrics |
| node-exporter         | Node-level operating system metrics    |
| kube-prometheus-stack | Helm-based monitoring stack            |

The monitoring system covers major Kubernetes platform components,
including:

* Kubernetes API server
* etcd
* kube-controller-manager
* kube-scheduler
* kubelet
* CoreDNS
* node-exporter
* kube-state-metrics

## Prometheus

Prometheus is deployed as part of the `kube-prometheus-stack`.

The Prometheus instance collects metrics from Kubernetes components and
monitoring exporters through Kubernetes monitoring resources.

The monitoring architecture provides visibility into both Kubernetes
control-plane health and workload/node infrastructure.

The current Prometheus configuration includes:

```text
Replica count: 1
Retention:     10d
Scrape interval: 30s
```

Prometheus therefore acts as the central metrics backend for the current
development environment.

## Control Plane Metrics

Control-plane metrics are collected from the Kubernetes control-plane
components:

* kube-apiserver
* kube-controller-manager
* kube-scheduler
* etcd

The control-plane metrics configuration is automated through:

```text
ansible/roles/k8s_control_plane_metrics/
```

The automation is integrated into the main Ansible platform configuration.

Control-plane changes are designed to be applied serially:

```yaml
serial: 1
```

This design reduces the risk of simultaneously disrupting multiple
control-plane nodes.

## etcd Metrics

The three control-plane nodes expose etcd metrics for Prometheus:

```text
CP01  192.168.1.20:2381
CP02  192.168.1.23:2381
CP03  192.168.1.24:2381
```

The three-member etcd cluster is therefore represented in Prometheus as
three monitoring targets.

The monitoring architecture provides visibility into the health of each
etcd member.

## Control Plane Metrics Endpoints

The Kubernetes control-plane components expose their metrics through their
standard secure metrics endpoints.

The current control-plane monitoring architecture includes:

```text
kube-apiserver
      |
      +-- metrics
      |
kube-controller-manager
      |
      +-- metrics
      |
kube-scheduler
      |
      +-- metrics
      |
etcd
      |
      +-- metrics
```

The control-plane manifest configuration is managed by Ansible rather than
being maintained as an independent manual configuration.

## Cilium and Kube-Proxy Replacement

The cluster uses Cilium kube-proxy replacement:

```yaml
kubeProxyReplacement: true
```

Because Cilium provides the service datapath, the traditional `kube-proxy`
component is not used as the cluster networking datapath.

The kube-prometheus-stack configuration therefore disables kube-proxy
monitoring:

```yaml
kubeProxy:
  enabled: false
```

This configuration is stored in:

```text
environments/dev/kubernetes/monitoring/kube-prometheus-stack/values.yaml
```

The monitoring configuration therefore reflects the actual networking
architecture rather than expecting metrics from a traditional kube-proxy
deployment.

## GitOps Management

The monitoring stack is managed through the Argo CD application:

```text
dev-monitoring
```

The configuration flow is:

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
 +-- kube-state-metrics
 +-- node-exporter
```

Git remains the source of truth for persistent monitoring configuration.

Argo CD reconciles the desired monitoring state with the Kubernetes
cluster.

## Grafana

Grafana is deployed as part of the monitoring stack.

The current external URL is:

```text
https://grafana.wawangholanda.biz.id
```

Grafana is configured with the external URL:

```yaml
grafana:
  grafana.ini:
    server:
      root_url: https://grafana.wawangholanda.biz.id
      serve_from_sub_path: false
```

This allows Grafana to generate links and redirects using the public HTTPS
hostname while its internal connection remains HTTP.

## Grafana External Access

Grafana is exposed through the same application ingress architecture used
by the platform.

The traffic path is:

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
grafana-route
  |
  v
monitoring/dev-monitoring-grafana
```

TLS termination occurs at Nginx Proxy Manager.

Cilium Gateway API is responsible for HTTP routing inside the Kubernetes
environment.

The Grafana `HTTPRoute` is managed through the GitOps application:

```text
dev-gateway
```

## Cross-Namespace Gateway Routing

The Grafana Service is located in the `monitoring` namespace, while the
Gateway and HTTPRoute are located in the `default` namespace.

Gateway API cross-namespace backend access is explicitly authorized using
a `ReferenceGrant`.

The Grafana ReferenceGrant is stored at:

```text
environments/dev/kubernetes/gateway/grafana-reference-grant.yaml
```

The resulting architecture is:

```text
default/grafana-route
        |
        | ReferenceGrant
        v
monitoring/dev-monitoring-grafana
```

This creates an explicit namespace boundary for the Gateway backend
reference.

## Monitoring Data Flow

The overall monitoring data flow is:

```text
Kubernetes Components
        |
        +-- kubelet
        +-- API server
        +-- etcd
        +-- controller-manager
        +-- scheduler
        +-- CoreDNS
        +-- node-exporter
        +-- kube-state-metrics
        |
        v
    Prometheus
        |
        +----------------+
        |                |
        v                v
    PromQL           Alert Rules
        |                |
        v                v
    Grafana         Alertmanager
```

Prometheus acts as the central source of metrics for both dashboards and
alert evaluation.

## Monitoring and GitOps Relationship

The monitoring platform is part of the broader GitOps architecture:

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
        Git Repository
            |
            +-- Applications
            +-- Monitoring
            +-- Gateway API
```

This separation provides clear ownership between infrastructure,
platform installation, and Kubernetes resource management.

## Control Plane Observability

The monitoring stack provides visibility across all three control-plane
nodes:

```text
CP01  192.168.1.20
CP02  192.168.1.23
CP03  192.168.1.24
```

The monitoring architecture includes metrics for:

```text
CP01 ── kube-apiserver
     ├─ kube-controller-manager
     ├─ kube-scheduler
     └─ etcd

CP02 ── kube-apiserver
     ├─ kube-controller-manager
     ├─ kube-scheduler
     └─ etcd

CP03 ── kube-apiserver
     ├─ kube-controller-manager
     ├─ kube-scheduler
     └─ etcd
```

This is particularly important for the HA control-plane architecture,
because the monitoring layer can distinguish individual control-plane
members rather than observing only the shared API endpoint.

## Lessons Learned

### Static Pod Configuration

Several Kubernetes control-plane components run as static Pods.

Their configuration is therefore closely coupled to the files under:

```text
/etc/kubernetes/manifests/
```

Control-plane metrics configuration must be handled carefully because
changes to these manifests can affect critical Kubernetes components.

Backup files should not be stored inside the kubelet static Pod manifest
directory because they may be interpreted as additional static Pod
manifests.

### Serial Control Plane Changes

Changes affecting multiple control-plane nodes are treated as a
potentially disruptive operation.

The Ansible configuration therefore uses:

```yaml
serial: 1
```

This preserves availability on the remaining control-plane nodes while
one node is being modified.

### etcd as a Critical Dependency

The monitoring architecture reinforces the dependency chain:

```text
etcd
  |
  v
kube-apiserver
  |
  v
Kubernetes API
  |
  v
Kubernetes platform services
```

Problems in etcd can therefore surface as higher-level API or platform
availability problems.

This makes etcd monitoring particularly important in a highly available
control-plane architecture.

### Avoid Destructive Recovery

The HA control plane depends on maintaining etcd membership and quorum.

Recovery therefore favors preserving the existing cluster state and
understanding the failure before performing destructive operations.

The monitoring layer provides supporting information for this recovery
process by exposing the health of individual etcd members and other
control-plane components.

### GitOps as Source of Truth

Persistent monitoring configuration is stored in Git and reconciled by
Argo CD.

This includes:

* Prometheus configuration
* Grafana configuration
* Alertmanager configuration
* kube-prometheus-stack values
* Grafana external URL configuration

Monitoring configuration therefore remains version controlled and
reproducible.

## Current Observability Capabilities

The current platform provides:

* Prometheus metrics collection
* Grafana dashboards
* Alertmanager
* kube-state-metrics
* node-exporter
* Kubernetes control-plane metrics
* etcd metrics
* kubelet metrics
* CoreDNS metrics
* GitOps-managed monitoring configuration
* Grafana external access
* Grafana routing through Cilium Gateway API
* TLS termination through Nginx Proxy Manager

## Future Improvements

Planned observability improvements include:

* Infrastructure failure alerts
* Notification integration
* Production-oriented dashboards
* Kubernetes workload dashboards
* Persistent logging
* Centralized log aggregation
* Additional Cilium observability
* Alerting for control-plane and worker-node failures
* Backup and disaster-recovery monitoring

## Related Documentation

```text
docs/
├── architecture/
│   └── kubernetes-ha.md
├── ansible/
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
    ├── validation.md
    ├── control-plane-failure.md
    └── startup-shutdown.md
```
