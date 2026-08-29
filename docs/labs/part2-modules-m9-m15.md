# Part 2 v2 — Modules M9 → M15 (delivery, compliance, DR, drills)

> Phần 2/2 của module list. Bối cảnh cluster và thứ tự phụ thuộc ở
> [part2-config-hardening.md](part2-config-hardening.md). Module M0 → M8 ở
> [part2-modules-m0-m8.md](part2-modules-m0-m8.md).

---

## M9 — Observability (bản v1 thiếu, nhưng M10 phụ thuộc nó)

🎯 Có metric + alert trước khi làm canary tự động — vì canary analysis đọc metric.
🏦 Không đo được thì không deploy an toàn được. SLO/error budget là ngôn ngữ bank dùng.

🛠️ `kube-prometheus-stack` (⚠️ retention 2d, PVC trên `nfs-csi`, tắt exporter không cần —
worker chỉ còn 12G disk). `ServiceMonitor` cho app; ít nhất 1 recording rule + 1 alert
(`PrometheusRule`) kiểu error-rate/latency; 1 SLO đơn giản + error budget; Grafana dashboard.

✅ Prometheus scrape được app; alert bắn khi anh cố tình đẩy 5xx lên.

🎤 1. Metric nào là 4 golden signal? 2. Vì sao `rate()` chứ không phải counter thô? 3. Alert
nên đặt trên symptom hay cause? 4. SLO/error budget dùng để ra quyết định gì?

---

## M10 — Progressive delivery (Argo Rollouts, canary **thật**)

🎯 Canary tự phân tích metric, tự rollback.
🏦 Khác biệt giữa "deploy được" và "deploy an toàn": phát hiện regression trên 20% traffic rồi
tự lùi, thay vì cả prod sập.

🛠️ ⚠️ **Chỗ bản v1 sai quan trọng nhất của module:** nó khai `canary.steps` với `setWeight: 20`
mà **không có `trafficRouting`**. Thiếu traffic manager thì Rollouts chỉ **xấp xỉ weight bằng
số pod** — `replicas: 4` thì 20% thực tế là 25% (1/4), và không có traffic split thật.
Anh **có ingress-nginx** → khai `trafficRouting.nginx` với `stableIngress`, Rollouts tự sinh
canary Ingress dùng annotation `canary-weight`. Đó mới là canary thật.
- `AnalysisTemplate` trỏ Prometheus của M9 (đúng service name trong ns `monitoring`).
- Deploy 1 version lỗi cố ý → analysis fail → tự rollback.

✅ Version tốt bò 20→50→100; version lỗi bị chặn ở bước 20% và tự lùi;
`kubectl argo rollouts get rollout --watch` thấy rõ.

🎤 1. Canary vs blue-green — đánh đổi? 2. Automated analysis chống được gì mà rollback tay
không? 3. Không có traffic manager thì `setWeight` nghĩa là gì? 4. Canary với app **có state**
(migration DB) thì vấn đề nằm ở đâu?

---

## M11 — GitOps hardening

🎯 Không `kubectl apply` tay; mọi thay đổi qua Git, có cổng kiểm.
🏦 Change control có approval là bắt buộc. Git history = audit trail; rollback = `git revert`.

🛠️ ArgoCD **đã chạy nhưng 0 Application** → anh bootstrap từ đầu, đúng bài:
- `AppProject` riêng, siết `sourceRepos` / `destinations` / `clusterResourceWhitelist`.
- app-of-apps + `argocd.argoproj.io/sync-wave` để order (CRD → controller → app).
- Kustomize `overlays/dev` + `overlays/prod`; pin image theo **digest**.
- `syncPolicy.automated: { prune: true, selfHeal: true }` → `kubectl edit` tay bị revert.
- **CI gate trước khi sync:** `kubeconform -strict`, `kyverno apply policies/ --resource manifests/`
  (test policy offline), `conftest test`.
- Repo: `InfrastructureGitOps` trên Azure DevOps. ⚠️ ESO chưa deploy lúc bootstrap → repo
  credential phải seed **thủ công 1 lần**. Đây chính là **bootstrap chicken-and-egg**; nói được
  điều này (và rằng sau đó ESO tiếp quản) là điểm cộng.

✅ `kubectl edit deploy/web` bị revert <1 phút; manifest sai policy bị CI chặn ở PR; sửa 1 dòng
trong overlay prod → chỉ prod sync.

🎤 1. GitOps giải quyết gì mà "kubectl apply trong pipeline" không? 2. Drift là gì,
`selfHeal`/`prune` xử lý sao, và `prune` nguy hiểm chỗ nào? 3. Vì sao validate policy ở CI
**và** enforce bằng Kyverno trong cluster (hai lớp)? 4. Secret trong GitOps xử lý thế nào?

---

## M12 — Compliance & continuous scanning

🎯 Có bằng chứng cluster đạt chuẩn, quét liên tục.
🏦 Auditor hỏi "chứng minh đi". Đây là ISO 27001 / Vanta phiên bản cho k8s.

🛠️ `kube-bench run --targets master,node,policies` — ⚠️ **lợi thế self-managed**: anh chạy
được cả nhóm check `master`/control-plane mà trên EKS là N/A. `trivy k8s --report summary cluster`
(misconfig + CVE + secret lộ). `pluto detect-files` tìm API sắp deprecated. Đóng thành `CronJob`,
xuất report làm evidence.

✅ Có report; vá ít nhất 1 finding và cho thấy điểm cải thiện (M0 sẽ tự vá vài check
encryption/audit — chạy kube-bench **trước và sau** M0 để thấy delta, đó là demo rất đẹp).

🎤 1. kube-bench map vào chuẩn nào? Check nào N/A trên managed cluster mà anh vẫn làm được?
2. Vì sao continuous scan chứ không audit 1 lần? 3. `pluto` cứu anh khỏi sự cố gì khi upgrade?

---

## M13 — Backup & DR (etcd **trước**, Velero sau)

🎯 Backup as code, và **test restore** — backup không test = không có backup.
🏦 RTO/RPO có số, DR drill định kỳ.

🛠️ ⚠️ Bản v1 chỉ có Velero. **Velero KHÔNG backup etcd** — với cluster tự quản, etcd snapshot
là backup giá trị nhất và là thứ duy nhất cứu anh khi mất control plane.
1. **etcd snapshot**: `etcdctl snapshot save` trên 1 CP → đẩy ra NAS → `CronJob`/systemd timer.
   Drill restore vào 1 CP (biết là phải dừng apiserver, restore, sửa `--initial-cluster`).
   Kubespray có playbook/vars cho etcd backup — dùng đường declarative.
2. **Velero** cho app-level: cần S3 → **chạy MinIO trên NAS** (anh đã quen pattern Docker-trên-NAS
   vì Vault đang chạy vậy). `--use-node-agent` (Kopia) để backup PV **file-level** — csi-driver-nfs
   không có snapshot như EBS.
3. Drill: `velero backup create` → xoá namespace → `velero restore` → **bấm giờ ra số RTO**.

⚠️ Trước khi drill xoá namespace: DB phải nằm trên `nfs-csi-retain`. Với `reclaimPolicy: Delete`,
xoá namespace = xoá PVC = **CSI xoá thật thư mục trên NAS**. Bản v1 để drill này ở module cuối
nhưng các drill phá hoại thì ở trên — sai thứ tự.

✅ Xoá namespace, restore lại được cả app **và data Postgres**; có con số RTO ghi lại; etcd
snapshot restore được trên 1 CP.

🎤 1. Vì sao "có backup" chưa đủ? 2. RTO vs RPO, config nào ảnh hưởng cái nào? 3. Velero backup
PV bằng cơ chế gì (CSI snapshot vs file-level) và vì sao NFS của anh phải dùng file-level?
4. Etcd snapshot và Velero backup **cái nào cứu được gì** — tại sao cần cả hai?

---

## M14 — Upgrade & cert rotation drill (bản v1 thiếu)

🎯 Nâng version cluster và rotate cert mà không rớt app.
🏦 "Anh upgrade cluster thế nào" là top-5 câu hỏi cho self-managed, và là việc bank làm hàng quý.

🛠️
- Đọc **version skew policy** trước (kubelet được thấp hơn apiserver mấy minor).
- kubespray `upgrade-cluster.yml` với `kube_version` mới — **control plane trước, worker sau**,
  rolling từng node: cordon → drain → upgrade → uncordon.
- Chạy `pluto` (M12) trước để bắt API deprecated.
- Cert: `kubeadm certs check-expiration` (cluster anh: hết hạn **2027-03-21**, còn 234 ngày →
  không gấp, nhưng phải biết quy trình) → `kubeadm certs renew all` + restart control plane
  component, hoặc đường kubespray.

✅ Upgrade 1 patch version với app chạy liên tục (`hey` 0 lỗi); `check-expiration` sau renew
cho ngày mới.

🎤 1. Thứ tự upgrade và vì sao CP trước? 2. Version skew cho phép lệch bao nhiêu? 3. Cert k8s
hết hạn thì triệu chứng là gì và fix thế nào? 4. Trên EKS thì AWS làm hộ phần nào của việc này?

---

## M15 — Failure drills (khai thác lợi thế 3 control plane)

🎯 Chứng minh anh hiểu HA thật, không chỉ đọc lý thuyết.
🏦 Bank hỏi rất sâu về failure mode. Đây là phần ứng viên dùng EKS **không thể** trả lời từ
kinh nghiệm.

🛠️ Mỗi drill bấm giờ, viết lại thứ tự lệnh mình chạy (không đoán):

| # | Gây lỗi | Triệu chứng đích |
|---|---|---|
| 1 | Tắt **1** control plane (`10.0.1.21`) | cluster vẫn hoạt động — quorum 2/3 |
| 2 | Tắt **2** control plane | **mất quorum**, apiserver không ghi được → demo etcd quorum |
| 3 | Sửa password DB trong Vault/Secret | `CrashLoopBackOff` |
| 4 | `limits.memory: 32Mi` cho postgres | `OOMKilled` (exit 137) |
| 5 | Tag image `:nope` | `ImagePullBackOff` |
| 6 | `requests.cpu: 8` (> 3.4 allocatable) | `Pending` + `Insufficient cpu` |
| 7 | Xoá rule egress DNS | app 502, log "no such host" |
| 8 | Sai `targetPort` trong Service | ingress 503, `Endpoints` rỗng |
| 9 | Taint cả 3 worker, không toleration | `Pending` + `untolerated taint` |
| 10 | `delete pvc` khi pod còn mount | PVC stuck `Terminating` (finalizer) |
| 11 | Drain 2/3 worker cùng lúc | PDB chặn eviction |
| 12 | Kill node đang giữ VIP MetalLB | VIP failover — đo mất mấy giây (L2 ARP re-announce) |
| 13 | Dừng Vault trên NAS | ESO fail, secret không refresh — đo blast radius |

⚠️ Drill 1-2 làm **sau** M13 (có etcd snapshot). Drill 2 phải biết cách khôi phục trước khi làm.

🎤 Với mỗi drill: triệu chứng → lệnh nào chạy trước → root cause → fix → cách phòng ngừa.

---

← Trước: [M0 → M8](part2-modules-m0-m8.md) · Index: [part2-config-hardening.md](part2-config-hardening.md)
