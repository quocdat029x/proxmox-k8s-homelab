You have to change the docker entrypoint command like below to use a custom vault.hcl file.
> vault server -config=/vault/vault.hcl

Example docker-compose.yaml file (vault.hcl file resides inside /home/volumes/vault/)

```yaml
version: "3.8"
services:
  vault:
   image: hashicorp/vault
   container_name: vault
   environment:
      VAULT_ADDR: http://127.0.0.1:8200
   ports:
      - "8200:8200"
   volumes:
      - ./volume2/Data/vault/:/vault/:rw
   cap_add:
      - IPC_LOCK
   entrypoint: vault server -config=/vault/vault.hcl
```

# Minimal example configuration
## 1. Create a directory for storing the server data.
> mkdir /volume2/Data/vault

## 2. Generate keypem
Use openssl to generate a self-signed TLS certificate and key for the server to use, and write them to the files ./volume2/Data/vault-cert.pem and ./volume2/Data/vault-key.pem.
```shell
openssl req -x509 -newkey rsa:4096 -sha256 -days 365 \
    -nodes -keyout ./volume2/Data/vault/file/vault-key.pem -out ./volume2/Data/vault/file/vault-cert.pem \
    -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
```

## 3. Create a basic server configuration file
```shell
cat > ./volume2/Data/vault/vault.hcl << EOF
api_addr                = "https://127.0.0.1:8200"
cluster_addr            = "https://127.0.0.1:8201"
cluster_name            = "learn-vault-cluster"
disable_mlock           = true
ui                      = true

listener "tcp" {
address       = "127.0.0.1:8200"
tls_cert_file = "./volume2/Data/vault-cert.pem"
tls_key_file  = "./volume2/Data/vault-key.pem"
}

backend "raft" {
path    = "./volume2/Data/vault"
node_id = "learn-vault-server"
}
EOF

```