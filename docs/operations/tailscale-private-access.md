# Private Tailscale Access

## Purpose

Provide private HTTPS access to Argo CD and Grafana through a dedicated Tailscale gateway and an Ansible-managed Nginx reverse proxy.

## Architecture

```text
Tailscale client
      |
      | HTTPS :443
      v
tailscale-gateway
100.121.197.34
      |
      | Nginx reverse proxy
      v
Platform services
      +-- Argo CD
      +-- Grafana
```

The gateway uses a Let's Encrypt certificate covering both service domains. Certbot obtains and renews the certificate through the Cloudflare DNS-01 challenge.

## Ansible Implementation

- Playbook: `ansible/playbooks/tailscale-reverse-proxy.yml`
- Role: `ansible/roles/tailscale_reverse_proxy`
- Deployment helper: `scripts/configure-tailscale-reverse-proxy.sh`

The role manages Nginx, Certbot dependencies, Cloudflare DNS credentials, the reverse-proxy configuration, and the Certbot deploy hook.

Nginx is configured to wait for the Tailscale interface address during service
startup. After certificate renewal, the deploy hook tests the Nginx configuration
before attempting a reload.

## Configuration Requirements

The following values are loaded from `.secrets/.env` by the deployment workflow and must not be committed as secrets:

- `ARGOCD_DOMAIN`
- `GRAFANA_DOMAIN`
- `CLOUDFLARE_API_TOKEN`
- `LETSENCRYPT_EMAIL`

Keep real credentials out of tracked files, terminal output, and documentation.

## Validation

### 1. Check Ansible syntax

```bash
ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/tailscale-reverse-proxy.yml \
  --syntax-check
```

### 2. Simulate the playbook

Run the check-mode simulation before applying changes:

```bash
set -a
source .secrets/.env
set +a

ansible-playbook \
  -i ansible/inventory/dev/hosts.yml \
  ansible/playbooks/tailscale-reverse-proxy.yml \
  --limit tailscale-gateway \
  --extra-vars "argocd_domain=${ARGOCD_DOMAIN} grafana_domain=${GRAFANA_DOMAIN}" \
  --check --diff
```

### 3. Validate Nginx on the gateway

```bash
sudo nginx -t
sudo systemctl is-active nginx
sudo systemctl is-enabled nginx
```

### 4. Validate HTTPS from a Tailscale client

Run these commands from a client connected to Tailscale. Ensure the domain variables are loaded from `.secrets/.env` first.

Ensure DNS resolution for both service domains points to the Tailscale gateway
before running HTTPS validation. The certificate validation depends on the
requested hostname matching the configured SAN certificate and Nginx server
names. The client must resolve both domains to the gateway address through the configured DNS path before running the HTTPS validation.

```bash
curl -sS -o /dev/null \
  -w 'HTTP %{http_code}; TLS verify=%{ssl_verify_result}\n' \
  "https://${ARGOCD_DOMAIN}/"

curl -sS -o /dev/null \
  -w 'HTTP %{http_code}; TLS verify=%{ssl_verify_result}\n' \
  "https://${GRAFANA_DOMAIN}/"
```

A TLS verification result of `0` indicates successful certificate validation. HTTP status codes can vary with application redirects and authentication.

## Verified Status

The following checks have passed:

- Ansible playbook syntax check and check-mode simulation.
- Check mode reported `changed=0` and `failed=0` after the Certbot deploy hook was applied.
- Nginx configuration test passed; the service was active and enabled.
- Nginx listened on `100.121.197.34:443`.
- A Tailscale client successfully reached the gateway.
- Argo CD returned HTTP `200` with TLS verification result `0`.
- Grafana returned HTTP `302` with TLS verification result `0`.

These checks validate the tested client-to-gateway HTTPS path. They do not
replace a separate audit of firewall rules, direct upstream exposure, or
certificate renewal execution.

## Future Work

- Design and validate high availability for Tailscale access through `lb01` and `lb02`.
- Audit firewall rules and direct access to upstream services.
- Test certificate renewal and the deploy hook in a controlled maintenance window.
