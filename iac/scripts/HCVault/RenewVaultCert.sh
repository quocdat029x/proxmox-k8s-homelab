#!/usr/bin/env bash
#
# Renew Vault TLS certificate (self-signed).
#
# Repo is the source of truth: cert is generated LOCALLY first (so the file in
# the repo and the file on the Vault server always match → Terraform TLS verify
# keeps working). With --deploy the new cert is then pushed to the Vault server
# and the Vault container is restarted.
#
# Why not run CertGen() on the server? Because that would produce a DIFFERENT
# cert than the one in the repo, and Terraform (ca_cert -> repo file) would
# reject it with a TLS mismatch.
#
# Usage:
#   USERNAME=<ssh_user> ./RenewVaultCert.sh [--deploy] [options]
#
# Env vars (override on the command line):
#   USERNAME   (required for --deploy) SSH user for the Vault server
#   SERVER     Vault server host                  default: 192.168.1.254
#   SSH_PORT   SSH port                           default: 2222
#   CERT_DAYS  Cert validity in days              default: 3650
#   CERT_CN    Common Name (+ SAN IP)             default: 192.168.1.254
#
# Flags:
#   --deploy    Push cert to server + restart Vault
#   --help,-h   Show this help
#
# Examples:
#   # Just regenerate the cert in the repo (no deploy)
#   ./RenewVaultCert.sh
#
#   # Regenerate + deploy to Vault server
#   USERNAME=admin ./RenewVaultCert.sh --deploy
#
set -euo pipefail

# ---- Config (env-overridable) ------------------------------------------------
USERNAME="${USERNAME:-}"
SERVER="${SERVER:-192.168.1.254}"
SSH_PORT="${SSH_PORT:-2222}"
CERT_DAYS="${CERT_DAYS:-3650}"
CERT_CN="${CERT_CN:-192.168.1.254}"

# ---- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_FILE="${SCRIPT_DIR}/volume2/Data/vault/file/vault-cert.pem"
KEY_FILE="${SCRIPT_DIR}/volume2/Data/vault/file/vault-key.pem"
REMOTE_DIR="/volume2/Data/vault/file"

# ---- Args --------------------------------------------------------------------
usage() {
  cat <<'EOF'
Renew Vault TLS certificate (self-signed).

Repo is the source of truth: cert is generated LOCALLY first (so the file in
the repo and the file on the Vault server always match -> Terraform TLS verify
keeps working). With --deploy the new cert is pushed to the Vault server and
the Vault container is restarted.

Usage:
  USERNAME=<ssh_user> ./RenewVaultCert.sh [--deploy]

Env vars:
  USERNAME   (required for --deploy) SSH user for the Vault server
  SERVER     Vault server host                  default: 192.168.1.254
  SSH_PORT   SSH port                           default: 2222
  CERT_DAYS  Cert validity in days              default: 3650
  CERT_CN    Common Name (+ SAN IP)             default: 192.168.1.254

Flags:
  --deploy    Push cert to server + restart Vault
  --help,-h   Show this help

Examples:
  ./RenewVaultCert.sh                            # regenerate cert in repo only
  USERNAME=admin ./RenewVaultCert.sh --deploy    # regenerate + deploy to server
EOF
}

DEPLOY=0
for arg in "$@"; do
  case "$arg" in
    --deploy) DEPLOY=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage; exit 1 ;;
  esac
done

# ---- 1. Generate cert locally -----------------------------------------------
echo "==> Generating new Vault cert (CN=${CERT_CN}, validity=${CERT_DAYS} days)..."
openssl req -x509 -newkey rsa:4096 -sha256 -days "${CERT_DAYS}" \
  -nodes \
  -keyout "${KEY_FILE}" \
  -out "${CERT_FILE}" \
  -subj "/CN=${CERT_CN}" \
  -addext "subjectAltName=IP:${CERT_CN}" 2>/dev/null

chmod 600 "${KEY_FILE}"
chmod 644 "${CERT_FILE}"

echo "==> New cert written to repo:"
echo "    ${CERT_FILE}"
echo "    ${KEY_FILE}"
openssl x509 -in "${CERT_FILE}" -noout -subject -issuer -dates

# ---- 2. Deploy (optional) ----------------------------------------------------
if [ "${DEPLOY}" -eq 1 ]; then
  if [ -z "${USERNAME}" ]; then
    echo "ERROR: USERNAME env var is required for --deploy" >&2
    echo "   e.g. USERNAME=admin $0 --deploy" >&2
    exit 1
  fi

  echo ""
  echo "==> Uploading cert to ${USERNAME}@${SERVER}:${SSH_PORT}:${REMOTE_DIR}/ ..."
  # -O = use legacy SCP protocol (OpenSSH 9+ defaults to SFTP, which Synology/older
  # servers reject with "subsystem request failed on channel 0").
  scp -O -P "${SSH_PORT}" "${CERT_FILE}" "${USERNAME}@${SERVER}:${REMOTE_DIR}/vault-cert.pem"
  scp -O -P "${SSH_PORT}" "${KEY_FILE}"   "${USERNAME}@${SERVER}:${REMOTE_DIR}/vault-key.pem"

  echo "==> Restarting Vault container (needs sudo on the server)..."
  # -t allocates a TTY so the remote `sudo` can prompt for its password.
  # You will be asked for: (1) SSH password, (2) sudo password.
  ssh -t "${USERNAME}@${SERVER}" -p "${SSH_PORT}" \
    "cd /volume2/Data/vault/ && sudo docker-compose restart vault"

  echo "==> Verifying cert on server..."
  ssh "${USERNAME}@${SERVER}" -p "${SSH_PORT}" \
    "openssl x509 -in ${REMOTE_DIR}/vault-cert.pem -noout -subject -dates"

  echo ""
  echo "==> Deploy complete. Now run:"
  echo "    cd iac/prod && terraform plan"
else
  echo ""
  echo "==> Cert replaced in repo only. To deploy:"
  echo "    USERNAME=<ssh_user> $0 --deploy"
fi

echo ""
echo "==> Done."
