# Platform Validation

## Overview

This document provides the post-deployment validation checklist for the
Platform Engineering Lab.

Validation covers infrastructure, configuration management, Kubernetes,
networking, storage, GitOps, and observability.

## Validation Flow

```text
Terraform
   |
   v
Ansible
   |
   v
Kubernetes
   |
   +-- Cilium
   +-- DNS / Services
   +-- Storage
   +-- Argo CD
   +-- Prometheus
```

## 1. Terraform

Validate configuration:

```bash
terraform fmt -check -recursive
terraform validate
terraform plan
```

Expected:

- Formatting is valid.
- Configuration is valid.
- Terraform plan matches the intended infrastructure changes.

## 2. Ansible

Run syntax validation:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --syntax-check
```

Use check mode where applicable:

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/<playbook>.yml \
  --check
```

Expected:

```text
failed=0
```

Repeated execution should produce no unexpected changes.

## 3. Kubernetes

Check nodes:

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

Check system workloads:

```bash
kubectl get pods -A
```

## 4. Kubernetes API

Validate the HA API endpoint:

```bash
curl -k --max-time 5 \
  https://192.168.1.30:6443/readyz
```

Expected:

```text
ok
```

## 5. Networking

Check Cilium:

```bash
kubectl -n kube-system get pods \
  -l k8s-app=cilium -o wide
```

Validate DNS:

```bash
kubectl run dns-test \
  --image=busybox:1.36 \
  --restart=Never \
  --rm -it \
  -- nslookup kubernetes.default.svc.cluster.local
```

Validate service connectivity where required.

## 6. Storage

Check storage resources:

```bash
kubectl get storageclass
kubectl get pv
kubectl get pvc -A
```

Expected PVC state:

```text
Bound
```

Persistent storage should also be tested after Pod recreation or
rescheduling.

## 7. GitOps

Check Argo CD applications:

```bash
kubectl get applications -n argocd
```

Validate an application:

```bash
kubectl get application dev-monitoring -n argocd \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'
```

Expected:

```text
Synced Healthy
```

## 8. Observability

Check Prometheus readiness:

```bash
curl -s http://localhost:9091/-/ready
```

Check unhealthy targets:

```bash
curl -s http://localhost:9091/api/v1/targets |
  jq '[.data.activeTargets[] | select(.health != "up")] | length'
```

Expected:

```text
0
```

Validate control-plane metrics:

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

All expected targets should report:

```text
1
```

## 9. High Availability

Validate:

- Both load balancers are available.
- VIP `192.168.1.30` is reachable.
- All three control-plane nodes are healthy.
- etcd maintains quorum.
- Worker failure does not remove the control plane.

Failure testing should be performed one failure domain at a time.

## Validation Summary

| Layer | Expected Result |
|---|---|
| Terraform | Valid |
| Ansible | Syntax OK / No unexpected changes |
| Kubernetes nodes | 5/5 Ready |
| API | Ready |
| Cilium | Healthy |
| Storage | PVC Bound |
| Argo CD | Synced Healthy |
| Prometheus | Ready |
| Prometheus targets | 0 unhealthy |
| Control-plane metrics | 3/3 UP |

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
├── gitops/
│   └── argocd.md
├── observability/
│   └── prometheus.md
└── operations/
    ├── control-plane-failure.md
    ├── startup-shutdown.md
    └── validation.md
```
