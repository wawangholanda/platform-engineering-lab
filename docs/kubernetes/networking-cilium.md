# Kubernetes Networking with Cilium

## Overview

Cilium provides the Container Network Interface (CNI) for the Kubernetes cluster.

The current cluster uses Cilium to provide:

* Pod networking
* Kubernetes service connectivity
* kube-proxy replacement
* Gateway API-based application routing
* LoadBalancer IP management
* Layer 2 announcements
* Network policy capabilities
* Network observability capabilities

Cilium is deployed and managed through Ansible and Helm, while application networking resources are managed declaratively through GitOps with Argo CD.

## Network Configuration

The Kubernetes cluster uses the following network ranges:

| Network                  | CIDR                        |
| ------------------------ | --------------------------- |
| Pod Network              | 10.0.0.0/16                 |
| Service Network          | 10.96.0.0/12                |
| Cluster DNS              | 10.96.0.10                  |
| Cilium LoadBalancer Pool | 192.168.1.240-192.168.1.250 |

The Pod CIDR is configured during Kubernetes bootstrap and is used by Cilium cluster-pool IPAM.

The Service CIDR is provided by the Kubernetes cluster configuration.

The Cilium LoadBalancer IP pool is allocated from the local LAN and provides addresses for Kubernetes `LoadBalancer` resources managed by Cilium.

## Cilium Deployment

Cilium is installed through Helm and automated using Ansible.

The corresponding Ansible role is:

```text
ansible/roles/cilium/
```

The main configuration enables:

* Cluster-pool IPAM
* kube-proxy replacement
* Gateway API
* L2 announcements
* Cilium LoadBalancer IP management

The relevant configuration is:

```yaml
ipam:
  mode: cluster-pool
  operator:
    clusterPoolIPv4PodCIDRList:
      - "{{ pod_cidr }}"

gatewayAPI:
  enabled: true

kubeProxyReplacement: true

l2announcements:
  enabled: true
```

Cilium agents run across the Kubernetes nodes and provide the cluster networking datapath.

## Cluster-Pool IPAM

Cilium uses cluster-pool IPAM for Pod address allocation.

The configured Pod network is:

```text
10.0.0.0/16
```

Cilium allocates Pod addresses from this cluster-wide address space through the Cilium operator.

This provides a consistent and centrally managed Pod address allocation model across the Kubernetes nodes.

## Kube-Proxy Replacement

The cluster uses Cilium kube-proxy replacement instead of the traditional Kubernetes `kube-proxy` datapath.

```yaml
kubeProxyReplacement: true
```

This allows Cilium to provide Kubernetes service handling directly through its networking datapath.

Kube-proxy replacement is also required for the Cilium Gateway API implementation used in this environment.

This dependency was important during the Gateway API deployment: Gateway API support remained unavailable until kube-proxy replacement was enabled.

With kube-proxy replacement enabled, the Cilium agents provide the required service and networking datapath for Gateway API.

## Gateway API

Cilium Gateway API provides the application ingress and HTTP routing layer inside the Kubernetes cluster.

```yaml
gatewayAPI:
  enabled: true
```

The Gateway API resources are managed declaratively through GitOps.

The current Gateway configuration includes:

* `GatewayClass`
* `Gateway`
* `HTTPRoute`
* `ReferenceGrant`

Cilium-specific resources supporting the Gateway include:

* `CiliumLoadBalancerIPPool`
* `CiliumL2AnnouncementPolicy`

The Git-managed resources are located at:

```text
environments/dev/kubernetes/gateway/
```

The corresponding Argo CD application is:

```text
dev-gateway
```

## GatewayClass

Cilium provides the GatewayClass:

```text
cilium
```

The GatewayClass uses the Cilium Gateway controller:

```text
io.cilium/gateway-controller
```

The GatewayClass establishes Cilium as the controller responsible for managing Gateway resources that reference this class.

The Gateway must have an accepted GatewayClass before it can become ready.

## LoadBalancer IP Management

Cilium LB-IPAM provides LoadBalancer addresses from the configured pool:

```text
192.168.1.240 - 192.168.1.250
```

The configuration is managed through:

```text
environments/dev/kubernetes/gateway/cilium-lb-ip-pool.yaml
```

The configured resource is:

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: default-pool
spec:
  blocks:
    - start: 192.168.1.240
      stop: 192.168.1.250
```

The Cilium Gateway receives an address from this pool.

The current Gateway address is:

```text
192.168.1.240
```

This separates application ingress addressing from the Kubernetes API VIP.

The Kubernetes API uses:

```text
192.168.1.30:6443
```

while the Cilium Gateway uses:

```text
192.168.1.240:80
```

## L2 Announcements

Cilium L2 announcements allow LoadBalancer IP addresses to be advertised directly on the local Layer 2 network.

L2 announcements are enabled in the Cilium configuration:

```yaml
l2announcements:
  enabled: true
```

The announcement policy is managed through:

```text
environments/dev/kubernetes/gateway/cilium-l2-announcement-policy.yaml
```

This allows the Cilium LoadBalancer address to be reachable from the local LAN without requiring a separate external load balancer.

The relationship between LoadBalancer IP management and L2 announcements is:

```text
CiliumLoadBalancerIPPool
        |
        v
192.168.1.240
        |
        v
L2 Announcement
        |
        v
Local LAN
```

## Gateway Configuration

The main application Gateway is:

```text
nginx-gateway
```

It uses the Cilium GatewayClass and provides HTTP routing on port 80.

The Gateway address is:

```text
192.168.1.240
```

The Gateway configuration is managed through:

```text
environments/dev/kubernetes/gateway/nginx-gateway.yaml
```

The Gateway acts as the internal Kubernetes application entry point.

## HTTPRoute-Based Application Routing

Applications are exposed using Kubernetes `HTTPRoute` resources.

The current routes include:

```text
nginx-route
argocd-route
grafana-route
```

Routing is based on the HTTP `Host` header.

For Grafana:

```text
grafana.wawangholanda.biz.id
        |
        v
Cilium Gateway
        |
        v
grafana-route
        |
        v
monitoring/dev-monitoring-grafana:80
```

For Argo CD:

```text
argocd.wawangholanda.biz.id
        |
        v
Cilium Gateway
        |
        v
argocd-route
        |
        v
argocd/argocd-server:80
```

The same Gateway can therefore expose multiple applications while routing requests based on their hostnames.

## Cross-Namespace Routing

The Gateway and HTTPRoutes are located in the `default` namespace, while some backend services are located in other namespaces.

For example:

```text
HTTPRoute namespace:
default

Backend Service:
monitoring/dev-monitoring-grafana
```

Gateway API requires explicit permission for cross-namespace backend references.

This permission is implemented using `ReferenceGrant`.

The Grafana ReferenceGrant is managed through:

```text
environments/dev/kubernetes/gateway/grafana-reference-grant.yaml
```

The Argo CD ReferenceGrant is managed through:

```text
environments/dev/kubernetes/gateway/argocd-reference-grant.yaml
```

This creates an explicit and declarative permission boundary between the Gateway namespace and application namespaces.

The resulting architecture is:

```text
default
  |
  +-- Gateway
  |
  +-- HTTPRoute
        |
        | authorized by ReferenceGrant
        v
monitoring / argocd
  |
  +-- Backend Service
```

## External Application Access

External application access uses Cilium Gateway API together with Nginx Proxy Manager.

The current architecture is:

```text
Internet / Tailscale
        |
        v
Nginx Proxy Manager
192.168.1.3
        |
        | HTTP
        v
Cilium Gateway
192.168.1.240
        |
        +-------------------+-------------------+
        |                   |                   |
        v                   v                   v
      nginx              Argo CD             Grafana
                         argocd.*             grafana.*
```

Nginx Proxy Manager provides the external reverse-proxy layer and terminates TLS for the public application domains.

The connection from Nginx Proxy Manager to the Cilium Gateway uses HTTP on port 80.

## TLS Termination

TLS is terminated at Nginx Proxy Manager rather than at the Cilium Gateway.

The traffic flow is:

```text
Client
  |
  | HTTPS
  v
Nginx Proxy Manager
  |
  | HTTP
  v
Cilium Gateway
  |
  | HTTP
  v
Application Service
```

This means the Cilium Gateway currently provides HTTP application routing rather than TLS termination.

For Argo CD, the internal server is configured to serve HTTP because TLS is terminated by Nginx Proxy Manager.

Grafana retains its public HTTPS URL in its server configuration:

```yaml
grafana:
  grafana.ini:
    server:
      root_url: https://grafana.wawangholanda.biz.id
      serve_from_sub_path: false
```

This allows Grafana to generate links and redirects using its external HTTPS hostname while its internal connection remains HTTP.

## GitOps Management

Gateway API resources are managed through the `dev-gateway` Argo CD application.

The source repository is:

```text
platform-engineering-lab
```

The application path is:

```text
environments/dev/kubernetes/gateway
```

The Gateway configuration is therefore maintained in Git and reconciled by Argo CD rather than being maintained through manual cluster changes.

This provides:

* Declarative networking configuration
* Version-controlled changes
* Automatic reconciliation
* Self-healing
* Reproducible Gateway configuration
* Auditable networking changes

The relationship between Cilium and GitOps is:

```text
Git Repository
      |
      v
Argo CD
      |
      v
Gateway API Resources
      |
      v
Cilium Gateway Controller
      |
      v
Application Traffic
```

Cilium itself remains a platform component deployed through Ansible and Helm,
while the Gateway and application networking configuration is managed through GitOps.

## Current Networking Architecture

The current networking architecture can be summarized as:

```text
                    Kubernetes Cluster
                           |
                     +-----+-----+
                     |  Cilium  |
                     +-----+-----+
                           |
          +----------------+----------------+
          |                |                |
          v                v                v
     Pod Network      Service Network   Gateway API
     10.0.0.0/16      10.96.0.0/12          |
                                             v
                                  LoadBalancer IPAM
                                             |
                                             v
                                      192.168.1.240
                                             |
                                             v
                                      L2 Announcement
                                             |
                                             v
                                     Local LAN / NPM
                                             |
                                             v
                                      Applications
```

## Current Networking Capabilities

The current Kubernetes networking stack provides:

* Cilium CNI
* Cluster-pool IPAM
* Kubernetes Service connectivity
* Cilium kube-proxy replacement
* Cilium Gateway API
* Cilium GatewayClass
* Cilium LoadBalancer IPAM
* Cilium L2 announcements
* HTTPRoute-based application routing
* Cross-namespace routing with ReferenceGrant
* GitOps-managed Gateway configuration
* External application access through Nginx Proxy Manager
* TLS termination at the reverse proxy
* Network policy capabilities
* Network observability capabilities

Future networking and security work includes:

* Cilium NetworkPolicy
* Kubernetes security baseline
* Network traffic security validation
* Additional ingress and traffic-management experiments

## Related Documentation

```text
docs/
├── architecture/
│   └── kubernetes-ha.md
├── kubernetes/
│   ├── cluster-bootstrap.md
│   └── storage-nfs.md
├── gitops/
│   └── argocd.md
├── observability/
│   └── prometheus.md
└── operations/
    └── validation.md
```
