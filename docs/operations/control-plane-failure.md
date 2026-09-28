# Control Plane Failure and Recovery

## Overview

This document provides an operational runbook for troubleshooting a
Kubernetes control-plane failure.

The cluster has three control-plane nodes with stacked etcd:

```text
CP01  192.168.1.20
CP02  192.168.1.23
CP03  192.168.1.24
```

The Kubernetes API is exposed through the HA endpoint:

```text
192.168.1.30:6443
```

The primary troubleshooting goal is to determine whether the failure is
caused by:

* Kubernetes API server
* kubelet
* Static Pod configuration
* etcd
* etcd peer connectivity
* Loss of etcd quorum
* Control-plane node failure
* Load-balancer or API endpoint failure

This document focuses on diagnosis and immediate validation.

For node replacement, use:

```text
docs/disaster-recovery/control-plane-node-recovery.md
```

For etcd state restoration, use:

```text
docs/disaster-recovery/etcd-restore-runbook.md
```

## Symptoms

Typical symptoms include:

* `kubectl` cannot reach the Kubernetes API.
* Port `6443` is unavailable on an affected control-plane node.
* kube-apiserver is restarting.
* Helm cannot connect to Kubernetes.
* Prometheus control-plane targets become unhealthy.
* kubelet reports API connection failures.
* Kubernetes API readiness checks fail.

Example:

```text
dial tcp 192.168.1.20:6443: connect: connection refused
```

An API failure does not automatically mean that etcd is unavailable.
The control-plane components should therefore be checked individually.

## Troubleshooting Flow

```text
API unavailable
      |
      v
Check HA API endpoint
      |
      v
Check affected control-plane node
      |
      +-- kubelet
      |
      +-- static Pods
      |
      +-- kube-apiserver
      |
      +-- etcd
      |
      v
Check etcd quorum and peer connectivity
      |
      v
Determine failure scope
      |
      +-- Configuration/component issue
      |
      +-- Single control-plane node failure
      |
      +-- etcd quorum failure
      |
      v
Apply the appropriate recovery procedure
      |
      v
Validate API / Kubernetes / Cilium / Monitoring
```

## Check the HA API Endpoint

Start by checking the shared Kubernetes API endpoint:

```bash
kubectl get nodes -o wide
```

If `kubectl` cannot connect, check the API endpoint directly:

```bash
curl -k --max-time 5 \
  https://192.168.1.30:6443/readyz
```

Check API port connectivity:

```bash
timeout 5 bash -c '</dev/tcp/192.168.1.30/6443' \
  && echo "API TCP OK" \
  || echo "API TCP FAILED"
```

The API endpoint is provided by:

```text
192.168.1.30:6443
        |
        v
HAProxy + Keepalived
        |
        +-- CP01 192.168.1.20
        +-- CP02 192.168.1.23
        +-- CP03 192.168.1.24
```

If the shared endpoint is unavailable, determine whether the problem is
with the load-balancer layer or with the Kubernetes control plane.

## Check the Affected Control Plane

Run these checks directly on the affected control-plane node.

Check whether the API server is listening:

```bash
sudo ss -lntp | grep ':6443\b' || true
```

Check the kube-apiserver process:

```bash
sudo ps -ef | grep '[k]ube-apiserver'
```

Check API readiness locally:

```bash
curl -k --max-time 5 \
  https://127.0.0.1:6443/readyz
```

A failure of the local API endpoint while other control-plane nodes remain
healthy may indicate a node-local control-plane problem rather than a
cluster-wide API failure.

## Check Kubelet

Control-plane components are deployed as static Pods and are managed by the
kubelet.

Check kubelet:

```bash
sudo systemctl status kubelet --no-pager -l
```

Inspect recent kubelet logs:

```bash
sudo journalctl -u kubelet \
  --since "10 minutes ago" \
  --no-pager
```

Check static Pod manifests:

```bash
sudo ls -lah /etc/kubernetes/manifests/
```

Expected control-plane manifests include:

```text
etcd.yaml
kube-apiserver.yaml
kube-controller-manager.yaml
kube-scheduler.yaml
```

Inspect the relevant manifest if a static Pod is repeatedly restarting:

```bash
sudo sed -n '1,240p' /etc/kubernetes/manifests/kube-apiserver.yaml
```

Do not modify control-plane manifests destructively during initial
troubleshooting.

## Check Static Pod Status

From a healthy Kubernetes API endpoint, inspect control-plane Pods:

```bash
kubectl get pods -n kube-system -o wide
```

Focus on:

```text
etcd-*
kube-apiserver-*
kube-controller-manager-*
kube-scheduler-*
```

Inspect a failing Pod:

```bash
kubectl describe pod <pod-name> -n kube-system
```

Inspect recent logs:

```bash
kubectl logs <pod-name> -n kube-system --previous
```

If the API is unavailable, use kubelet and container runtime logs on the
affected node instead.

## Check Container Runtime

The cluster uses containerd.

Check the runtime:

```bash
sudo systemctl status containerd --no-pager -l
```

Check recent containerd logs:

```bash
sudo journalctl -u containerd \
  --since "10 minutes ago" \
  --no-pager
```

A container-runtime failure can prevent static Pods from starting even when
the Kubernetes manifests themselves are correct.

## Check etcd

Check etcd ports:

```bash
sudo ss -lntp | grep -E ':(2379|2380|2381)\b'
```

The local etcd metrics/health endpoint is exposed on:

```text
127.0.0.1:2381
```

Check the local health endpoint:

```bash
curl -sS --max-time 5 \
  http://127.0.0.1:2381/health
```

A healthy endpoint should return a response indicating that etcd is
healthy.

If available, inspect the etcd container or static Pod logs:

```bash
kubectl logs -n kube-system \
  $(kubectl get pods -n kube-system \
    -l component=etcd \
    -o jsonpath='{.items[0].metadata.name}') \
  --tail=100
```

If the Kubernetes API is unavailable, inspect the container runtime and
system logs directly on the control-plane node.

## Check etcd Peer Connectivity

The three etcd members are:

```text
CP01  192.168.1.20
CP02  192.168.1.23
CP03  192.168.1.24
```

Check peer connectivity on port `2380`:

```bash
for ip in 192.168.1.20 192.168.1.23 192.168.1.24; do
  echo "===== $ip:2380 ====="
  timeout 3 bash -c "</dev/tcp/$ip/2380" \
    && echo "TCP OK" \
    || echo "TCP FAILED"
done
```

Peer connectivity problems can prevent etcd members from maintaining
quorum.

## Check etcd Membership and Quorum

If the cluster API is available, inspect the etcd member list using the
project's configured etcd client credentials.

The conceptual checks are:

```text
etcd endpoint health
etcd endpoint status
etcd member list
```

The expected topology is three etcd members:

```text
CP01
CP02
CP03
```

A three-member etcd cluster requires two healthy members to maintain
quorum.

Therefore:

```text
3 members -> quorum = 2
2 healthy  -> quorum maintained
1 healthy  -> quorum lost
```

Do not remove or re-add an etcd member merely because one node is
unhealthy.

First determine whether the member can be recovered or replaced through
the documented control-plane recovery procedure.

## Determine the Failure Scope

After collecting the initial evidence, classify the failure.

### Node-Local Control Plane Problem

Typical indicators:

* Other control-plane nodes remain healthy.
* Other API backends remain reachable.
* Local kube-apiserver is unhealthy.
* kubelet, containerd, or static Pod configuration has a problem.
* etcd quorum remains healthy.

Continue with node-local troubleshooting and configuration recovery.

### Single Control Plane Node Failure

Typical indicators:

* One control-plane node is unreachable or permanently failed.
* The other control-plane nodes remain healthy.
* etcd quorum remains available.

Use:

```text
docs/disaster-recovery/control-plane-node-recovery.md
```

Do not use an etcd restore simply to replace a single failed control-plane
node when the remaining etcd cluster is healthy.

### etcd Quorum Failure

Typical indicators:

* Multiple etcd members are unavailable.
* etcd quorum cannot be recovered normally.
* Kubernetes API state cannot be served correctly.
* Existing control-plane state requires restoration from a known-good
  snapshot.

Use:

```text
docs/disaster-recovery/etcd-restore-runbook.md
```

An etcd restore is a control-plane state recovery operation and should not
be treated as a normal node-replacement procedure.

## Recovery Rules

Before making destructive changes:

* Verify the current API state.
* Verify the health of the remaining control-plane nodes.
* Verify etcd member health.
* Verify etcd quorum.
* Check recent kubelet and containerd logs.
* Inspect static Pod manifests.
* Preserve `/var/lib/etcd`.
* Preserve relevant `/etc/kubernetes/` configuration.
* Change one control-plane node at a time where possible.
* Record the observed failure before making destructive changes.

Do not immediately run:

```text
kubeadm reset
rm -rf /var/lib/etcd
etcd member remove
etcd member add
```

without first determining the current etcd cluster state and recovery
scope.

Deleting etcd data can turn a recoverable node failure into a broader
control-plane recovery operation.

## Validate Recovery

After recovery, validate the control-plane components.

Check etcd locally:

```bash
curl -sS --max-time 5 \
  http://127.0.0.1:2381/health
```

Check the local API:

```bash
curl -k --max-time 5 \
  https://127.0.0.1:6443/readyz
```

Check Kubernetes:

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

Expected state:

```text
All expected nodes Ready
Control-plane Pods Running
CoreDNS healthy
Cilium healthy
```

A single node may require additional validation while it rejoins the
cluster.

## Validate API Availability

Validate the shared HA endpoint:

```bash
curl -k --max-time 5 \
  https://192.168.1.30:6443/readyz
```

Also check:

```bash
kubectl get --raw='/readyz?verbose'
```

The API should be reachable through the HA endpoint rather than relying
only on a single control-plane node address.

## Validate Cilium

Check Cilium Pods:

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
```

Check Cilium status when available:

```bash
cilium status
```

Verify that the networking layer has returned to a healthy state before
considering the control-plane recovery complete.

Detailed networking configuration is documented in:

```text
docs/kubernetes/networking-cilium.md
```

## Validate Monitoring

Prometheus readiness:

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

Inspect control-plane metrics:

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

Expected control-plane monitoring targets should report:

```text
1
```

for healthy targets.

Monitoring should be treated as supporting evidence. A healthy Prometheus
target does not by itself prove that the entire Kubernetes control plane
is healthy.

## Validate GitOps

Check Argo CD applications:

```bash
kubectl get applications -n argocd
```

The expected platform applications include:

```text
dev-nginx
dev-monitoring
dev-gateway
```

Check application health and synchronization:

```bash
kubectl get applications -n argocd \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
```

Expected applications should return to their intended GitOps state.

If resources are missing after recovery, verify GitOps state before
manually recreating them.

## Recovery Checklist

| Check                               | Expected            |
| ----------------------------------- | ------------------- |
| HA API endpoint `192.168.1.30:6443` | Reachable           |
| API `/readyz`                       | Healthy             |
| etcd members                        | Expected membership |
| etcd quorum                         | Maintained          |
| etcd peers                          | Reachable           |
| Control-plane nodes                 | Ready               |
| Static control-plane Pods           | Healthy             |
| Container runtime                   | Running             |
| Cilium                              | Healthy             |
| Prometheus                          | Ready               |
| Prometheus unhealthy targets        | 0                   |
| Argo CD applications                | Synced / Healthy    |

## Lessons Learned

* Check the HA API endpoint before assuming that a control-plane node has
  failed.
* Check etcd before making changes to kube-apiserver or control-plane
  membership.
* Static Pod manifest errors can cause control-plane outages.
* Containerd and kubelet are critical dependencies for static Pods.
* Control-plane changes should be serial where possible.
* Backup files should remain outside `/etc/kubernetes/manifests/`.
* Preserve `/var/lib/etcd` until the failure scope is understood.
* Do not perform destructive etcd operations without first checking
  membership and quorum.
* Manual emergency fixes should eventually be represented in Ansible and
  Git.
* Node replacement, etcd restoration, and full platform reconstruction are
  separate recovery scenarios.

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
│   ├── control-plane-failure.md
│   ├── disaster-recovery.md
│   ├── etcd-backup-and-restore.md
│   ├── startup-shutdown.md
│   └── validation.md
└── disaster-recovery/
    ├── control-plane-node-recovery.md
    ├── worker-node-recovery.md
    ├── etcd-restore-runbook.md
    └── kubernetes-disaster-recovery-runbook.md
```
