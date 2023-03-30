# vault-operator


# AWS

Deploy the EKS Cluster

```shell

terraform -chdir=eks/ init -upgrade
terraform -chdir=eks/ apply -auto-approve
aws eks --region $(terraform -chdir=eks/ output -raw region) update-kubeconfig --name $(terraform -chdir=eks/ output -raw cluster_name)

```

Deploy Vault

```shell
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm search repo hashicorp/vault
helm install vault hashicorp/vault -n vault --create-namespace --values vault/vault-values.yaml
```

Configure Vault

```shell
kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh
vault auth enable kubernetes
vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

vault secrets enable -path=kvv2 kv-v2
vault secrets enable -path=kv kv

vault policy write dev - <<EOF
path "kv/*" {
  capabilities = ["read"]
}

path "kvv2/*" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/role1 \
        bound_service_account_names=default \
        bound_service_account_namespaces=app \
        policies=dev \
        audience=vault \
        ttl=24h

vault kv put kv/webapp/config username="static-user" password="static-password"
```

Deploy the Vault Operator

```shell
helm install vault-secrets-operator hashicorp/vault-secrets-operator --version 0.1.0-beta -n vault-secrets-operator-system --create-namespace --values vault/vault-operator-values.yaml
```

Deploy and sync a static secret

```shell
kubectl create ns app
kubectl apply -f vault/static-secret.yaml
```