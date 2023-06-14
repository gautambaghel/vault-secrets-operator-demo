# Working with PKI certificates


## Create the initial k8s setup

```sh
kubectl create ns testing
kubectl create secret generic pki1 -n testing
```

## Configure Vault

```sh
kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh

vault secrets enable -path=pki pki

vault write pki/roles/secret -<<EOF
{
  "ttl": "3600",
  "allow_ip_sans": true,
  "key_type": "rsa",
  "key_bits": 4096,
  "allowed_domains": ["example.com"],
  "allow_subdomains": true,
  "allowed_uri_sans": ["uri1.example.com", "uri2.example.com"]
}
EOF

vault write pki/root/generate/internal \
  common_name="Root CA" \
  ttl="315360000" \
  format="pem" \
  private_key_format="der" \
  key_type="rsa" \
  key_bits=4096 \
  exclude_cn_from_sans=true \
  ou="My OU" \
  organization="My organization"

vault auth enable -path demo-pki kubernetes

vault write auth/demo-pki/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    disable_iss_validation=true

vault write auth/demo-pki/role/pki-role -<<EOF
{
  "bound_service_account_names": ["default"],
  "bound_service_account_namespaces": ["testing"],
  "token_ttl": 3600,
  "token_policies": ["pki-dev"],
  "audience": "vault"
}
EOF

vault policy write pki-dev -<<EOF
path "pki/*" {
  capabilities = ["read", "create", "update"]
}
EOF
```

## Deploy sample app & PKI secret CRD

```sh
kubectl apply -f vault/pki/.
```

## Verify the PKI certs were created

```sh
# PKI certs should be created as a k8s secret
kubectl get secret pki1 -n testing -o json | jq -r .data._raw | base64 -D

# PKI certs should be available in the pod
kubectl exec deployment/vso -n testing -- cat /etc/secrets/_raw
```