# Platform Validation

## Overview

This document provides the post-deployment validation checklist for the
Platform Engineering Lab.

Validation covers:

* Infrastructure
* Configuration management
* Kubernetes
* High availability
* Cilium networking
* Gateway API
* Storage
* GitOps
* Observability
* External application access

The validation process verifies that the platform is operational after
deployment, configuration changes, recovery, or infrastructure startup.

## Validation Flow

```text id="vflow01"
Terraform
    |
    v
Proxmox Infrastructure
    |
    v
Ansible
    |
    v
Kubernetes
    |
    +-- Control Plane
    +-- Workers
    +-- Cilium
    +-- Gateway API
    +-- Storage
    +-- Argo CD
    +-- Monitoring
    |
    v
External Access
    |
    +-- Nginx Proxy Manager
    +-- Argo CD
    +-- Grafana
```

## 1. Terraform

Validate Terraform configuration:

```bash id="terraform01"
terraform fmt -check -recursive
terraform validate
terraform plan
```

Expected:

* Formatting is valid.
* Configuration is valid.
* The Terraform plan matches the intended infrastructure changes.

Terraform validation confirms the infrastructure definition before
configuration management and Kubernetes validation.

## 2. Ansible

Ansible uses `site.yml` as the primary automation entry point.

Syntax validation:

```bash id="ansible01"
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --syntax-check
```

Complete automation:

```bash id="ansible02"
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml
```

Check mode:

```bash id="ansible03"
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --check
```

Available tags:

```bash id="ansible04"
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --list-tags
```

For targeted control-plane metrics configuration:

```bash id="ansible05"
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/site.yml \
  --tags k8s_control_plane_metrics
```

Expected automation result:

```text id="ansible06"
failed=0
```

Repeated execution should produce no unexpected changes.

## 3. Kubernetes Cluster

Check all nodes:

```bash id="k8s01"
kubectl get nodes -o wide
```

Expected nodes:

```text id="k8s02"
k8s-cp01
k8s-cp02
k8s-cp03
k8s-worker01
k8s-worker02
```

All nodes should report:

```text
Ready
```

Check system workloads:

```bash id="k8s03"
kubectl get pods -A
```

Core Kubernetes, networking, storage, GitOps, and monitoring components
should be operational.

## 4. Kubernetes API High Availability

The Kubernetes API is exposed through the HA endpoint:

```text id="api01"
192.168.1.30:6443
```

Validate API readiness:

```bash id="api02"
curl -k --max-time 5 \
  https://192.168.1.30:6443/readyz
```

Expected:

```text id="api03"
ok
```

The API endpoint is backed by:

```text id="api04"
LB01  192.168.1.25
LB02  192.168.1.26
```

and the three control-plane nodes:

```text id="api05"
CP01  192.168.1.20
CP02  192.168.1.23
CP03  192.168.1.24
```

## 5. Cilium Networking

Check Cilium Pods:

```bash id="cilium01"
kubectl -n kube-system get pods \
  -l k8s-app=cilium -o wide
```

Cilium should be running across the Kubernetes nodes.

Check the GatewayClass:

```bash id="cilium02"
kubectl get gatewayclass
```

The Cilium GatewayClass should report:

```text
Accepted: True
```

Check the Gateway:

```bash id="cilium03"
kubectl get gateway -n default
```

The Gateway should report a ready status and the expected address:

```text
192.168.1.240
```

Check HTTPRoutes:

```bash id="cilium04"
kubectl get httproute -n default
```

The application routes include:

```text
nginx-route
argocd-route
grafana-route
```

Check ReferenceGrants:

```bash id="cilium05"
kubectl get referencegrant -A
```

The Argo CD and Grafana cross-namespace backend references should have
corresponding ReferenceGrant resources.

## 6. DNS and Service Connectivity

Cluster DNS can be validated using a temporary test Pod:

```bash id="dns01"
kubectl run dns-test \
  --image=busybox:1.36 \
  --restart=Never \
  --rm -it \
  -- nslookup kubernetes.default.svc.cluster.local
```

Expected DNS resolution should return the Kubernetes cluster DNS service.

Service connectivity should also be validated for workloads where
application-level connectivity is important.

## 7. Gateway Application Routing

The Cilium Gateway provides the internal application routing layer.

The current routing architecture is:

```text id="gateway01"
HTTP Host
    |
    v
Cilium Gateway
192.168.1.240
    |
    +-- nginx-route
    +-- argocd-route
    +-- grafana-route
```

Direct Gateway routing can be tested using the appropriate HTTP Host header.

Argo CD:

```bash id="gateway02"
curl -v \
  -H 'Host: argocd.wawangholanda.biz.id' \
  http://192.168.1.240/
```

Grafana:

```bash id="gateway03"
curl -v \
  -H 'Host: grafana.wawangholanda.biz.id' \
  http://192.168.1.240/
```

A successful response validates the path:

```text
Client
  |
  v
Cilium Gateway
  |
  v
HTTPRoute
  |
  v
Application Service
```

## 8. External Application Access

External access uses Nginx Proxy Manager:

```text id="external01"
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
  +-- Argo CD
  +-- Grafana
```

Validate the public applications:

```text id="external02"
https://argocd.wawangholanda.biz.id
https://grafana.wawangholanda.biz.id
```

The expected result is:

* TLS is successfully terminated at Nginx Proxy Manager.
* The request reaches the Cilium Gateway.
* The appropriate HTTPRoute is selected.
* The request reaches the intended Kubernetes Service.
* The application returns a valid response.

## 9. Storage

Check the StorageClass:

```bash id="storage01"
kubectl get storageclass
```

Check PersistentVolumes:

```bash id="storage02"
kubectl get pv
```

Check PersistentVolumeClaims:

```bash id="storage03"
kubectl get pvc -A
```

Expected application PVCs should report:

```text
Bound
```

Persistent storage should remain available after Pod recreation or
rescheduling.

## 10. GitOps

Check Argo CD applications:

```bash id="gitops01"
kubectl get applications -n argocd
```

The current platform includes:

```text
dev-nginx
dev-monitoring
dev-gateway
```

Check monitoring synchronization:

```bash id="gitops02"
kubectl get application dev-monitoring -n argocd \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'
```

Expected:

```text
Synced Healthy
```

Check Gateway synchronization:

```bash id="gitops03"
kubectl get application dev-gateway -n argocd \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{"\n"}'
```

Expected:

```text
Synced Healthy
```

GitOps validation confirms that the Kubernetes state matches the desired
state stored in Git.

## 11. Observability

Prometheus readiness:

```bash id="prom01"
curl -s http://localhost:9091/-/ready
```

Expected:

```text
Prometheus Server is Ready.
```

Check unhealthy active targets:

```bash id="prom02"
curl -s http://localhost:9091/api/v1/targets |
  jq '[.data.activeTargets[] | select(.health != "up")] | length'
```

Expected:

```text
0
```

Validate control-plane metrics:

```bash id="prom03"
curl -sG http://localhost:9091/api/v1/query \
  --data-urlencode \
  'query=up{job=~"kube-etcd|kube-controller-manager|kube-scheduler"}' |
  jq '.data.result[] | {
    job: .metric.job,
    instance: .metric.instance,
    value: .value[1]
  }'
```

The expected control-plane targets are:

```text
kube-etcd
kube-controller-manager
kube-scheduler
```

Each expected target should report:

```text
1
```

Because Cilium kube-proxy replacement is enabled, kube-proxy is not expected
to appear as an active monitoring target.

## 12. Monitoring Workloads

Check monitoring workloads:

```bash id="monitoring01"
kubectl get pods -n monitoring -o wide
```

The monitoring namespace should contain healthy instances of:

* Prometheus
* Grafana
* Alertmanager
* kube-state-metrics
* node-exporter
* Prometheus Operator components

Grafana external access should resolve through:

```text
grafana.wawangholanda.biz.id
```

## 13. High Availability

The HA architecture should be evaluated across its independent failure
domains.

### Load Balancer Layer

```text
LB01
LB02
```

Both nodes provide redundancy for the Kubernetes API VIP:

```text
192.168.1.30
```

### Control Plane Layer

```text
CP01
CP02
CP03
```

The three control-plane nodes provide etcd quorum and Kubernetes
control-plane redundancy.

### Worker Layer

```text
Worker01
Worker02
```

Worker failure affects workload capacity but should not remove the
Kubernetes control plane.

### Failure Testing

Failure testing is performed separately from routine post-deployment
validation.

The relevant failure scenarios include:

* LB01 failure
* LB02 failure
* Single control-plane failure
* Control-plane recovery
* Worker failure
* API availability during failure

Failure testing should be performed one failure domain at a time.

## Validation Summary

| Layer                   | Expected Result                   |
| ----------------------- | --------------------------------- |
| Terraform               | Valid                             |
| Ansible                 | Syntax OK / No unexpected changes |
| Kubernetes nodes        | 5/5 Ready                         |
| Kubernetes API          | Ready                             |
| Cilium                  | Healthy                           |
| GatewayClass            | Accepted                          |
| Gateway                 | Ready                             |
| Gateway address         | `192.168.1.240`                   |
| HTTPRoutes              | Accepted / Resolved               |
| ReferenceGrants         | Present                           |
| Storage                 | PVC Bound                         |
| Argo CD                 | Synced Healthy                    |
| Prometheus              | Ready                             |
| Prometheus targets      | 0 unhealthy                       |
| Control-plane metrics   | Expected targets UP               |
| kube-proxy metrics      | No active target                  |
| Grafana external access | Available                         |
| Argo CD external access | Available                         |

## Validation Scope

This document is intended for platform-level validation after:

* Terraform infrastructure changes
* Ansible configuration changes
* Kubernetes cluster deployment
* Control-plane recovery
* Worker recovery
* Cilium configuration changes
* Gateway API changes
* Storage changes
* GitOps changes
* Monitoring changes
* Proxmox startup and shutdown cycles

Detailed failure recovery procedures are documented separately.

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
