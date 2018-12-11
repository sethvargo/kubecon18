#!/usr/bin/env bash
set -e
set -o pipefail

kubectl create secret generic vault-tls \
  --from-file=vault.crt=tls/vault.crt \
  --from-file=vault.key=tls/vault.key
