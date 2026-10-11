
#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

SECRETS_ENV="${ROOT_DIR}/.secrets/.env"
INVENTORY="${ROOT_DIR}/ansible/inventory/dev/hosts.yml"
PLAYBOOK="${ROOT_DIR}/ansible/playbooks/tailscale-reverse-proxy.yml"

[[ -f "${SECRETS_ENV}" ]] || die ".secrets/.env not found."
[[ -f "${INVENTORY}" ]] || die "Ansible inventory not found."
[[ -f "${PLAYBOOK}" ]] || die "Reverse proxy playbook not found."

command -v ansible-playbook >/dev/null 2>&1 ||
  die "ansible-playbook is required."

# Load variables from the project environment file without exporting all of them.
source "${SECRETS_ENV}"

[[ -n "${ARGOCD_DOMAIN:-}" ]] ||
  die "ARGOCD_DOMAIN is missing from .secrets/.env."

[[ -n "${GRAFANA_DOMAIN:-}" ]] ||
  die "GRAFANA_DOMAIN is missing from .secrets/.env."

[[ -n "${CLOUDFLARE_API_TOKEN:-}" ]] ||
  die "CLOUDFLARE_API_TOKEN is missing from .secrets/.env."

[[ -n "${LETSENCRYPT_EMAIL:-}" ]] ||
  die "LETSENCRYPT_EMAIL is missing from .secrets/.env."

# Export only the credentials required by the Ansible role.
export CLOUDFLARE_API_TOKEN
export LETSENCRYPT_EMAIL

echo "==> Checking reverse proxy playbook syntax"
ansible-playbook \
  -i "${INVENTORY}" \
  "${PLAYBOOK}" \
  --syntax-check

echo "==> Configuring Tailscale reverse proxy"
ansible-playbook \
  -i "${INVENTORY}" \
  "${PLAYBOOK}" \
  --extra-vars "argocd_domain=${ARGOCD_DOMAIN} grafana_domain=${GRAFANA_DOMAIN}"

echo "==> Tailscale reverse proxy playbook completed."
