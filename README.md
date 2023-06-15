# Vault Secrets Operator Demo

This repository contains some samples on how to use the Vault Secrets Operator (VSO) with different Cloud hosted kubernetes solutions.

## Deploy your Kubernetes cluster

### KIND

```shell
kind get clusters | grep --silent "^kind$$" || kind create cluster --wait=5m \
    --image kindest/node:v1.25.3 --name kind --config infra/kind/config.yaml

kubectl config use-context kind-kind
```

### Google Cloud (GKE)

```shell       
gcloud init
gcloud auth application-default login
echo 'project_id = "'$(gcloud config get-value project)'"' > infra/gke/terraform.tfvars \
    && echo 'region = "us-west1"' >> infra/gke/terraform.tfvars

terraform -chdir=infra/gke/ init -upgrade
terraform -chdir=infra/gke/ apply -auto-approve
gcloud container clusters get-credentials \
    $(terraform -chdir=infra/gke/ output -raw kubernetes_cluster_name) \
    --region $(terraform -chdir=infra/gke/ output -raw region)
```

### AWS (EKS)

```shell
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
                          
terraform -chdir=infra/eks/ init -upgrade
terraform -chdir=infra/eks/ apply -auto-approve
aws eks --region $(terraform -chdir=infra/eks/ output -raw region) \
    update-kubeconfig --name $(terraform -chdir=infra/eks/ output -raw cluster_name)
```

### Azure (AKS)

```shell
az config set core.allow_broker=true && az account clear && az login
az account set --subscription <subscription_id>
az ad sp create-for-rbac --output json \
    | jq -r '. | "appId = \"" + .appId + "\"\npassword = \"" + .password + "\"" ' \
    > infra/aks/terraform.tfvars

terraform -chdir=infra/aks/ init -upgrade
terraform -chdir=infra/aks/ apply -auto-approve
az aks get-credentials --resource-group \
    $(terraform -chdir=infra/aks/ output -raw resource_group_name) \
    --name $(terraform -chdir=infra/aks/ output -raw kubernetes_cluster_name)
```

# Vault

## Deploy Vault

```shell
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm search repo hashicorp/vault
helm install vault hashicorp/vault -n vault \
    --create-namespace --values vault/vault-server-values.yaml
```

> **For OpenShift**

```shell
helm install vault hashicorp/vault -n vault \
    --create-namespace --values vault/vault-server-values.yaml \
    --set "global.openshift=true"
```

## Deploy the Vault Secrets Operator

```shell
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
    --version 0.1.0 -n vault-secrets-operator-system \
    --create-namespace --values vault/vault-operator-values.yaml
```

## Using the Vault Secrets Operator

### * [Working with Static secrets](/vault/static-secrets/README.md)
### * [Working with Dynamic secrets](/vault/dynamic-secrets/README.md)
### * [Working with PKI](/vault/pki/README.md)


# HCP Vault

> **Limited support: works with pre-deployed public cluster & static secrets only**

This guide assumes you have HCP Vault deployed and configured with your cloud providers already
and the cluster URL is publicly accessible

## Deploy the Vault Secrets Operator (HCP Vault)

```shell
# Uncomment line 7 in hcp-vault/vault-operator-values.yaml file
# Add publicly accessible endpoint for HCP Vault "https://vault-public-url.hashicorp.cloud:8200"

helm install vault-secrets-operator hashicorp/vault-secrets-operator \
    --version 0.1.0 -n vault-secrets-operator-system \
    --create-namespace --values hcp-vault/hcp-vault-operator-values.yaml
```

## Using the Vault Secrets Operator (HCP Vault)

### * [Working with Static secrets](/hcp-vault/static-secrets/README.md)
### * [Working with Dynamic secrets](/hcp-vault/dynamic-secrets/README.md)
### * [Working with PKI](/hcp-vault/pki/README.md)