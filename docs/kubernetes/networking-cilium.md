# Kubernetes Networking with Cilium

## Overview

Cilium provides the Container Network Interface (CNI) for the Kubernetes
cluster.

The current cluster uses Cilium to provide Pod networking, Kubernetes
service connectivity, and the foundation for future network security
and observability capabilities.

## Network Configuration

The Kubernetes cluster uses the following network ranges:

| Network | CIDR |
|---|---|
| Pod Network | 10.0.0.0/16 |
| Service Network | 10.96.0.0/12 |
| Cluster DNS | 10.96.0.10 |

The Pod CIDR is configured during Kubernetes bootstrap and must be
consistent with the Cilium configuration.

## Cilium Deployment

Cilium is installed through Helm and automated using Ansible.

The Ansible role is:

```text
ansible/roles/cilium/
