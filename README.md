# Vault Operator Demo

This repository contains some samples on how to use the Vault operator with different Cloud hosted Kubernetes solutions.

<details>

<summary>
    <h2>
        Deploy your Kubernetes cluster
    </h2>
</summary>

### KIND

```shell
$ kind get clusters | grep --silent "^kind$$" || kind create cluster --wait=5m --image kindest/node:v1.25.3 --name kind --config kind/config.yaml
$ kubectl config use-context kind-kind
```

### GCP

```shell       
$ gcloud init
$ gcloud auth application-default login
$ echo 'project_id = "'$(gcloud config get-value project)'"' > gke/terraform.tfvars && echo 'region = "us-west1"' >> gke/terraform.tfvars

$ terraform -chdir=gke/ init -upgrade
$ terraform -chdir=gke/ apply -auto-approve
$ gcloud container clusters get-credentials $(terraform -chdir=gke/ output -raw kubernetes_cluster_name) --region $(terraform -chdir=gke/ output -raw region)
```

### AWS

```shell
$ export AWS_ACCESS_KEY_ID="..."
$ export AWS_SECRET_ACCESS_KEY="..."
$ export AWS_SESSION_TOKEN="..."
                          
$ terraform -chdir=eks/ init -upgrade
$ terraform -chdir=eks/ apply -auto-approve
$ aws eks --region $(terraform -chdir=eks/ output -raw region) update-kubeconfig --name $(terraform -chdir=eks/ output -raw cluster_name)
```

### Azure

```shell
$ az config set core.allow_broker=true && az account clear && az login
$ az account set --subscription <subscription_id>
$ az ad sp create-for-rbac --output json | jq -r '. | "appId = \"" + .appId + "\"\npassword = \"" + .password + "\"" ' > aks/terraform.tfvars

$ terraform -chdir=aks/ init -upgrade
$ terraform -chdir=aks/ apply -auto-approve
$ az aks get-credentials --resource-group $(terraform -chdir=aks/ output -raw resource_group_name) --name $(terraform -chdir=aks/ output -raw kubernetes_cluster_name)
```

</details>

## Deploy Vault

```shell
$ helm repo add hashicorp https://helm.releases.hashicorp.com
$ helm repo update
$ helm search repo hashicorp/vault
$ helm install vault hashicorp/vault -n vault --create-namespace --values vault/vault-values.yaml
```

## Configure Vault

```shell
$ kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh
$ vault auth enable kubernetes
$ vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

$ vault secrets enable -path=kvv2 kv-v2
$ vault secrets enable -path=kv kv

$ vault policy write dev - <<EOF
path "kv/*" {
  capabilities = ["read"]
}

path "kvv2/*" {
  capabilities = ["read"]
}
EOF

$ vault write auth/kubernetes/role/role1 \
        bound_service_account_names=default \
        bound_service_account_namespaces=app \
        policies=dev \
        audience=vault \
        ttl=24h

$ vault kv put kv/webapp/config username="static-user" password="static-password"
$ vault kv put kvv2/webapp/config username="static-user-kvv2" password="static-password-kvv2"
$ exit
```

## Deploy the Vault Operator

```shell
$ helm install vault-secrets-operator hashicorp/vault-secrets-operator --version 0.1.0-beta -n vault-secrets-operator-system --create-namespace --values vault/vault-operator-values.yaml
```

## Create a new namespace for the demo app & the static secret CRDs

```shell
$ kubectl create ns app
$ kubectl apply -f vault/static-secret.yaml
```

## Verify the static secrets were created

```shell
$ kubectl get secret secretkv -n app -o json | jq -r .data._raw | base64 -D
$ kubectl get secret secretkvv2 -n app -o json | jq -r .data._raw | base64 -D
```

## Change the secrets and verify they are synced

```shell
$ kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh
$ vault kv put kv/webapp/config username="new-static-user" password="new-static-password"
$ vault kv put kvv2/webapp/config username="new-static-user-kvv2" password="new-static-password-kvv2"
$ exit
```

## Verify the static secrets were updated (wait 30s)

```shell
$ kubectl get secret secretkv -n app -o json | jq -r .data._raw | base64 -D
$ kubectl get secret secretkvv2 -n app -o json | jq -r .data._raw | base64 -D
```