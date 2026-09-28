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

The monitoring architecture provides:

* Metrics collection
* Kubernetes object metrics
* Node-level metrics
* Control-plane metrics
* Grafana dashboards
* Alert management
* Kubernetes workload visibility
* Monitoring of the cluster networking layer

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
      |                   v
      |             grafana-route
      |                   |
      |                   v
      |            Cilium Gateway
      |                   |
      |                   v
      |           Nginx Proxy Manager
      |                   |
      |                   v
      |              HTTPS Client
      |
      +-- Kubernetes Components
      +-- kube-state-metrics
      +-- node-exporter
      +-- kubelet
      +-- CoreDNS
```

Prometheus provides the central metrics collection and query layer.

Grafana provides visualization and dashboards.

Alertmanager provides alert management for Prometheus-generated alerts.

Argo CD continuously reconciles the monitoring resources defined in Git.

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
* Kubernetes workloads

## Prometheus

Prometheus is deployed as part of `kube-prometheus-stack`.

The Prometheus instance collects metrics from Kubernetes components,
exporters, and monitoring resources configured by the monitoring stack.

The current development environment uses:

```text
Replica count:   1
Retention:       10d
Scrape interval: 30s
```

Prometheus therefore acts as the central metrics backend for the current
development environment.

The current single-replica configuration provides monitoring visibility
but does not provide Prometheus high availability.

## Control Plane Metrics

Control-plane metrics are collected from:

* kube-apiserver
* kube-controller-manager
* kube-scheduler
* etcd

The control-plane metrics configuration is automated through:

```text
ansible/roles/k8s_control_plane_metrics/
```

The automation is integrated into the main Ansible platform configuration.

Changes affecting multiple control-plane nodes are applied serially:

```yaml
serial: 1
```

This reduces the risk of simultaneously disrupting multiple control-plane
nodes.

## etcd Metrics

The three control-plane nodes expose etcd metrics for Prometheus:

```text
CP01  192.168.1.20:2381
CP02  192.168.1.23:2381
CP03  192.168.1.24:2381
```

The three-member etcd cluster is therefore represented as individual
monitoring targets.

This allows Prometheus to provide visibility into the health and behavior
of individual etcd members rather than only the overall cluster state.

etcd remains a critical dependency for Kubernetes control-plane state, so
etcd metrics are important when troubleshooting API or control-plane
problems.

## Control Plane Metrics Endpoints

The Kubernetes control-plane components expose metrics through their
configured metrics endpoints.

The current control-plane monitoring architecture includes:

```text
kube-apiserver
      |
      +-- metrics

kube-controller-manager
      |
      +-- metrics

kube-scheduler
      |
      +-- metrics

etcd
      |
      +-- metrics
```

The control-plane manifest configuration is managed by Ansible rather than
being maintained as an independent manual configuration.

Control-plane metric configuration should therefore be changed through the
corresponding Ansible role and validated after deployment.

## Cilium and Kube-Proxy Replacement

The cluster uses Cilium kube-proxy replacement:

```yaml
kubeProxyReplacement: true
```

Cilium provides the Kubernetes service datapath, so the traditional
`kube-proxy` component is not used as the cluster networking datapath.

The kube-prometheus-stack configuration therefore disables kube-proxy
monitoring:

```yaml
kubeProxy:
  enabled: false
```

This configuration is stored at:

```text
environments/dev/kubernetes/monitoring/kube-prometheus-stack/values.yaml
```

The monitoring configuration therefore reflects the actual cluster
networking architecture.

## GitOps Management

The monitoring stack is managed through the Argo CD application:

```text
dev-monitoring
```

The configuration flow is:

```text
Git
 |
 +-- kube-prometheus-stack/values.yaml
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

Changes to persistent monitoring configuration should therefore be made
through Git rather than by directly modifying generated Kubernetes
resources.

## Grafana

Grafana is deployed as part of the monitoring stack.

The current external URL is:

```text
https://grafana.wawangholanda.biz.id
```

Grafana is configured with the public HTTPS hostname:

```yaml
grafana:
  grafana.ini:
    server:
      root_url: https://grafana.wawangholanda.biz.id
      serve_from_sub_path: false
```

This allows Grafana to generate links and redirects using the public
hostname while the internal Kubernetes connection remains HTTP.

## Grafana External Access

Grafana uses the platform's application ingress architecture.

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

Cilium Gateway API provides HTTP routing inside the Kubernetes environment.

The Grafana `HTTPRoute` is managed through the GitOps application:

```text
dev-gateway
```

The Gateway configuration is stored under:

```text
environments/dev/kubernetes/gateway/
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
        +-- kube-apiserver
        +-- etcd
        +-- kube-controller-manager
        +-- kube-scheduler
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
    PromQL         Alert Rules
        |                |
        v                v
    Grafana         Alertmanager
```

Prometheus acts as the central metrics backend for dashboards and alert
evaluation.

## Control Plane Observability

The monitoring stack provides visibility across all three control-plane
nodes:

```text
CP01  192.168.1.20
CP02  192.168.1.23
CP03  192.168.1.24
```

The monitoring architecture includes metrics associated with:

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

This is important for the HA control-plane architecture because monitoring
can distinguish individual control-plane members rather than observing
only the shared API endpoint.

## Monitoring the Kubernetes API

The Kubernetes API is exposed through the HA endpoint:

```text
192.168.1.30:6443
```

The API endpoint is backed by:

```text
HAProxy + Keepalived
        |
        +-- CP01 192.168.1.20
        +-- CP02 192.168.1.23
        +-- CP03 192.168.1.24
```

Prometheus provides component-level metrics, while API availability can
also be validated independently:

```bash
kubectl get --raw='/readyz?verbose'
```

The shared API endpoint and individual control-plane metrics should be
considered separately when diagnosing a control-plane failure.

## Monitoring Cilium

Cilium is the cluster networking layer and provides:

* Pod networking
* Service networking
* kube-proxy replacement
* Gateway API
* LoadBalancer IP management
* L2 announcements
* Network policy and observability capabilities

The current Cilium version is:

```text
1.20.0
```

Cilium components can be inspected with:

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
```

Cilium-specific troubleshooting should be combined with Prometheus metrics,
Cilium status, Kubernetes events, and Gateway API state.

Detailed networking configuration is documented in:

```text
docs/kubernetes/networking-cilium.md
```

## Monitoring Nodes and Workloads

`node-exporter` provides operating-system-level metrics from Kubernetes
nodes.

`kube-state-metrics` provides metrics derived from Kubernetes API objects,
including information about:

* Nodes
* Pods
* Deployments
* StatefulSets
* DaemonSets
* Jobs
* Services
* PersistentVolumeClaims

These metrics allow Grafana dashboards and Prometheus queries to correlate
node-level conditions with Kubernetes workload state.

For example, node availability and workload scheduling should be examined
together during worker-node failures.

## Monitoring Storage

The Kubernetes platform uses NFS and the NFS CSI driver for persistent
storage.

The monitoring stack can provide Kubernetes object-level visibility for
storage resources such as:

* PersistentVolumes
* PersistentVolumeClaims
* StorageClasses

Storage availability should also be validated independently from
Prometheus because a healthy monitoring stack does not prove that the
underlying NFS data is available.

The NFS architecture is documented in:

```text
docs/kubernetes/storage-nfs.md
```

## Monitoring and GitOps Relationship

The monitoring platform is part of the broader platform architecture:

```text
Proxmox Bootstrap
        |
        v
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

The responsibilities are separated:

* Proxmox Bootstrap prepares the infrastructure prerequisites.
* Terraform manages Proxmox infrastructure.
* Ansible configures the Kubernetes platform.
* Argo CD manages GitOps resources.
* Prometheus collects platform metrics.
* Grafana provides visualization.
* Alertmanager handles alerts.

This separation makes monitoring configuration reproducible and
consistent with the overall platform engineering architecture.

## Lessons Learned

### Static Pod Configuration

Several Kubernetes control-plane components run as static Pods.

Their configuration is closely coupled to:

```text
/etc/kubernetes/manifests/
```

Control-plane metrics configuration must therefore be handled carefully
because changes to these manifests can affect critical Kubernetes
components.

Backup files should not be stored inside the kubelet static Pod manifest
directory because they may be interpreted as additional static Pod
manifests.

### Serial Control Plane Changes

Changes affecting multiple control-plane nodes are potentially disruptive.

The Ansible configuration therefore uses:

```yaml
serial: 1
```

This preserves availability on the remaining control-plane nodes while one
control-plane node is being modified.

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

This makes individual etcd member monitoring important in a highly
available control-plane architecture.

### Avoid Destructive Recovery

The HA control plane depends on maintaining etcd membership and quorum.

Recovery should therefore favor preserving the existing cluster state and
understanding the failure before performing destructive operations.

Monitoring provides supporting information for this recovery process by
exposing the health of individual etcd members and other control-plane
components.

Detailed recovery procedures are documented separately in the disaster
recovery runbooks.

### GitOps as Source of Truth

Persistent monitoring configuration is stored in Git and reconciled by
Argo CD.

This includes:

* Prometheus configuration
* Grafana configuration
* Alertmanager configuration
* kube-prometheus-stack values
* Grafana external URL configuration
* Monitoring-related Kubernetes resources

Monitoring configuration therefore remains version controlled and
reproducible.

## Monitoring Validation

The following checks provide a basic operational validation of the
monitoring stack.

Check monitoring pods:

```bash
kubectl get pods -n monitoring
```

Check Prometheus:

```bash
kubectl get prometheus -n monitoring
```

Check Grafana:

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana
```

Check Alertmanager:

```bash
kubectl get alertmanager -n monitoring
```

Check monitoring services:

```bash
kubectl get svc -n monitoring
```

Check Argo CD application state:

```bash
kubectl get application dev-monitoring -n argocd
```

Check Prometheus readiness:

```bash
curl -s http://localhost:9091/-/ready
```

Expected result:

```text
Prometheus Server is Ready.
```

Check Prometheus targets from the Prometheus UI or API and verify that
expected Kubernetes and node monitoring targets are healthy.

A monitoring validation should also confirm that no unexpected targets are
reporting persistent scrape failures.

## Observability During Failure Recovery

Monitoring is a supporting system for Kubernetes failure recovery.

During control-plane recovery, use monitoring to observe:

* etcd member health
* API server health
* Control-plane component availability
* Node availability
* Cilium health
* Workload status

During worker-node recovery, use monitoring to observe:

* Node availability
* Pod scheduling
* Workload restart behavior
* Resource pressure
* Persistent storage-related symptoms

Monitoring does not replace the recovery procedures.

The relevant recovery runbooks remain:

```text
docs/disaster-recovery/control-plane-node-recovery.md
docs/disaster-recovery/worker-node-recovery.md
docs/disaster-recovery/etcd-restore-runbook.md
docs/disaster-recovery/kubernetes-disaster-recovery-runbook.md
```

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
* Kubernetes object metrics
* GitOps-managed monitoring configuration
* Grafana external access
* Grafana routing through Cilium Gateway API
* TLS termination through Nginx Proxy Manager
* Monitoring visibility for Kubernetes nodes and workloads

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
* Prometheus high availability
* Long-term metrics storage
* Additional SLO and platform-health dashboards

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
├── operations/
│   ├── validation.md
│   ├── control-plane-failure.md
│   ├── disaster-recovery.md
│   ├── etcd-backup-and-restore.md
│   └── startup-shutdown.md
└── disaster-recovery/
    ├── control-plane-node-recovery.md
    ├── worker-node-recovery.md
    ├── etcd-restore-runbook.md
    └── kubernetes-disaster-recovery-runbook.md
```
