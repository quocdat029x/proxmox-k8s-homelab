#!/bin/bash

# Script to get ArgoCD password and save into Vault

CONTROL_PLANE_IP=$${control_plane_ip}
SSH_KEY_PATH=$${kubespray_data_dir}/id_rsa
VAULT_ADDR=$${vault_addr}
VAULT_TOKEN=$${vault_token}
SECRET_PATH=$${secret_path}

# Get ArgoCD password from Kubernetes
ARGOCD_PASSWORD=$(ssh -i "$SSH_KEY_PATH" ubuntu@"$CONTROL_PLANE_IP" "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d" 2>/dev/null)

if [ -n "$ARGOCD_PASSWORD" ]; then
    echo "Retrieved ArgoCD password successfully"
else
    echo "Failed to get ArgoCD password"
    exit 1
fi

# Save to Vault using Vault API
curl -s --header "X-Vault-Token: $VAULT_TOKEN" \
    --request POST "$VAULT_ADDR/v1/$SECRET_PATH" \
    --data "{ \"data\": { \"password\": \"$ARGOCD_PASSWORD\" } }" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "Saved ArgoCD password to Vault at: $SECRET_PATH"
else
    echo "Failed to save in Vault"
    exit 1
fi
