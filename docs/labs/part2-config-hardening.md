# Part 2 v2 — Enterprise Config Hardening on `k8s-prod-cantho-01`

> **Cho:** Dat Quoc Nguyen · Senior DevOps / SRE — ôn phỏng vấn NAB
> **Khác gì bản v1:** bản này viết dựa trên **cluster thật đã survey**, không phải giả định.
> Sửa distro (kubespray, không phải k3s), sửa secret backend (Vault trên NAS, không phải AWS
> Secrets Manager), bỏ demo IMDS không tồn tại, thêm 5 module thiếu, và sửa các chỗ sẽ làm vỡ
> homelab. Chi tiết ở §2.
> **Nguyên tắc:** plan này **không** chứa manifest hoàn chỉnh. Anh tự viết YAML — đó là phần
> học. Snippet chỉ xuất hiện ở chỗ cần chỉ rõ cái gì bản cũ viết sai.

**Module list:** [M0 → M8](part2-modules-m0-m8.md) · [M9 → M15](part2-modules-m9-m15.md)

---

## 0. Cluster thật (verified 2026-07-30)

| Hạng mục | Thực tế | Ảnh hưởng tới lab |
|---|---|---|
| Distro | **kubespray** (kubeadm bên dưới), k8s v1.32.3, containerd 2.0.5 | M0 đi qua Ansible vars, **không** sửa tay static pod |
| Control plane | 3 node `10.0.1.20/.21/.22`, stacked etcd | etcd quorum lab được thật → M15 |
| Worker | 3 node `10.0.1.30/.31/.32` · 3.4 CPU + 7Gi allocatable · **chỉ ~12G disk free** | PVC đẩy hết ra NAS; Prometheus retention ngắn |
| CNI | **Calico** (đã có sẵn) | NetworkPolicy egress enforce được; có cả `GlobalNetworkPolicy` |
| kube-proxy | **IPVS** | câu hỏi iptables vs IPVS |
| Ingress | ingress-nginx DaemonSet, hostPort 80/443, IngressClass `nginx` | có sẵn → M10 dùng `trafficRouting.nginx` |
| | cờ `--watch-ingress-without-class=true` | **finding thật** → sửa ở M6 |
| | `externalTrafficPolicy: Cluster` | mất client IP → PROXY protocol |
| LoadBalancer | MetalLB v0.13.9 L2, pool `primary` = **1 IP** `10.0.1.88/32` | 1 VIP, routing toàn bộ ở L7 |
| Storage | **chưa có StorageClass** | Part 0 phải dựng |
| NAS | `192.168.1.254` — NFS `/volume2/k8s_data` **và** Vault `:8200` | M4 + M6 xoay quanh cái này |
| Secrets | Vault (Docker trên NAS, HTTPS self-signed CA, KV v2 path `proxmox`) | M4 = Vault + ESO |
| ESO | cấu hình sẵn trong git (v0.17.0, Vault **Kubernetes auth**) — **chưa deploy** | |
| GitOps | ArgoCD Running 130d, **0 Application** | M11 bootstrap |
| DNS | `example.com` @ Cloudflare · public IP `<your-public-ip>` (Viettel) | |
| Bastion | `192.168.1.40` + `10.0.1.40`, trống port 80/443 | L4 proxy hop |
| kubeadm certs | hết hạn **2027-03-21** (còn 234d), CA 2036 | không gấp; vẫn drill ở M14 |
| kubespray vars | `kube_encrypt_secret_data: false` · `kubernetes_audit: false` | ← M0 chỉ cần đổi 2 dòng này |

**Trạng thái app: rỗng.** Toàn cluster chỉ có ArgoCD, ingress-nginx, calico, coredns,
metrics-server, metallb + `deploy/hello-world` (rác 130 ngày đang giữ VIP). **Không có
podinfo / postgres / redis.** Nên Part 1 phải làm trước — xem §3.

---

## 1. Ranh giới thật (đã sửa lại cho đúng)

Bản v1 xếp "HA control plane / etcd quorum" vào loại không lab được. Sai — anh có 3 control
plane stacked etcd, đó là **lợi thế lớn nhất** của anh so với ứng viên dùng EKS.

| ❌ Không tái tạo được ở nhà | ✅ Lab được **vì anh tự quản** (ứng viên EKS không đụng tới) | ✅ Config-bound — Part 2 làm hết |
|---|---|---|
| Multi-AZ vật lý (zone thật) | Secrets **encryption at rest** ở etcd | Policy-as-code (PSA + Kyverno) |
| DR đa-region | **Audit logging** + shipping | RBAC least-privilege, SA-per-workload |
| PrivateLink / dedicated tenancy | **etcd quorum loss drill** (tắt 1 vs 2 CP) | Zero-trust NetworkPolicy in/egress |
| Cloud autoscaler thật (Karpenter) | **etcd snapshot backup + restore** | Supply chain: cosign + trivy gate + SBOM |
| Managed control-plane patching | **Cluster upgrade drill** (kubespray) | Secrets: Vault + ESO, không plaintext |
| | **Cert rotation** (`kubeadm certs renew`) | Quota / LimitRange / PriorityClass |
| | **kube-bench control-plane checks** (N/A trên EKS) | PDB + topologySpread + graceful shutdown |
| | | Progressive delivery (canary + auto-rollback) |
| | | GitOps hardening + CI policy gate |
| | | Velero backup + restore drill |

**Câu chốt dùng trong interview:**
> *"Tôi tự quản control plane trên Proxmox, nên tôi enforce được cả những thứ EKS làm hộ:
> secrets encryption at rest, audit policy, etcd snapshot/restore, và upgrade drill. Phần
> duy nhất tôi không tái tạo được là multi-AZ vật lý. Ở NAB thì EKS lo lớp đó, còn kỷ luật
> config thì giống hệt — và tôi biết chính xác cái gì đang được làm hộ mình."*

---

## 2. Đã sửa gì so với bản v1

**Ba chỗ đủ sức làm vỡ homelab:**

| Chỗ | Bản v1 | Đã sửa |
|---|---|---|
| M2 Kyverno | `ClusterPolicy` + `Enforce` toàn cluster, không exclude ns hệ thống | Bắt buộc exclude `kube-system`/`metallb-system`/`ingress-nginx`/`argocd`/`cert-manager`/`kyverno`. Không exclude thì `calico-node`/`coredns` **không tạo lại được** khi bị reschedule → mất CNI, mà cluster vẫn "xanh" lúc apply |
| M2 registry | allowlist chỉ `ghcr.io` + ECR | Anh không có ECR, app pull từ `docker.io` → allowlist phải khớp registry thật |
| M13 Velero drill | `kubectl delete ns` để test restore, nằm ở module cuối | DB phải trên `nfs-csi-retain`; với `Delete` thì xoá ns = **CSI xoá thật data trên NAS**. Và M13 phải chạy **trước** mọi drill phá hoại |

**Tám lỗi kỹ thuật:**

| # | Sửa gì |
|---|---|
| 1 | M0: cluster là **kubespray**, không phải k3s. Sửa tay static pod manifest sẽ **bị playbook ghi đè** → đi qua `kube_encrypt_secret_data` + `kubernetes_audit` (đã tìm thấy trong repo, cả hai đang `false`) |
| 2 | M2: `spec.validationFailureAction` **deprecated từ Kyverno 1.12** → `spec.rules[].validate.failureAction` |
| 3 | M3: khối `verifyImages` của v1 **không parse được** (block scalar `\|-` trong flow mapping, `}` lạc dòng) → viết block style, và dùng `keyless` thay `publicKeys` |
| 4 | M3: `cosign sign <ecr>/...` — anh không có ECR và **không ký được image người khác build** → tự build 1 image nhỏ, push ghcr.io, ký keyless OIDC |
| 5 | M4: AWS Secrets Manager + IRSA → **Vault trên NAS + ESO Kubernetes auth** (repo đã cấu hình sẵn) |
| 6 | M6: v1 bảo "cài Calico nếu chưa có" — **đã có**. Và demo chặn IMDS `169.254.169.254` **không tồn tại trên Proxmox** → đổi mục tiêu sang chặn `192.168.1.0/24`, mở ngoại lệ ESO→Vault |
| 7 | M6: `ipBlock` với `except` mà thiếu `cidr` → không hợp lệ |
| 8 | M10: `canary.steps` không có `trafficRouting` → Rollouts chỉ xấp xỉ weight **bằng số pod** (`replicas: 4` ⇒ 20% thực tế là 25%). Có ingress-nginx sẵn → khai `trafficRouting.nginx` mới là canary thật |

Thêm: v1 dạy "pin digest, cấm `:latest`" nhưng **cài mọi thứ bằng `releases/latest/download/`** —
tự mâu thuẫn, phải pin version.

**Năm module thêm mới:** M1 PSA (v1 bỏ hẳn) · M9 Observability (M10 phụ thuộc nó mà v1 không
dựng) · M13 phần **etcd snapshot** (Velero **không** backup etcd) · M14 Upgrade & cert rotation ·
M15 Failure drills gồm etcd quorum.

**Quota (M7):** v1 đặt `requests.cpu: 4` / `8Gi` — gần trọn **một** node của anh (3.4 CPU / 7Gi
allocatable). Đã ghi chú scale xuống.

---

## 3. Part 0 — Nền móng (BẮT BUỘC, vì cluster đang rỗng)

Không phải Part 2, nhưng Part 2 không chạy được nếu thiếu. Ước lượng ~6-8h.

1. **Giải phóng VIP** — `svc/hello-world-service` (ns `default`) đang giữ `10.0.1.88`, nên
   ingress-nginx `<pending>`. Tự chẩn đoán trước (`describe svc`, log
   `metallb-system/controller`, `get ipaddresspool -A`) rồi patch nó về `ClusterIP`.
2. **StorageClass** — cài `csi-driver-nfs` v4.11 + 2 class trỏ `192.168.1.254:/volume2/k8s_data`:
   `nfs-csi` (`reclaimPolicy: Delete`) và `nfs-csi-retain` (`Retain`), cả hai
   `volumeBindingMode: WaitForFirstConsumer`, **không set default class**. Manifest có sẵn
   trong `InfrastructureGitOps/gitops/prod/argocd/manifests/nfs/`.
   → Trên NAS: Control Panel → Shared Folder → NFS Permissions cho `10.0.1.0/24` rw.
3. **cert-manager** + 2 ClusterIssuer Let's Encrypt (**staging trước**), **DNS-01 qua
   Cloudflare** — chọn DNS-01 vì không cần inbound port 80, nên cert vẫn cấp được kể cả khi
   Viettel chặn hoặc CGNAT.
4. **external-dns** — giới hạn blast radius: `--domain-filter=lab.example.com`,
   `--txt-owner-id=lab` (khác `homelab-prod` đang có trong repo), `--cloudflare-proxied=false`.
5. **App 3 tầng** (`web` nginx-unprivileged → `api` PostgREST → `postgres` StatefulSet trên
   `nfs-csi-retain`). Image public, không cần build. ⚠️ Trên NFS, `PGDATA` **phải** là
   subdirectory (`/var/lib/postgresql/data/pgdata`) — trỏ thẳng mountpoint là Postgres fail
   vì `lost+found`/permission.
6. **Expose** — check CGNAT **trước tiên** (so `<your-public-ip>` với WAN IP trong admin router
   `192.168.1.1`; khác nhau ⇒ CGNAT ⇒ phải dùng Cloudflare Tunnel). Rồi nginx `stream` trên
   bastion (L4 + `proxy_protocol`) → VIP, và `use-proxy-protocol: "true"` phía ingress.

✅ **Cổng vào Part 2:** `curl https://pay.lab.example.com` từ 4G ra 200 + cert hợp lệ,
và log ingress hiện IP client thật (không phải `10.0.1.40`).

---

## 4. Thứ tự module (có phụ thuộc — đừng đảo)

```
Part 0 ─→ M0 control-plane
            ↓
   M1 PSA(audit) → M2 Kyverno(Audit) → sửa app compliant → M2(Enforce)
            ↓
   M3 supply chain → M4 secrets(Vault+ESO) → M5 RBAC → M6 network → M7 quota → M8 resilience
            ↓
   M9 observability ──→ M10 progressive delivery   (M10 CẦN M9)
            ↓
   M11 GitOps → M12 compliance scan
            ↓
   M13 backup+DR (etcd trước, Velero sau)   ← PHẢI xong trước mọi drill xoá namespace
            ↓
   M14 upgrade & cert rotation → M15 failure drills
```

Bẫy self-lockout của bản v1: nó bật Kyverno `Enforce` trước khi app compliant, và để backup ở
module cuối trong khi các drill phá hoại nằm phía trên.

Chi tiết từng module: [M0 → M8](part2-modules-m0-m8.md) · [M9 → M15](part2-modules-m9-m15.md)

---

## 5. 🏁 Capstone — checklist "NAB-grade config"

- [ ] **M0** Secret encrypt at rest (chứng minh bằng `etcdctl`, không chỉ tin `kubectl`) · audit log bật **và ship ra ngoài node** · qua kubespray vars, không sửa tay
- [ ] **M1** PSA `restricted` enforce · securityContext hardened đủ 6 trường
- [ ] **M2** Kyverno Audit→Enforce, **có exclude ns hệ thống**, allowlist khớp registry thật, `failureAction` đúng chỗ, ≥1 mutate rule
- [ ] **M3** image tự build distroless non-root, ký **cosign keyless OIDC**, Kyverno `verifyImages` enforce, Trivy gate fail build
- [ ] **M4** Vault + ESO Kubernetes auth, không secret plaintext, `automountServiceAccountToken: false`, **biết và nói được** Vault SPOF
- [ ] **M5** RBAC least-privilege, không `cluster-admin` cho workload, `can-i` chứng minh
- [ ] **M6** default-deny in/egress, chặn `192.168.1.0/24` trừ ESO→Vault, DNS egress mở đúng, tắt `watch-ingress-without-class`
- [ ] **M7** Quota/LimitRange **khớp capacity thật** + PriorityClass
- [ ] **M8** PDB + spread + graceful, sống sót drain với 0 lỗi 5xx, có fake zone label
- [ ] **M9** Prometheus + ServiceMonitor + alert + 1 SLO
- [ ] **M10** Argo Rollouts canary **có `trafficRouting.nginx`** + auto-rollback
- [ ] **M11** GitOps self-heal + CI policy gate, hiểu bootstrap chicken-and-egg
- [ ] **M12** kube-bench (cả `master` targets) trước/sau M0 có delta, trivy k8s, pluto
- [ ] **M13** etcd snapshot **và** Velero, restore drill có số RTO, DB trên class `Retain`
- [ ] **M14** upgrade 1 patch version với 0 downtime, biết cert renew
- [ ] **M15** 13 drill, mỗi cái viết được thứ tự lệnh chẩn đoán

## 6. Ánh xạ sang thế mạnh có sẵn (dùng khi phỏng vấn)

| Trong lab | Anh ĐÃ làm ở tầng AWS |
|---|---|
| Kyverno policy-as-code | AWS Config conformance packs ~260 rules |
| Cosign keyless + Trivy + SBOM gate | Trivy scan + Semgrep weekly audit |
| **Vault K8s auth** → ESO | Secrets Manager + OIDC keyless CI/CD (IRSA) |
| kube-bench / continuous compliance | ISO 27001 ISMS + Vanta evidence |
| NetworkPolicy zero-trust | WAFv2 + VPC endpoints + least-priv IAM |
| etcd snapshot + Velero + RTO drill | (mảng nên bổ sung cho tròn story) |
| Kubespray declarative control-plane config | Terraform IaC discipline |
