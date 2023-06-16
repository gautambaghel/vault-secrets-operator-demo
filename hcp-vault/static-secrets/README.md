# Working with static secrets (HCP Vault)

## Configure k8s

```shell
kubectl create ns app-sa
kubectl create sa app-sa -n app
kubectl create clusterrolebinding vault-client-auth-delegator \
  --clusterrole=system:auth-delegator \
  --serviceaccount=app:app-sa

kubectl create -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-token
  namespace: app
  annotations:
    kubernetes.io/service-account.name: app-sa
type: kubernetes.io/service-account-token
EOF

export TOKEN_REVIEW_JWT=$(kubectl get secret vault-token -n app -o json \
  | jq -r '.data | .token' \
  | base64 --decode)

export KUBE_CA_CERT=$(kubectl get secret vault-token -n app -o json \
  | jq -r '.data | ."ca.crt"' \
  | base64 --decode)

export KUBE_HOST=$(kubectl config view --raw --minify --flatten \
   -o jsonpath='{.clusters[].cluster.server}')
```

## Configure HCP Vault

```shell
vault auth enable kubernetes
vault write auth/kubernetes/config \
   token_reviewer_jwt="$TOKEN_REVIEW_JWT" \
   kubernetes_host="$KUBE_HOST" \
   kubernetes_ca_cert="$KUBE_CA_CERT"

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
        bound_service_account_names=app-sa \
        bound_service_account_namespaces=app \
        policies=dev \
        audience=vault \
        ttl=24h

vault kv put kv/webapp/config username="static-user" password="static-password"
vault kv put kvv2/webapp/config username="static-user-kvv2" password="static-password-kvv2"
exit
```

## Create the static secret CRDs

```shell
kubectl apply -f hcp-vault/static-secrets/.
```

## Verify the static secrets were created

```shell
kubectl get secret secretkv -n app -o json | jq -r .data._raw | base64 -D
kubectl get secret secretkvv2 -n app -o json | jq -r .data._raw | base64 -D
```

## Change the secrets and verify they are synced

```shell
vault kv put kv/webapp/config username="new-static-user" password="new-static-password"
vault kv put kvv2/webapp/config username="new-static-user-kvv2" password="new-static-password-kvv2"
exit
```

## Verify the static secrets were updated (wait 30s)

```shell
kubectl get secret secretkv -n app -o json | jq -r .data._raw | base64 -D
kubectl get secret secretkvv2 -n app -o json | jq -r .data._raw | base64 -D
```
