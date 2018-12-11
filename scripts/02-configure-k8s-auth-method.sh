#!/usr/bin/env bash
set -e
set -o pipefail

# Create the service account which Vault will use to authenticate tokens
kubectl apply -f - <<EOH
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth

---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: role-tokenreview-binding
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: default
EOH

# Get the name of the secret corresponding to the service account
SECRET_NAME="$(kubectl get serviceaccount vault-auth \
  -o go-template='{{ (index .secrets 0).name }}')"

# Get the actual token reviewer account
TR_ACCOUNT_TOKEN="$(kubectl get secret ${SECRET_NAME} \
  -o go-template='{{ .data.token }}' | base64 --decode)"

# Get the host for the apps cluster
CLUSTER_NAME="gke_${GOOGLE_CLOUD_PROJECT}_${GOOGLE_CLOUD_REGION}_apps-cluster"
K8S_HOST="$(kubectl config view --raw \
  -o go-template="{{ range .clusters }}{{ if eq .name \"${CLUSTER_NAME}\" }}{{ index .cluster \"server\" }}{{ end }}{{ end }}")"

# Get the CA for the apps cluster
K8S_CACERT="$(kubectl config view --raw \
  -o go-template="{{ range .clusters }}{{ if eq .name \"${CLUSTER_NAME}\" }}{{ index .cluster \"certificate-authority-data\" }}{{ end }}{{ end }}" | base64 --decode)"

# Enable the Kubernetes auth method
vault auth enable kubernetes

# Configure Vault to talk to our Kubernetes host with the cluster's CA and the
# correct token reviewer JWT token
vault write auth/kubernetes/config \
  kubernetes_host="${K8S_HOST}" \
  kubernetes_ca_cert="${K8S_CACERT}" \
  token_reviewer_jwt="${TR_ACCOUNT_TOKEN}"

# Create a policy which permits reading from the key-value store
vault policy write secret-readonly -<<EOF
path "secret/*" {
  capabilities = ["read"]
}
EOF

# Create a role against which to authenticate
vault write auth/kubernetes/role/demo \
  bound_service_account_names="default" \
  bound_service_account_namespaces="default" \
  policies="secret-readonly" \
  ttl="1h"

# Create a config map to store the vault address
kubectl create configmap vault \
  --from-literal "vault_addr=https://${VAULT_ADDR}"

# Create a secret for our CA
DIR="$(pwd)/tls"
kubectl create secret generic vault-tls \
  --from-file "${DIR}/ca.crt"
