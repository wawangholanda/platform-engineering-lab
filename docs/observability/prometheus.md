# Prometheus

## Overview

Prometheus is deployed through `kube-prometheus-stack` and managed by
Argo CD.

Configuration:

```text
environments/dev/kubernetes/monitoring/kube-prometheus-stack/values.yaml
```

The stack runs in the `monitoring` namespace.

## Components

- Prometheus — metrics collection and querying
- Grafana — visualization and dashboards
- Alertmanager — alert management
- kube-state-metrics — Kubernetes object metrics
- node-exporter — node metrics

Monitoring covers:

- Kubernetes API server
- etcd
- kube-controller-manager
- kube-scheduler
- kubelet
- CoreDNS
- node-exporter
- kube-state-metrics

## Control Plane Metrics Validation

Control-plane metrics are collected from:

- kube-apiserver
- kube-controller-manager
- kube-scheduler
- etcd

Configuration is automated using:

```text
ansible/roles/k8s_control_plane_metrics/
```

The dedicated playbook is:

```text
ansible/playbooks/control-plane-metrics.yml
```

Control-plane changes are executed serially to reduce the risk of
simultaneously disrupting multiple control-plane nodes.

```yaml
serial: 1
```

## kube-proxy Validation

kube-proxy scraping is intentionally disabled because its metrics
endpoint is bound to localhost:

```text
127.0.0.1:10249
```

The monitoring configuration therefore uses:

```yaml
kubeProxy:
  enabled: false
```

This is managed through GitOps in:

```text
environments/dev/kubernetes/monitoring/kube-prometheus-stack/values.yaml
```

## GitOps

The monitoring stack is managed by the Argo CD application:

```text
dev-monitoring
```

Changes to monitoring configuration should be committed to Git and
reconciled by Argo CD.

Validate:

```bash
kubectl get application dev-monitoring -n argocd \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'
```

Expected:

```text
Synced Healthy
```

## Validation

Prometheus is validated through readiness checks, target health, and
PromQL queries.

### Prometheus Readiness

```bash
curl -s http://localhost:9091/-/ready
```

Expected:

```text
Prometheus Server is Ready.
```

### Target Health

```bash
curl -s http://localhost:9091/api/v1/targets |
  jq '[.data.activeTargets[] | select(.health != "up")] | length'
```

Expected:

```text
0
```

A result of `0` means no active scrape target is unhealthy.

### Control Plane Metrics

```bash
curl -sG http://localhost:9091/api/v1/query \
  --data-urlencode \
  'query=up{job=~"kube-etcd|kube-controller-manager|kube-scheduler"}' |
  jq '.data.result[] | {
    job: .metric.job,
    instance: .metric.instance,
    value: .value[1]
  }'
```

Expected:

```text
kube-etcd                 192.168.1.20:2381   1
kube-etcd                 192.168.1.23:2381   1
kube-etcd                 192.168.1.24:2381   1

kube-controller-manager   192.168.1.20:10257  1
kube-controller-manager   192.168.1.23:10257  1
kube-controller-manager   192.168.1.24:10257  1

kube-scheduler            192.168.1.20:10259  1
kube-scheduler            192.168.1.23:10259  1
kube-scheduler            192.168.1.24:10259  1
```

A value of `1` indicates a healthy Prometheus scrape.

### kube-proxy

Verify that no kube-proxy target is active:

```bash
curl -s http://localhost:9091/api/v1/targets |
  jq '.data.activeTargets[] |
      select(.labels.job == "kube-proxy")'
```

Expected:

```text
No output
```

### Kubernetes Nodes

```bash
kubectl get nodes -o wide
```

Expected:

```text
k8s-cp01       Ready
k8s-cp02       Ready
k8s-cp03       Ready
k8s-worker01   Ready
k8s-worker02   Ready
```

### Monitoring Workloads

```bash
kubectl get pods -n monitoring -o wide
```

Prometheus, Grafana, Alertmanager, and supporting monitoring components
should be healthy.

## Validation Summary

| Validation | Expected Result |
|---|---|
| Prometheus readiness | Ready |
| Unhealthy active targets | 0 |
| etcd metrics | 3/3 UP |
| kube-controller-manager metrics | 3/3 UP |
| kube-scheduler metrics | 3/3 UP |
| kube-proxy active targets | None |
| Kubernetes nodes | 5/5 Ready |
| Argo CD application | Synced Healthy |

## Operational Notes

For local validation, Prometheus is accessed through port forwarding:

```bash
kubectl -n monitoring port-forward \
  svc/dev-monitoring-kube-promet-prometheus 9091:9090
```

Prometheus is then available at:

```text
http://localhost:9091
```

Port forwarding is intended for local administration and validation,
not as the permanent production access method.

## Lessons Learned

### Static Pod Safety

Control-plane components run as static Pods. Changes to their manifests
must be made carefully because invalid configuration can immediately
restart critical components.

Do not store backup manifests inside:

```text
/etc/kubernetes/manifests/
```

Store backups outside the kubelet static Pod directory.

### Serial Changes

Control-plane configuration changes should be applied one node at a
time.

```yaml
serial: 1
```

### Validate etcd First

When kube-apiserver is unavailable, validate etcd first:

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
kubectl / Helm / platform services
```

An etcd failure can therefore appear as an API server or Helm
connectivity problem.

### Avoid Destructive Recovery

Do not immediately remove etcd members, run `kubeadm reset`, or delete
the etcd data directory.

Verify cluster membership and quorum before destructive recovery.

### Validate Automation

Cluster-affecting automation should be validated using:

- Ansible syntax checks
- Ansible check mode
- Idempotency testing
- Targeted playbooks

### GitOps as Source of Truth

Persistent monitoring configuration should be stored in Git and
reconciled by Argo CD.

Emergency manual changes should be reflected back into automation and
Git afterward.

## Related Documentation

```text
docs/
├── architecture/
├── ansible/
├── kubernetes/
├── gitops/
├── observability/
├── proxmox/
├── terraform/
└── operations/
```
