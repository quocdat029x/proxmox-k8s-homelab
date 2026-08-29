# Exposing Kubernetes Apps to the Internet

How applications running in the prod k8s cluster are exposed to the public internet
through Cloudflare, the Mikrotik router, Nginx Proxy Manager (NPM), and Caddy on the
bastion. Verified working 2026-08-10 with a `whoami` demo app (`HTTP 200`).

## Topology

```
                       Internet
                          │
                          ▼
                    Cloudflare (*.example.com, Full/Strict)
                          │
                          ▼  A record → <your-public-ip> (router public IP)
   ┌──────────────── MIKROTIK ROUTER ────────────────────┐
   │  VLAN40-Server  192.168.1.0/24 (gw .1)              │
   │  dst-nat: public:443 → 192.168.1.253 (NPM)          │
   │  NOTE: router does NOT route to 10.0.1.0/24         │
   └──────────────────────┬──────────────────────────────┘
                          │ 192.168.1.0/24 (Server VLAN)
        ┌─────────────────┴──────────────────┐
        ▼                                     ▼
  NPM (.253)                            BASTION (.40)  ← dual-homed, ONLY bridge
  Nginx Proxy Manager                   eth0: 192.168.1.40  (Server VLAN)
  edge reverse proxy                    eth1: 10.0.1.40     (k8s private VNET)
  routes by hostname                    runs Caddy → 10.0.1.88
        │                                     │
        │   host: promox.*  → Proxmox .237    │  (ip_forward=0, Caddy bridges HTTP)
        │   host: k8s.*      ─────────────────┘
        ▼                                     ▼
                                  10.0.1.0/24 (k8s private VNET, unrouted)
                                  CP .20-.22 | workers .30-.32
                                  ingress-nginx on MetalLB VIP 10.0.1.88
                                            │
                                            ▼  route by Host header → Service → Pod
```

**Key constraint:** the k8s VNET (`10.0.1.0/24`) is isolated from the Mikrotik. The
**bastion is the only dual-homed host** bridging the two networks. NPM (`.253`) cannot
reach `10.0.1.88` directly — it must proxy through Caddy on the bastion.

## The verified request path

```
Client → Cloudflare (TLS, *.example.com)
  → <your-public-ip>:443
  → Mikrotik dst-nat 443 → 192.168.1.253 (NPM)
  → NPM Proxy Host <host>.example.com → http://192.168.1.40:80 (Caddy, bastion)
  → Caddy reverse_proxy → 10.0.1.88:80 (ingress-nginx VIP)
  → Ingress rule (host match) → Service → Pod
```

Header evidence from a live request:
- `Cf-Ray` / `Cf-Connecting-Ip` — Cloudflare edge
- `Via: 1.1 Caddy` — Caddy on the bastion
- `X-Forwarded-Host` — ingress-nginx
- `Hostname: whoami-<pod>` — the actual pod

## Components

| Component | Address | Role |
|-----------|---------|------|
| Cloudflare | — | Edge TLS, DDoS, DNS (`*.example.com`) |
| Mikrotik router | 192.168.1.1 / 10.0.1.1-gw-not-routed | dst-nat 443 → NPM; firewall |
| NPM (Nginx Proxy Manager) | 192.168.1.253 | Edge L7 reverse proxy, hostname routing, TLS (wildcard cert) |
| Bastion | 192.168.1.40 + 10.0.1.40 | SSH jump host + Caddy bridge to k8s VNET |
| Caddy (on bastion) | listens :80, :443 | `reverse_proxy 10.0.1.88:80` |
| ingress-nginx | MetalLB VIP 10.0.1.88 | k8s ingress, routes by Host to Services |
| Proxmox VE | 192.168.1.237:8006 | Hypervisor UI (served via NPM at `promox.example.com`) |

## How to expose a new app

1. **Cloudflare** — add A record `<name>.example.com` → `<your-public-ip>`, proxied (orange cloud).
2. **NPM** (`https://promox.example.com` or `https://192.168.1.253:81`) — add Proxy Host:
   - Domain: `<name>.example.com`
   - Forward Hostname/IP: `192.168.1.40`
   - Forward Port: `80`
   - SSL tab → select the `*.example.com` certificate, enable **Force SSL**.
3. **k8s** — deploy app + Service + Ingress:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: myapp
     namespace: myapp
     annotations:
       nginx.ingress.kubernetes.io/ssl-redirect: "false"   # path is HTTP NPM→Caddy→ingress
   spec:
     ingressClassName: nginx
     rules:
     - host: <name>.example.com
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service: { name: myapp, port: { number: 80 } }
   ```

No Mikrotik or Caddy change needed — those are shared across all apps.

## Caddy config on the bastion

`/etc/caddy/Caddyfile` (the running, verified config):

```caddyfile
:443 {
    tls /etc/caddy/cert.pem /etc/caddy/key.pem   # self-signed; Cloudflare "Full" accepts it
    log {
        output file /var/log/caddy/access.log
    }
    reverse_proxy 10.0.1.88:80 {
        header_up Host {http.request.host}        # preserve Host for ingress routing
    }
}

:80 {
    log {
        output file /var/log/caddy/access.log
    }
    reverse_proxy 10.0.1.88:80 {
        header_up Host {http.request.host}
    }
}
```

The self-signed cert was generated with:
```bash
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /etc/caddy/key.pem -out /etc/caddy/cert.pem -days 3650 \
  -subj "/CN=ingress-bastion" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:192.168.1.40,IP:10.0.1.40"
```

> Note: `iac/modules/kubespray/ansible/expose_service.yaml` installs Caddy but writes a
> simpler Caddyfile (`:80, :443 { reverse_proxy 10.0.1.88:80 }`) that lacks TLS cert +
> Host preservation. Align the playbook with the config above when it is next run.

## Mikrotik dst-nat rules (reference)

```routeros
/ip firewall nat
# Only the app-exposure rule you need for this stack:
add action=dst-nat chain=dstnat dst-address-list=DDNS dst-port=443 protocol=tcp to-addresses=192.168.1.253   # edge proxy
# Forward any other service (VPN, NAS sync, ...) at your own risk — every extra
# dst-nat widens your home network's attack surface.
```

The forward chain ends with a catch-all drop, so each dst-nat also needs a matching
`chain=forward action=accept` rule.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `HTTP 525` (Cloudflare) | NPM has no cert for that hostname | Assign `*.example.com` cert on the Proxy Host's SSL tab |
| `HTTP 404` (nginx page) | Ingress reached, but no Ingress rule for the host | Create the Ingress with matching `host:` |
| `HTTP 502/504` (NPM) | NPM can't reach bastion:80 | Check Caddy running on bastion, UFW/forward rules |
| `HTTP 000` from outside | Laptop IP blocked (CF-only firewall) or dst-nat missing | Test through Cloudflare, not the raw public IP |
| Domain shows Proxmox UI | Traffic is going to NPM→Proxmox, not your app | The hostname's NPM Proxy Host is wrong/missing |

To debug the chain, check the Caddy access log on the bastion:
`sudo tail -f /var/log/caddy/access.log` — if a request is absent, it never reached the bastion.

## Known gaps

- **No StorageClass / CSI** — stateful apps (databases, PVC) will hang `Pending`. Install
  `local-path-provisioner` or Longhorn before deploying apps that need persistence.
- **cert-manager not installed** — not required for the exposed path (NPM handles TLS with
  the wildcard cert), but needed if apps want in-cluster TLS.
- **Bastion UFW is inactive** — all ports open on the Server VLAN. For prod hardening,
  enable UFW allowing only 22/80/443.
- **MetalLB pool is a single IP** (`10.0.1.88/32`) consumed by ingress-nginx — fine for the
  Ingress-based exposure model; only a problem if apps need their own `type: LoadBalancer`.
