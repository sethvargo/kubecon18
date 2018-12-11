# Kubecon 2018 Vault + Kubernetes

This repo contains the scripts and configurations I used in my 2018 Kubecon talk
"So You Want to Run Vault in Kubernetes".

The script and setup are mostly meant for me, but the configurations are largely
applicable anywhere.

## Remove all existing contexts

```text
$ rm -rf ~/.kube
```

## Create Vault on GKE cluster

```text
$ cd Development/kubecon
$ terraform apply
```

## Demo 1 - Deploy Vault

Create the secret which will hold our TLS configuration:

```text
$ ./scripts/01-create-secret.sh
```

Inspect the Vault YAML:

```text
$ vi vault.yaml
```

Apply the Vault YAML:

```text
$ kubectl apply -f vault.yaml
```

Show that Vault is running:

```text
$ kubectl get po
```

Configure talk to load balancer:

```text
$ source vault.env
```

Show Vault is uninitialized:

```text
$ vault status
```

Initialize Vault:

```text
vault operator init
```

Save the vault token:

```text
echo "export VAULT_TOKEN=..." >> vault.env
```

```text
source vault.env
```

```text
vault write secret/kubecon message=hello
```


## Demo 2 - Auth to Kubernetes

Get the name of the `apps-cluster` context:

```text
$ kubectl config get-contexts
```

Switch to the context:

```text
$ kubectl config use-context gke_kubecon-..._apps-cluster
```

Explore setup:

```text
$ vi scripts/02-configure-k8s-auth-method.sh
```

Run setup:

```text
$ ./scripts/02-configure-k8s-auth-method.sh
```

Create container and establish connection:

```text
$ kubectl run demo-shell --rm --env VAULT_ADDR=$VAULT_ADDR -it --image debian -- /bin/bash
```

Install some tools into said container:

```text
$ apt-get update && apt-get install -yqq curl jq
```

Get the JWT token and post it to vault to authenticate

```text
JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

curl -sk $VAULT_ADDR/v1/auth/kubernetes/login -d @- <<EOF | jq .
{
  "role": "demo",
  "jwt": "${JWT}"
}
EOF
```

Extract the token and make retrieve the secret from Vault:

```text
curl -sk -H "x-vault-token: ..." $VAULT_ADDR/v1/secret/kubecon | jq .
```
