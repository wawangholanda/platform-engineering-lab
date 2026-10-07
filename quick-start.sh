#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Platform Engineering Lab Quick Start"
echo "    Repository: ${ROOT_DIR}"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  echo "ERROR: .env not found."
  echo "       Copy .env.example to .env and configure it first."
  exit 1
fi
echo "==> Loading environment"
source "${ROOT_DIR}/.env"

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
terraform plan -input=false -out="${TERRAFORM_PLAN}"

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
