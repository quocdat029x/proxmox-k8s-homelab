#!/usr/bin/env bash
# Deploy Vault (docker-compose) + generate its self-signed TLS certificate
# on the target server (any docker host; paths assume a Synology-style layout).
#
# Credentials are prompted (read -rs), never passed as arguments, so they
# don't appear in the local process list.
set -euo pipefail

read -rp "SSH username: " username
read -rp "Server host   : " server
read -rsp "SSH/sudo password: " password
echo

# Generate the TLS cert ON THE SERVER (for a fully repo-tracked cert flow
# prefer RenewVaultCert.sh, which generates locally then deploys).
CertGen() {
  ssh "$username@$server" -p 2222 "openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
      -nodes -keyout /volume2/Data/vault/file/vault-key.pem \
      -out /volume2/Data/vault/file/vault-cert.pem \
      -subj \"/CN=192.168.1.254\" \
      -addext \"subjectAltName=IP:192.168.1.254\"
  "
}

DeployVault() {
  scp -r -p -O -P 2222 ./docker-compose.yaml "$username@$server":/volume2/Data/vault/
  scp -r -p -O -P 2222 ./volume2/Data/vault/* "$username@$server":/volume2/Data/vault/
  # sudo reads the password from stdin (-S); interactive ssh (-t) for the TTY.
  printf '%s\n' "$password" | ssh -t "$username@$server" -p 2222 \
    "sudo -S docker-compose -f /volume2/Data/vault/docker-compose.yaml up -d --force-recreate"
}

CertGen
DeployVault
