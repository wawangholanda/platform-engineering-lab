# Alertmanager Telegram Notifications

This document describes the Telegram notification integration for Alertmanager in the Platform Engineering Lab.

The integration provides a secure GitOps-based workflow for sending critical Kubernetes alerts
to Telegram while keeping the Telegram bot token out of the Git repository.

## Overview

The monitoring stack uses:

* Prometheus for metrics collection and alert evaluation
* Alertmanager for alert routing and notification delivery
* `AlertmanagerConfig` for notification configuration
* Sealed Secrets for protecting the Telegram bot token
* Argo CD for GitOps deployment
* Telegram as the external notification channel

The current implementation routes critical alerts to Telegram.

## Architecture

```text
                         Kubernetes
                              |
                              v
                       kube-state-metrics
                              |
                              v
                         Prometheus
                              |
                       PrometheusRule
                              |
                 KubernetesNodeNotReady
                 severity = critical
                 namespace = monitoring
                              |
                              v
                        Alertmanager
                              |
                    AlertmanagerConfig
                              |
                              v
                       Telegram API
                              |
                              v
                       Telegram Chat
```

The Telegram bot token is stored in Kubernetes through a Sealed Secret:

```text
Telegram Bot Token
        |
        v
kubectl create secret
        |
        v
     kubeseal
        |
        v
SealedSecret
        |
        v
       Git
        |
        v
     Argo CD
        |
        v
Sealed Secrets Controller
        |
        v
Kubernetes Secret
        |
        v
   Alertmanager
```

## Components

### Prometheus

The monitoring stack is deployed using the `kube-prometheus-stack` Helm chart.

The current tested chart version is:

```text
kube-prometheus-stack: 88.5.0
```

The custom `KubernetesNodeNotReady` alert is defined through `additionalPrometheusRulesMap`.

The alert fires when a Kubernetes node is no longer reporting the Ready condition for more than five minutes.

The alert includes:

```yaml
labels:
  severity: critical
  namespace: monitoring
```

The explicit `namespace` label is used by the namespace-scoped `AlertmanagerConfig` route.

### Alertmanager

Alertmanager is provided by the `kube-prometheus-stack` deployment.

The Telegram receiver is configured through an `AlertmanagerConfig` resource rather than embedding the Telegram token in the Alertmanager Helm values.

The configuration is located at:

```text
environments/dev/kubernetes/monitoring/alertmanager/telegram.yaml
```

The receiver uses:

* Telegram Bot API
* HTML message parsing
* resolved notifications
* critical alert routing
* grouped alerts

### Sealed Secrets

The Sealed Secrets controller is deployed through Argo CD.

The current tested versions are:

```text
Helm chart: 2.20.0
Controller: 0.40.0
kubeseal:   0.40.0
```

The controller is deployed as:

```text
dev-sealed-secrets
```

in:

```text
kube-system
```

The encrypted Telegram secret is stored in:

```text
environments/dev/kubernetes/monitoring/alertmanager-telegram-sealedsecret.yaml
```

Only the encrypted value is committed to Git.

## Telegram Secret

The Kubernetes Secret contains:

```text
bot-token
```

The plaintext Telegram bot token must never be committed to Git.

The SealedSecret contains encrypted data instead:

```yaml
spec:
  encryptedData:
    bot-token: <encrypted-value>
```

The Sealed Secrets controller decrypts the value inside the cluster and creates the corresponding Kubernetes Secret.

## AlertmanagerConfig

The Telegram notification configuration is defined in:

```text
environments/dev/kubernetes/monitoring/alertmanager/telegram.yaml
```

The receiver references the Kubernetes Secret:

```yaml
botToken:
  name: alertmanager-telegram
  key: bot-token
```

The Telegram configuration does not contain the plaintext bot token.

The route matches:

```text
severity = critical
```

and uses the monitoring namespace label required by the namespace-scoped `AlertmanagerConfig`.

## GitOps Flow

All configuration is maintained in the Git repository.

The deployment flow is:

```text
Git repository
      |
      v
    Argo CD
      |
      +--------------------------+
      |                          |
      v                          v
PrometheusRule              AlertmanagerConfig
      |                          |
      v                          v
 Prometheus                  Alertmanager
                                 |
                                 v
                          Telegram notification
```

The secret flow is separate:

```text
Encrypted SealedSecret
          |
          v
        Argo CD
          |
          v
Sealed Secrets Controller
          |
          v
 Kubernetes Secret
          |
          v
    Alertmanager
```

This keeps the secret encrypted while still allowing the complete monitoring configuration to remain GitOps-managed.

## Validation

The implementation was validated at several levels.

### SealedSecret validation

The SealedSecret can be validated with:

```bash
kubeseal --validate \
  --controller-name dev-sealed-secrets \
  --controller-namespace kube-system \
  < environments/dev/kubernetes/monitoring/alertmanager-telegram-sealedsecret.yaml
```

A successful validation produces no error.

### Kubernetes API validation

The AlertmanagerConfig can be checked with:

```bash
kubectl apply --dry-run=server \
  -f environments/dev/kubernetes/monitoring/alertmanager/telegram.yaml
```

### Prometheus rule validation

The Prometheus rule can be inspected through the Prometheus API:

```bash
curl -sS \
  'http://127.0.0.1:9090/api/v1/rules?type=alert' \
  | jq '.data.groups[] | .rules[] | select(.name=="KubernetesNodeNotReady")'
```

The rule should report:

```text
state: inactive
health: ok
type: alerting
```

when all Kubernetes nodes are healthy.

### Helm validation

The monitoring values are validated against the tested `kube-prometheus-stack` chart version:

```text
88.5.0
```

using `helm lint`.

## Security Considerations

The Telegram bot token is considered a secret and must not be stored as plaintext in Git.

The repository contains only the encrypted SealedSecret representation.

The Sealed Secrets certificate used by `kubeseal` is a public certificate and may be stored locally on the workstation.

The private key used by the Sealed Secrets controller remains inside the Kubernetes cluster.

Never commit:

```text
TELEGRAM_BOT_TOKEN
```

or a plaintext Kubernetes Secret containing the token.

If the Telegram bot token is compromised, revoke or regenerate the token through Telegram's BotFather and create a new SealedSecret.

## Repository Files

The relevant configuration is organized as follows:

```text
environments/dev/
├── kubernetes/
│   └── monitoring/
│       ├── alertmanager/
│       │   └── telegram.yaml
│       ├── alertmanager-telegram-sealedsecret.yaml
│       └── kube-prometheus-stack/
│           └── values.yaml
```

The Sealed Secrets controller is bootstrapped through:

```text
ansible/inventory/dev/group_vars/k8s.yml
ansible/roles/argocd_bootstrap/tasks/main.yml
```

The workstation installation of `kubeseal` is managed through:

```text
ansible/playbooks/workstation.yml
```

## Troubleshooting

### Alertmanager does not send Telegram notifications

Check the Alertmanager configuration:

```bash
kubectl get alertmanager \
  dev-monitoring-kube-promet-alertmanager \
  -n monitoring \
  -o yaml
```

Check the Alertmanager pod:

```bash
kubectl get pods -n monitoring \
  -l app.kubernetes.io/name=alertmanager
```

Check the Alertmanager configuration generated by the operator:

```bash
kubectl exec -n monitoring \
  alertmanager-dev-monitoring-kube-promet-alertmanager-0 \
  -- cat /etc/alertmanager/config_out/alertmanager.env.yaml
```

### Sealed Secret does not create the Kubernetes Secret

Check the SealedSecret:

```bash
kubectl get sealedsecret alertmanager-telegram -n monitoring
```

Check the generated Secret:

```bash
kubectl get secret alertmanager-telegram -n monitoring
```

Check the Sealed Secrets controller:

```bash
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=sealed-secrets
```

### Alert is not routed to Telegram

Verify that the alert contains the labels expected by the `AlertmanagerConfig`.

For the current node alert:

```text
severity=critical
namespace=monitoring
```

Then inspect the Alertmanager configuration and routes.

## Reproducibility

The implementation is designed to be reproducible:

* Sealed Secrets controller version is pinned.
* `kubeseal` version is pinned.
* Monitoring Helm chart version is pinned.
* Alertmanager configuration is stored in Git.
* Secret material is encrypted before being committed.
* Argo CD manages the Kubernetes resources.
* Workstation tooling is provisioned through Ansible.

This allows the notification integration to be reconstructed without storing the Telegram bot token in the repository.
