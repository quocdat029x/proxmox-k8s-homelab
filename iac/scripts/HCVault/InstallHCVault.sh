##!/usr/bin/env bash
# Input username, server and password each time you connect to. Another option is setup ssh key, however I am lazy.

function DeployVault() {
  scp -r -p -O -P 2222 ./docker-compose.yaml $username@$server:/volume2/Data/vault/
  scp -r -p -O -P 2222 ./volume2/Data/vault/* $username@$server:/volume2/Data/vault/
  ssh $username@$server -p 2222 "cd /volume2/Data/vault/ && echo $password | sudo -S docker-compose up -d --force-recreate"
}
function CertGen() {
  ssh $username@$server -p 2222 "openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
      -nodes -keyout /volume2/Data/vault/file/vault-key.pem \
      -out /volume2/Data/vault/file/vault-cert.pem \
      -subj "/CN=192.168.1.254" \
      -addext "subjectAltName=IP:192.168.1.254"
  "
}
CertGen
DeployVault
