#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TARGET_BRANCH="main"
TARGET_FILES=(
  "environments/dev/kubernetes/gateway/argocd-route.yaml"
  "environments/dev/kubernetes/gateway/grafana-route.yaml"
  "environments/dev/kubernetes/monitoring/kube-prometheus-stack/values.yaml"
)

die() {
  echo "ERROR: $*" >&2
  exit 1
}

for cmd in git python3; do
  command -v "${cmd}" >/dev/null 2>&1 ||
    die "Required command not found: ${cmd}"
done

[[ "$(git branch --show-current)" == "${TARGET_BRANCH}" ]] ||
  die "Must run on branch ${TARGET_BRANCH}."

git remote get-url origin >/dev/null 2>&1 ||
  die "Git remote 'origin' is not configured."

# Refuse staged changes, but allow unrelated unstaged and untracked work.
git diff --cached --quiet ||
  die "Staged changes exist. Commit or unstage them first."

# Never overwrite local edits to the generated target manifests.
git diff --quiet -- "${TARGET_FILES[@]}" ||
  die "Generated target manifests have local changes. Review or restore them first."

SECRETS_ENV="${ROOT_DIR}/.secrets/.env"
[[ -f "${SECRETS_ENV}" ]] ||
  die ".secrets/.env not found."

set -a
source "${SECRETS_ENV}"
set +a

echo "==> Fetching origin/main"
git fetch origin "${TARGET_BRANCH}"

LOCAL_HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse "origin/${TARGET_BRANCH}")"

[[ "${LOCAL_HEAD}" == "${REMOTE_HEAD}" ]] ||
  die "Local main and origin/main differ. Reconcile them before publishing."

echo "==> Validating domain templates"
python3 "${ROOT_DIR}/scripts/render-domain-config.py"

echo "==> Rendering domain configuration"
python3 "${ROOT_DIR}/scripts/render-domain-config.py" --write

echo "==> Staging only generated domain manifests"
git add -- "${TARGET_FILES[@]}"

if git diff --cached --quiet; then
  echo "==> Generated manifests are unchanged; no commit or push needed."
  exit 0
fi

git diff --cached --check ||
  die "Generated changes failed git diff --check."

echo "==> Committing only generated domain manifests"
git commit -m "chore(gitops): render domain configuration" -- "${TARGET_FILES[@]}"

echo "==> Pushing to origin/${TARGET_BRANCH}"
git push origin "HEAD:${TARGET_BRANCH}"

echo "==> Domain manifests published successfully."
