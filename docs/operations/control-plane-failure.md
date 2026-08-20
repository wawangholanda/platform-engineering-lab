# Control Plane Failure and Recovery

## Overview

This document provides a concise runbook for troubleshooting and
recovering a Kubernetes control-plane failure.

The cluster has three control-plane nodes with stacked etcd:

```text
CP01  192.168.1.20
CP02  192.168.1.23
CP03  192.168.1.24
```

The Kubernetes API is exposed through:

```text
192.168.1.30:6443
```

The primary recovery goal is to restore API availability while
preserving etcd quorum and cluster state.

## Symptoms

Typical symptoms include:

- `kubectl` cannot reach the API
- Port `6443` is unavailable
- kube-apiserver is restarting
- Helm cannot connect to Kubernetes
- Prometheus control-plane targets become unhealthy
- kubelet reports API connection failures

Example:

```text
dial tcp 192.168.1.20:6443: connect: connection refused
```

## Troubleshooting Flow

```text
API unavailable
      |
      v
Check API server
      |
      v
Check etcd
      |
      v
Check kubelet / static Pods
      |
      v
Check etcd quorum and peers
      |
      v
Recover affected component
      |
      v
Validate API / Kubernetes / Monitoring
```

## 1. Check API Server

On the affected control-plane node:

```bash
sudo ss -lntp | grep ':6443\b' || true
sudo ps -ef | grep '[k]ube-apiserver'
```

Check readiness:

```bash
curl -k --max-time 5 \
  https://127.0.0.1:6443/readyz
```

## 2. Check Kubelet

```bash
sudo systemctl status kubelet --no-pager -l
sudo journalctl -u kubelet \
  --since "10 minutes ago" \
  --no-pager
```

Check static Pod manifests:

```bash
sudo ls -lah /etc/kubernetes/manifests/
```

Expected:

```text
etcd.yaml
kube-apiserver.yaml
kube-controller-manager.yaml
kube-scheduler.yaml
```

## 3. Check etcd

Check ports:

```bash
sudo ss -lntp | grep -E ':(2379|2380|2381)\b'
```

Check health:

```bash
curl -sS --max-time 5 \
  http://127.0.0.1:2381/health
```

Expected:

```json
{"health":"true","reason":""}
```

Check peer connectivity:

```bash
for ip in 192.168.1.20 192.168.1.23 192.168.1.24; do
  echo "===== $ip:2380 ====="
  timeout 3 bash -c "</dev/tcp/$ip/2380" \
    && echo "TCP OK" \
    || echo "TCP FAILED"
done
```

## 4. Recovery Rules

Before making destructive changes:

- Verify etcd health.
- Verify member connectivity.
- Verify quorum.
- Change one control-plane node at a time.
- Preserve `/var/lib/etcd`.
- Fix configuration errors before recreating components.

Do not immediately run:

```text
kubeadm reset
rm -rf /var/lib/etcd
etcd member remove
etcd member add
```

without first determining the etcd cluster state.

## 5. Validate Recovery

Check etcd:

```bash
curl -sS --max-time 5 \
  http://127.0.0.1:2381/health
```

Check API:

```bash
curl -k --max-time 5 \
  https://127.0.0.1:6443/readyz
```

Check Kubernetes:

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

Expected:

```text
All nodes Ready
Core control-plane components healthy
```

## 6. Validate Monitoring

Prometheus readiness:

```bash
curl -s http://localhost:9091/-/ready
```

Unhealthy targets:

```bash
curl -s http://localhost:9091/api/v1/targets |
  jq '[.data.activeTargets[] | select(.health != "up")] | length'
```

Expected:

```text
0
```

Control-plane metrics:

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

## Recovery Checklist

| Check | Expected |
|---|---|
| etcd | Healthy |
| etcd peers | Reachable |
| API `6443` | Listening |
| API `/readyz` | `ok` |
| Nodes | Ready |
| System Pods | Healthy |
| Prometheus | Ready |
| Unhealthy targets | 0 |

## Lessons Learned

- Check etcd before troubleshooting kube-apiserver.
- Static Pod manifest errors can cause control-plane outages.
- Control-plane changes should be serial.
- Backup files should remain outside `/etc/kubernetes/manifests/`.
- Recovery should preserve etcd quorum.
- Manual emergency fixes should be returned to Ansible and Git.

## Related Documentation

```text
docs/
├── architecture/
│   └── kubernetes-ha.md
├── kubernetes/
│   └── cluster-bootstrap.md
├── ansible/
│   └── architecture.md
├── observability/
│   └── prometheus.md
└── operations/
    ├── control-plane-failure.md
    ├── startup-shutdown.md
    └── validation.md
```
