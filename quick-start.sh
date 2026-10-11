#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Platform Engineering Lab Quick Start"
echo "    Repository: ${ROOT_DIR}"

SECRETS_ENV="${ROOT_DIR}/.secrets/.env"

if [[ ! -f "${SECRETS_ENV}" ]]; then
  echo "ERROR: ${SECRETS_ENV} not found."
  echo "       Create .secrets/.env and configure it first."
  exit 1
fi

echo "==> Loading environment"
set -a
source "${SECRETS_ENV}"
set +a
if [[ "${ENABLE_TAILSCALE:-}" != "true" &&
      "${ENABLE_TAILSCALE:-}" != "false" ]]; then
  echo "ERROR: ENABLE_TAILSCALE must be 'true' or 'false'."
  exit 1
fi

echo "    ENABLE_TAILSCALE=${ENABLE_TAILSCALE}"

if [[ -z "${ARGOCD_DOMAIN:-}" || -z "${GRAFANA_DOMAIN:-}" ]]; then
  echo "ERROR: ARGOCD_DOMAIN and GRAFANA_DOMAIN must be configured."
  exit 1
fi


required_commands=(
  terraform
  ansible-playbook
  kubectl
  helm
  kubeseal
)

echo "==> Checking required commands"

for cmd in "${required_commands[@]}"; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${cmd}"
    exit 1
  fi
done

echo "    All required commands are available."

if [[ -z "${TF_VAR_proxmox_api_url:-}" ||
      -z "${TF_VAR_proxmox_api_token_id:-}" ||
      -z "${TF_VAR_proxmox_api_token_secret:-}" ||
      -z "${TF_VAR_ssh_public_key:-}" ||
      -z "${TF_VAR_cloud_init_password:-}" ]]; then
  echo "ERROR: required Terraform environment variables are missing."
  exit 1
fi

echo "==> Environment validation passed."

echo
echo "Domain configuration will be rendered and published to origin/main."
echo "Only the three generated domain manifests will be committed."
echo "This must complete successfully before Terraform starts."

if [[ ! -t 0 ]]; then
  echo "ERROR: Domain publication requires an interactive terminal."
  exit 1
fi

read -r -p "Publish domain configuration now? [y/N] " domain_confirm

if [[ ! "${domain_confirm}" =~ ^[Yy]$ ]]; then
  echo "==> Domain publication cancelled; Terraform will not run."
  exit 1
fi

echo "==> Publishing domain configuration"
"${ROOT_DIR}/scripts/publish-domain-config.sh"
echo "==> Domain configuration publication completed."

TERRAFORM_DIR="${ROOT_DIR}/environments/dev/proxmox"
TERRAFORM_PLAN="$(mktemp)"

cleanup() {
  rm -f "${TERRAFORM_PLAN}"
}

trap cleanup EXIT

echo "==> Initializing Terraform"
cd "${TERRAFORM_DIR}"
terraform init -input=false

echo "==> Validating Terraform configuration"
terraform validate

echo "==> Creating Terraform plan"
terraform plan \
  -input=false \
  -out="${TERRAFORM_PLAN}"

echo "==> Terraform plan created successfully."

read -r -p "Apply this Terraform plan? [y/N] " terraform_confirm

if [[ ! "${terraform_confirm}" =~ ^[Yy]$ ]]; then
  echo "==> Terraform apply skipped."
  exit 0
fi
echo "==> Applying Terraform plan"
terraform apply "${TERRAFORM_PLAN}"

echo "==> Terraform apply completed successfully."

cd "${ROOT_DIR}"

echo "==> Running Ansible platform configuration"
ansible-playbook \
  -i "${ROOT_DIR}/ansible/inventory/dev/hosts.yml" \
  "${ROOT_DIR}/ansible/playbooks/site.yml"

echo "==> Ansible platform configuration completed successfully."

if [[ "${ENABLE_TAILSCALE}" == "true" ]]; then
  echo "==> Running Ansible Tailscale gateway configuration"
  ansible-playbook \
    -i "${ROOT_DIR}/ansible/inventory/dev/hosts.yml" \
    "${ROOT_DIR}/ansible/playbooks/tailscale-gateway.yml"

  echo "==> Ansible Tailscale gateway configuration completed successfully."
else
  echo "==> Tailscale gateway disabled; skipping Tailscale configuration."
fi
