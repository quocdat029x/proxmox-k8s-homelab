# Architecture

What this repo builds, module by module, and how traffic reaches your apps.

## Provisioning flow

1. **Plan time** — the `vault` module reads two KV-v2 secrets:
   `proxmox/terraform-prov` (Proxmox API creds) and `proxmox/infra-<env>-tfvars`
   (subnets, bastion SSH params, root domain, base64 SSH key). Nothing secret
   is ever read from the repo itself.
2. **Template** — `vm_template` downloads the Ubuntu noble cloud image and
   builds a cloneable template VM.
3. **VMs** — the `vm` module clones 3 control-plane nodes (.20–.22) and
   3 workers (.30–.32) on the isolated bridge `vmbr1` (10.0.1.0/24);
   `bastion_host` clones the dual-homed bastion (management + k8s VLAN).
   Each VM gets a cloud-init snippet (`user-data` module) and a
   `random_password` persisted to Vault (`vm_secret` module, `prevent_destroy`).
4. **Cluster install** — `kubespray` module runs `remote-exec` (SSH through the
   bastion) on the deployer VM: writes templated `inventory.ini` /
   `k8s-cluster.yml` / `addons.yml`, then runs the Kubespray container
   (`ansible-playbook cluster.yml`), saves the generated ArgoCD admin password
   to Vault, and sets up Caddy.
5. **Vault config** — the separate `iac/vault-config` root provisions the KV
   engine, a read-only policy, and an AppRole that external-secrets (ESO) uses
   inside the cluster. Kubernetes auth is intentionally avoided when the Vault
   host can't reach the k8s API.

## Module map

| Module | Responsibility |
|---|---|
| `iac/modules/pool` | Proxmox resource pools |
| `iac/modules/vault` | KV-v2 data readers (creds + infra values) |
| `iac/modules/vm_template` | Cloud image download + template VM |
| `iac/modules/vm` | Cloned VM factory: `cidrhost()` addressing, cloud-init, Vault-backed password |
| `iac/modules/kubespray` | Deployer VM + Kubespray run + addon templating |
| `iac/modules/bastion_host` | Dual-NIC bastion (vmbr0 + vmbr1) |
| `iac/modules/user-data` | Per-VM cloud-init snippet (user, ssh key, qemu-agent) |
| `iac/modules/vm_secret` | `random_password` + `vault_kv_secret_v2` per VM |

IP allocation convention: `cidrhost(subnet, vm_host_number + vm_host_offset + count.index)`
— offsets keep node groups in predictable ranges (CP .20+, workers .30+,
bastion .40+, deployer .10+).

## Traffic path (internet → pod)

```
Client → Cloudflare (TLS)
  → home router dst-nat :443 → edge proxy (192.168.1.253)
  → edge proxy by hostname → Caddy on bastion :80
  → Caddy reverse_proxy → ingress-nginx MetalLB VIP (10.0.1.88)
  → Ingress host rule → Service → Pod
```

The bastion is the **only** dual-homed host between the server VLAN and the
unrouted k8s VNET; `ip_forward=0`, Caddy bridges HTTP. Detailed walkthrough
with header evidence: [expose-architecture.md](expose-architecture.md).

## Admin access

- `scripts/admin/gen-ssh-config.sh` — generates `~/.ssh/config.d/proxmox-k8s.conf`
  (bastion entry + `ProxyJump` for every node; agent forwarding, no key on bastion).
- `scripts/admin/k8s-tunnel.sh` — fetches `admin.conf`, rewrites the API server
  to `localhost:<port>`, maintains an SSH master connection through the bastion.

## Risky areas (known, by design or debt)

- `remote-exec` chain requires bastion + Vault + NAS up during apply (~45 min).
- `sleep 30` waits before SSH (cloud-init race on slow hosts).
- Kubespray image pin + in-container patch of an upstream ArgoCD bug
  (`install_kubernetes.sh`) — revisit on Kubespray upgrades.
- `ignore_changes = [initialization]` on VMs hides manual cloud-init drift.

## Learning path

- `docs/expose-architecture.md` — full exposure chain, verified end-to-end.
- `docs/labs/` — hardening walkthroughs (config hardening, module-by-module notes).
