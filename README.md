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
$ kind get clusters | grep --silent "^kind$$" || kind create cluster --wait=5m --image kindest/node:v1.25.3 --name kind --config infra/kind/config.yaml
$ kubectl config use-context kind-kind
```

### GCP

```shell       
$ gcloud init
$ gcloud auth application-default login
$ echo 'project_id = "'$(gcloud config get-value project)'"' > infra/gke/terraform.tfvars && echo 'region = "us-west1"' >> infra/gke/terraform.tfvars

$ terraform -chdir=infra/gke/ init -upgrade
$ terraform -chdir=infra/gke/ apply -auto-approve
$ gcloud container clusters get-credentials $(terraform -chdir=infra/gke/ output -raw kubernetes_cluster_name) --region $(terraform -chdir=infra/gke/ output -raw region)
```

### AWS

```shell
$ export AWS_ACCESS_KEY_ID="..."
$ export AWS_SECRET_ACCESS_KEY="..."
$ export AWS_SESSION_TOKEN="..."
                          
$ terraform -chdir=infra/eks/ init -upgrade
$ terraform -chdir=infra/eks/ apply -auto-approve
$ aws eks --region $(terraform -chdir=infra/eks/ output -raw region) update-kubeconfig --name $(terraform -chdir=infra/eks/ output -raw cluster_name)
```

### Azure

```shell
$ az config set core.allow_broker=true && az account clear && az login
$ az account set --subscription <subscription_id>
$ az ad sp create-for-rbac --output json | jq -r '. | "appId = \"" + .appId + "\"\npassword = \"" + .password + "\"" ' > infra/aks/terraform.tfvars

$ terraform -chdir=infra/aks/ init -upgrade
$ terraform -chdir=infra/aks/ apply -auto-approve
$ az aks get-credentials --resource-group $(terraform -chdir=infra/aks/ output -raw resource_group_name) --name $(terraform -chdir=infra/aks/ output -raw kubernetes_cluster_name)
```

</details>

## Deploy Vault

```shell
$ helm repo add hashicorp https://helm.releases.hashicorp.com
$ helm repo update
$ helm search repo hashicorp/vault
$ helm install vault hashicorp/vault -n vault --create-namespace --values vault/vault-server-values.yaml
```

## Deploy the Vault Operator

```shell
$ helm install vault-secrets-operator hashicorp/vault-secrets-operator --version 0.1.0-beta -n vault-secrets-operator-system --create-namespace --values vault/vault-operator-values.yaml
```

## Working with static secrets

### Configure Vault

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

### Create a new namespace for the demo app & the static secret CRDs

```shell
$ kubectl create ns app
$ kubectl apply -f vault/static-secrets/vault-kv-secret.yaml
$ kubectl apply -f vault/static-secrets/vault-kvv2-secret.yaml
```

### Verify the static secrets were created

```shell
$ kubectl get secret secretkv -n app -o json | jq -r .data._raw | base64 -D
$ kubectl get secret secretkvv2 -n app -o json | jq -r .data._raw | base64 -D
```

### Change the secrets and verify they are synced

```shell
$ kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh
$ vault kv put kv/webapp/config username="new-static-user" password="new-static-password"
$ vault kv put kvv2/webapp/config username="new-static-user-kvv2" password="new-static-password-kvv2"
$ exit
```

### Verify the static secrets were updated (wait 30s)

```shell
$ kubectl get secret secretkv -n app -o json | jq -r .data._raw | base64 -D
$ kubectl get secret secretkvv2 -n app -o json | jq -r .data._raw | base64 -D
```

## Working with dynamic secrets


### Deploy Postgres Server

```shell
$ kubectl create ns postgres
$ helm repo add bitnami https://charts.bitnami.com/bitnami
$ helm upgrade --install postgres bitnami/postgresql --namespace postgres --set auth.audit.logConnections=true
$ export POSTGRES_PASSWORD=$(kubectl get secret --namespace postgres postgres-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)
$ echo $POSTGRES_PASSWORD
```

### Configure Postgres backend in Vault

```shell
$ kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh
$ vault secrets enable -path=demo-db database

# Paste the POSTGRES_PASSWORD from the step above
$ vault write demo-db/config/demo-db \
    plugin_name=postgresql-database-plugin \
    allowed_roles="dev-postgres" \
    connection_url="postgresql://{{username}}:{{password}}@postgres-postgresql.postgres.svc.cluster.local:5432/postgres?sslmode=disable" \
    username="postgres" \
    password="<POSTGRES_PASSWORD from deploy postgres server step above>"

$ vault write demo-db/roles/dev-postgres \
    db_name=demo-db \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT ALL PRIVILEGES ON DATABASE postgres TO \"{{name}}\";" \
    backend=demo-db \
    name=dev-postgres \
    default_ttl="1h" \
    max_ttl="24h"

$ vault policy write demo-auth-policy-db - <<EOT
path "demo-db/creds/dev-postgres" {
  capabilities = ["read"]
}
EOT

```

### Configure K8s Auth in Vault

```shell

# Enable Kubernetes auth backend
$ vault auth enable -path demo-auth-mount kubernetes

# Configure Kubernetes auth backend
$ vault write auth/demo-auth-mount/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    disable_iss_validation=true

# Create Kubernetes auth role
$ vault write auth/demo-auth-mount/role/auth-role \
    bound_service_account_names=default \
    bound_service_account_namespaces=demo-ns \
    token_ttl=0 \
    token_max_ttl=120 \
    token_policies=demo-auth-policy-db \
    audience=vault

```

### Configure Transit engine in Vault

```shell
# Create a transit backend mount
$ vault secrets enable -path=demo-transit transit

# Create a cache secret cache configuration
$ vault write demo-transit/config/caching size=500

# Create a transit key
$ vault write -force demo-transit/keys/vso-client-cache

# Create a policy for the operator role
$ vault policy write demo-auth-policy-operator - <<EOF
path "demo-transit/encrypt/vso-client-cache" {
  capabilities = ["create", "update"]
}
path "demo-transit/decrypt/vso-client-cache" {
  capabilities = ["create", "update"]
}
EOF

# Create Kubernetes auth role
$ vault write auth/demo-auth-mount/role/auth-role-operator \
    bound_service_account_names=demo-operator \
    bound_service_account_namespaces=vault-secrets-operator-system \
    token_ttl=0 \
    token_max_ttl=120 \
    token_policies=demo-auth-policy-db \
    audience=vault

$ exit
```


### Create the App

```shell
$ kubectl create ns demo-ns
$ kubectl apply -f vault/dynamic-secrets/.
```

### Verify the App pods are running

```shell
$ kubectl get pods -n demo-ns
$ kubectl get secret vso-db-demo -n demo-ns -o json | jq -r .data._raw | base64 -D
$ kubectl get secret vso-db-demo-created -n demo-ns -o json | jq -r .data._raw | base64 -D
```