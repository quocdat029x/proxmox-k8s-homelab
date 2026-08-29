#!/usr/bin/env bash
# kubectl access to the prod k8s API from the laptop, tunnelled through the bastion.
#
# The API server (control-plane :6443) lives on the internal network and is not
# reachable directly from the admin network. This script:
#   1. fetches /etc/kubernetes/admin.conf from the first control-plane (via the
#      ProxyJump ssh config produced by gen-ssh-config.sh),
#   2. rewrites its `server` to https://localhost:<port>,
#   3. opens an SSH local port-forward localhost:<port> -> <control-plane>:6443
#      through bastion (managed via an ssh control socket for clean stop/status).
#
# Usage:
#   ./k8s-tunnel.sh start [prod-dir] [local-port]   # default action (port defaults to 6443)
#   ./k8s-tunnel.sh status
#   ./k8s-tunnel.sh stop
#
# Prereq: run gen-ssh-config.sh first so `ssh <control-plane>` works via bastion,
# and `ssh-add` the key matching ./ssh/id_ed25519.pub.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_LOCAL_PORT=6443

CMD="${1:-start}"
PROD_DIR="${2:-$SCRIPT_DIR/../../iac/prod}"
LOCAL_PORT="${3:-$DEFAULT_LOCAL_PORT}"

KUBE_DIR="$HOME/.kube"
KUBECONF="$KUBE_DIR/prod.conf"
SOCKET="$KUBE_DIR/prod.tunnel.sock"

need_tf() {
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 1; }
  if command -v tofu >/dev/null 2>&1; then TF=tofu
  elif command -v terraform >/dev/null 2>&1; then TF=terraform
  else echo "ERROR: tofu or terraform is required." >&2; exit 1; fi
}

is_running() { [[ -S "$SOCKET" ]] && ssh -S "$SOCKET" -O check bastion >/dev/null 2>&1; }

show_use() {
  cat <<EOF

Kubeconfig : ${KUBECONF}
Tunnel     : localhost:${LOCAL_PORT} -> control-plane:6443 (via bastion)

Use:
  export KUBECONFIG=${KUBECONF}
  kubectl get nodes

Manage:
  $(basename "$0") status
  $(basename "$0") stop
EOF
}

start() {
  need_tf
  PROD_DIR="$(cd "$PROD_DIR" 2>/dev/null && pwd)" || { echo "ERROR: prod dir not found: $PROD_DIR" >&2; exit 1; }
  mkdir -p "$KUBE_DIR"; chmod 700 "$KUBE_DIR"

  if is_running; then
    echo "Tunnel already up (socket $SOCKET)."
    show_use
    return
  fi

  echo "Reading outputs from $PROD_DIR ..."
  local out cp_name cp_ip
  out="$("$TF" -chdir="$PROD_DIR" output -json)"
  cp_name=$(echo "$out" | jq -r '.control_plane_nodes.value[0].name')
  cp_ip=$(echo "$out"   | jq -r '.control_plane_nodes.value[0].ip')
  [[ -n "$cp_name" && "$cp_name" != "null" && -n "$cp_ip" && "$cp_ip" != "null" ]] \
    || { echo "ERROR: no control-plane node in output. Run gen-ssh-config.sh and 'tofu output'." >&2; exit 1; }

  echo "Fetching kubeconfig from ${cp_name} (via bastion; needs passwordless sudo on ubuntu)..."
  # Rewrite server -> localhost:<port> (the tunnel endpoint), drop the CA, and enable
  # insecure-skip-tls-verify. The API server cert SAN is the control-plane's real
  # hostname/IP, not "localhost", so verification against localhost would fail.
  # kubectl forbids specifying a CA together with the insecure flag, so we remove
  # certificate-authority-data. The SSH tunnel leg is already encrypted; localhost
  # traffic does not leave the laptop.
  ssh -o BatchMode=no "$cp_name" 'sudo cat /etc/kubernetes/admin.conf' \
    | sed -E 's#(server:[[:space:]]*)https://[^:]+:[0-9]+#\1https://localhost:'"$LOCAL_PORT"'#' \
    | awk '
        /certificate-authority(-data)?:/ { next }
        { print }
        /^[[:space:]]*server: https:\/\/localhost/ && !d { print "    insecure-skip-tls-verify: true"; d=1 }
      ' \
    > "$KUBECONF"
  chmod 600 "$KUBECONF"

  echo "Opening tunnel localhost:${LOCAL_PORT} -> ${cp_name} (${cp_ip}:6443) via bastion..."
  # -M master, -S control socket, -fN background no-command, -L local forward.
  ssh -fN -M -S "$SOCKET" \
      -o ExitOnForwardFailure=yes \
      -L "${LOCAL_PORT}:${cp_ip}:6443" bastion

  echo "Tunnel up (socket $SOCKET)."
  show_use
}

stop() {
  if is_running; then
    ssh -S "$SOCKET" -O exit bastion >/dev/null 2>&1 || true
    echo "Tunnel stopped."
  else
    echo "Tunnel not running."
  fi
  rm -f "$SOCKET"
}

status() {
  if is_running; then
    echo "Tunnel: UP (socket $SOCKET)"
  else
    echo "Tunnel: down"
  fi
  if [[ -f "$KUBECONF" ]]; then
    echo "Kubeconfig: $KUBECONF (server: $(grep -E '^[[:space:]]*server:' "$KUBECONF" | head -1 | xargs))"
  else
    echo "Kubeconfig: not generated (run '$(basename "$0") start')"
  fi
}

case "$CMD" in
  start)  start ;;
  stop)   stop ;;
  status) status ;;
  *) echo "Usage: $(basename "$0") {start|stop|status} [prod-dir] [local-port]" >&2; exit 1 ;;
esac
