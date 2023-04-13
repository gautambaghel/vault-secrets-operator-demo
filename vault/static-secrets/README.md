# Working with static secrets

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

## Create a new namespace for the demo app & the static secret CRDs

```shell
$ kubectl create ns app
$ kubectl apply -f vault/static-secrets/vault-kv-secret.yaml
$ kubectl apply -f vault/static-secrets/vault-kvv2-secret.yaml
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
