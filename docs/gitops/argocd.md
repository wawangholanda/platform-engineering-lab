# Argo CD and GitOps

## Overview

Argo CD is used as the GitOps controller for the Kubernetes platform.

Git is the source of truth for Kubernetes application and platform
configuration, while Argo CD continuously reconciles the desired state
with the live Kubernetes cluster.

## Architecture

```text
Git Repository
      |
      v
   Argo CD
      |
      v
Kubernetes Cluster
      |
      +-------------------+
      |                   |
      v                   v
   Applications      Platform Services
      |                   |
      v                   v
   dev-nginx         dev-monitoring
                          |
                          v
                  kube-prometheus-stack
```

## Repository Structure

GitOps-managed resources are stored under:

```text
environments/dev/kubernetes/

├── apps/
│   └── nginx/
│       ├── deployment.yaml
│       ├── namespace.yaml
│       └── service.yaml
│
└── monitoring/
    └── kube-prometheus-stack/
        └── values.yaml
```

## Applications

### dev-nginx

The NGINX application is deployed from Git manifests into:

```text
namespace: demo
```

### dev-monitoring

The monitoring stack uses:

```text
kube-prometheus-stack
```

The Helm values are stored in:

```text
environments/dev/kubernetes/monitoring/kube-prometheus-stack/values.yaml
```

## GitOps Workflow

```text
Local Change
     |
     v
Git Commit
     |
     v
Git Push
     |
     v
Argo CD
     |
     v
Kubernetes
     |
     v
Validation
```

The intended workflow is to make persistent configuration changes in
Git rather than modifying Argo CD-managed resources manually.

## Argo CD Configuration

GitOps configuration is defined through:

```text
ansible/inventory/dev/group_vars/k8s.yml
```

The current repository is:

```text
https://github.com/wawangholanda/platform-engineering-lab.git
```

Target revision:

```text
main
```

## Installation

Argo CD is installed using Ansible.

Relevant roles:

```text
ansible/roles/argocd/
ansible/roles/argocd_bootstrap/
```

Bootstrap playbook:

```text
ansible/playbooks/argocd-bootstrap.yml --tags argocd_bootstrap
```

## Validation

Check Argo CD applications:

```bash
kubectl get applications -n argocd
```

Validate monitoring:

```bash
kubectl get application dev-monitoring -n argocd \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'
```

Expected:

```text
Synced Healthy
```

Validate NGINX:

```bash
kubectl get application dev-nginx -n argocd \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'
```

Expected:

```text
Synced Healthy
```

Inspect managed resources:

```bash
kubectl get application dev-monitoring -n argocd \
  -o jsonpath='{range .status.resources[*]}{.kind}{" | "}{.name}{" | "}{.status}{" | "}{.health.status}{"\n"}{end}'
```

## Configuration Drift

Argo CD reports `OutOfSync` when the live Kubernetes state differs from
the desired state stored in Git.

The preferred workflow is:

```text
OutOfSync
   |
   v
Identify Difference
   |
   +------------------+
   |                  |
   v                  v
Intended Change   Unintended Change
   |                  |
   v                  v
Update Git         Reconcile
   |                  |
   +---------+--------+
             |
             v
        Synced Healthy
```

Manual changes may be used during incident response, but persistent
changes should be returned to Git.

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

Monitoring validation is documented separately in:

```text
docs/observability/prometheus.md
```

## Troubleshooting

### Application is OutOfSync

```bash
kubectl get application <APPLICATION> -n argocd -o yaml
```

Check the managed resources:

```bash
kubectl get application <APPLICATION> -n argocd \
  -o jsonpath='{range .status.resources[*]}{.kind}{" | "}{.name}{" | "}{.status}{" | "}{.health.status}{"\n"}{end}'
```

### Application is Degraded

Check Kubernetes resources:

```bash
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp
```

Inspect the affected resource:

```bash
kubectl describe <RESOURCE> <NAME> -n <NAMESPACE>
```

### Git Changes Are Not Reflected

Verify:

```bash
git status
git log -1
```

Then confirm the Argo CD application is tracking the expected repository
and revision.

## Operational Principles

- Git is the source of truth.
- Argo CD is responsible for reconciliation.
- Persistent changes should be committed to Git.
- Manual changes should be minimized.
- Configuration drift should be investigated.
- GitOps-managed resources should remain reproducible.

## Future Improvements

- [ ] Automated sync policies
- [ ] Pull request based deployment workflow
- [ ] Environment promotion
- [ ] Progressive delivery
- [ ] Secret management integration
- [ ] Multi-environment GitOps structure

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
├── observability/
│   └── prometheus.md
└── operations/
    ├── validation.md
    └── control-plane-failure.md
```
