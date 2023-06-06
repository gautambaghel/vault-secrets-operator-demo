# Working with dynamic secrets


## Deploy Postgres Server

```shell
kubectl create ns postgres

helm repo add bitnami https://charts.bitnami.com/bitnami

helm upgrade --install postgres bitnami/postgresql --namespace postgres --set auth.audit.logConnections=true

export POSTGRES_PASSWORD=$(kubectl get secret --namespace postgres postgres-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)

echo $POSTGRES_PASSWORD
```

For OpenShift

```shell
helm upgrade --install postgres bitnami/postgresql --namespace postgres -f postgres/values.yaml

export POSTGRES_PASSWORD=$(kubectl get secret --namespace postgres postgres-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)

echo $POSTGRES_PASSWORD
```

## Configure Postgres backend in Vault

```shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh

vault secrets enable -path=demo-db database

# Paste the POSTGRES_PASSWORD from the step above
vault write demo-db/config/demo-db \
  plugin_name=postgresql-database-plugin \
  allowed_roles="dev-postgres" \
  connection_url="postgresql://{{username}}:{{password}}@postgres-postgresql.postgres.svc.cluster.local:5432/postgres?sslmode=disable" \
  username="postgres" \
  password="<POSTGRES_PASSWORD from deploy postgres server step above>"

vault write demo-db/roles/dev-postgres \
  db_name=demo-db \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
      GRANT ALL PRIVILEGES ON DATABASE postgres TO \"{{name}}\";" \
  backend=demo-db \
  name=dev-postgres \
  default_ttl="1h" \
  max_ttl="24h"

vault policy write demo-auth-policy-db - <<EOT
path "demo-db/creds/dev-postgres" {
  capabilities = ["read"]
}
EOT

```

## Configure K8s Auth in Vault

```shell

# Enable Kubernetes auth backend
vault auth enable -path demo-auth-mount kubernetes

# Configure Kubernetes auth backend
vault write auth/demo-auth-mount/config \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  disable_iss_validation=true

# Create Kubernetes auth role
vault write auth/demo-auth-mount/role/auth-role \
  bound_service_account_names=default \
  bound_service_account_namespaces=demo-ns \
  token_ttl=0 \
  token_max_ttl=120 \
  token_policies=demo-auth-policy-db \
  audience=vault

```

## Configure Transit engine in Vault

```shell
# Create a transit backend mount
vault secrets enable -path=demo-transit transit

# Create a cache secret cache configuration
vault write demo-transit/cache-config size=500

# Create a transit key
vault write -force demo-transit/keys/vso-client-cache

# Create a policy for the operator role
vault policy write demo-auth-policy-operator - <<EOF
path "demo-transit/encrypt/vso-client-cache" {
  capabilities = ["create", "update"]
}
path "demo-transit/decrypt/vso-client-cache" {
  capabilities = ["create", "update"]
}
EOF

# Create Kubernetes auth role
vault write auth/demo-auth-mount/role/auth-role-operator \
  bound_service_account_names=demo-operator \
  bound_service_account_namespaces=vault-secrets-operator-system \
  token_ttl=0 \
  token_max_ttl=120 \
  token_policies=demo-auth-policy-db \
  audience=vault

exit
```

## Create the App

```shell
kubectl create ns demo-ns
kubectl apply -f vault/dynamic-secrets/.
```

For OpenShift

> **Not recommended in production**

```shell
oc create sa demo-sa -n demo-ns
oc adm policy add-scc-to-user privileged -z demo-sa -n demo-ns
oc set sa deployment vso-db-demo demo-sa -n demo-ns
```

## Verify the App pods are running

```shell
kubectl get pods -n demo-ns
kubectl get secret vso-db-demo -n demo-ns -o json | jq -r .data._raw | base64 -D
kubectl get secret vso-db-demo-created -n demo-ns -o json | jq -r .data._raw | base64 -D
```