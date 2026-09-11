#!/usr/bin/env bash

set -euo pipefail

gateway_address="$(kubectl get gateway nginx-gateway \
  -n default \
  -o jsonpath='{.status.addresses[0].value}')"

if [[ -z "${gateway_address}" ]]; then
  echo "ERROR: Gateway address is empty"
  exit 1
fi

response="$(curl -fsS --max-time 10 "http://${gateway_address}/")"

if ! grep -Fq "Welcome to nginx!" <<< "${response}"; then
  echo "ERROR: Nginx response was not detected"
  exit 1
fi

echo "PASS: Gateway → HTTPRoute → ReferenceGrant → Service → Nginx"
