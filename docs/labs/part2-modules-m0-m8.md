# Part 2 v2 — Modules M0 → M8 (hardening nền)

> Phần 1/2 của module list. Bối cảnh cluster, ranh giới lab, Part 0 và thứ tự phụ thuộc nằm ở
> [part2-config-hardening.md](part2-config-hardening.md). Module M9 → M15 ở
> [part2-modules-m9-m15.md](part2-modules-m9-m15.md).

---

## M0 — Control-plane hardening (qua kubespray, không sửa tay)

🎯 Mã hoá Secret ở etcd + bật audit logging.
🏦 Secret nằm plaintext trong etcd là finding nghiêm trọng (ISO 27001 A.10, APRA CPS 234
information asset protection). Audit log = bằng chứng "ai làm gì" cho SIEM và điều tra.

🛠️ **Đây là chỗ bản v1 sai đường.** Cluster anh do kubespray quản, nên sửa
`/etc/kubernetes/manifests/kube-apiserver.yaml` bằng tay sẽ **bị ghi đè** lần chạy playbook
sau. Đúng cách — đổi 2 biến đã có trong repo:

```yaml
# iac/modules/kubespray/ansible/k8s-cluster.yaml
kube_encrypt_secret_data: true      # line 152 — hiện false
kubernetes_audit:          true     # line 234 — hiện false
```

Kubespray sẽ tự sinh `EncryptionConfiguration`, audit policy file, và thêm cờ apiserver trên
cả 3 CP. Sau đó:
- chạy lại playbook (`cluster.yml`, hoặc `--tags=master` cho nhanh), **rolling từng CP một**
- **re-encrypt secret cũ** — bật encryption chỉ áp dụng cho ghi mới:
  `kubectl get secrets -A -o json | kubectl replace -f -`
- tuỳ chỉnh audit policy nếu cần (`kube_audit_policy_*` vars) — đừng để `level: RequestResponse`
  cho `secrets`, vì như thế **giá trị secret vào log**, tự tạo lỗ hổng mới
- **ship audit log** ra khỏi node: fluent-bit/vector DaemonSet đọc `/var/log/audit/` → Loki
  (hoặc SIEM). Log nằm trên chính node bị tấn công thì không phải evidence.

⚠️ Bẫy:
- Đừng chạy playbook đồng thời 3 CP — mất quorum.
- Encryption key nằm trên node ở `/etc/kubernetes/ssl/`; mất key = **mất toàn bộ secret**. Phải
  backup, và biết quy trình rotate (thêm key mới lên đầu provider list → re-encrypt → xoá key cũ).
- Audit log ăn disk, worker chỉ còn 12G — set `--audit-log-maxsize/maxbackup` tử tế.

✅ **Checkpoint:** đọc trực tiếp từ etcd để **chứng minh** ciphertext, không tin `kubectl`:
`ETCDCTL_API=3 etcdctl get /registry/secrets/default/<name>` → thấy prefix `k8s:enc:aescbc:v1:`
thay vì plaintext. Và `tail -f` audit log thấy event khi anh tạo secret.

🎤 1. Base64 trong Secret giải quyết gì và **không** giải quyết gì? Encryption at rest thêm
được gì, và vẫn **không** chống được attacker nào? 2. Vì sao bật encryption rồi vẫn phải
`kubectl replace` toàn bộ secret cũ? 3. `aescbc` vs KMS provider — trên EKS thì AWS làm hộ
phần nào? 4. Audit log để `RequestResponse` cho secrets thì hại gì?

---

## M1 — PSA (Pod Security Admission) — bản v1 bỏ hoàn toàn

🎯 Bật baseline bảo mật pod bằng cơ chế **có sẵn trong k8s**, trước khi thêm policy engine.
🏦 Đây là lớp phòng thủ rẻ nhất và là câu hỏi kinh điển (lịch sử PSP → PSA). Bank muốn thấy
anh dùng cơ chế built-in trước, rồi mới thêm công cụ.

🛠️
- Label namespace theo 3 chế độ: `enforce` + `audit` + `warn`, ở mức `restricted` cho lab ns.
  Bắt đầu bằng `warn`/`audit` để soi trước, `enforce` sau.
- Cố ý apply 1 pod vi phạm (privileged / hostPath / runAsRoot) → xem bị admission từ chối kèm
  message. Đây là demo đẹp và nhanh nhất trong cả lab.
- Hardening `securityContext` cho app: `runAsNonRoot`, `runAsUser`, `readOnlyRootFilesystem`
  (+ `emptyDir` cho `/tmp`, `/var/cache/nginx`, `/var/run/postgresql`),
  `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`.

⚠️ PSA **không** kiểm được thứ ngoài `securityContext` (image registry, resource limits,
label) — đó chính là lý do cần Kyverno ở M2. Nói được ranh giới này là điểm cộng.

✅ Pod vi phạm bị chặn với message rõ; app 3 tầng vẫn chạy dưới `restricted`.

🎤 1. PSP bị bỏ vì sao, PSA khác gì? 2. Ba mode `enforce/audit/warn` dùng phối hợp thế nào khi
rollout vào cluster đang chạy? 3. `restricted` chặn cụ thể những gì? 4. PSA **không** làm được gì?

---

## M2 — Kyverno policy-as-code (rollout an toàn)

🎯 Chặn config xấu ngay cửa vào cho những thứ PSA không phủ.
🏦 Con người quên, policy engine không. Shift-left governance, map thẳng CIS Benchmark.

🛠️ Rule nên có: `disallow-latest-tag`, `require-requests-limits`, `require-probes`,
`allowed-registries`, `require-owner-labels`, `disallow-default-service-account`,
`disallow-host-path`, `disallow-host-namespaces`. Kho `kyverno/policies` copy về được.
Thêm ít nhất **1 mutate rule** (auto thêm label owner, hoặc `imagePullSecrets`) — bản v1 nhắc
mutate ở câu hỏi nhưng không có bài làm.

⚠️ **Ba bẫy — cái đầu đủ sức làm vỡ cluster:**

1. **Phải exclude namespace hệ thống.** `ClusterPolicy` + `Enforce` mà không loại
   `kube-system`, `metallb-system`, `ingress-nginx`, `argocd`, `cert-manager`, `kyverno` thì:
   pod đang chạy không sao (admission chỉ chặn lúc **tạo**), nhưng lần đầu `calico-node` hay
   `coredns` bị evict/reschedule là **nó không tạo lại được** → mất CNI trên node đó → outage
   âm thầm, và cluster vẫn "xanh" lúc anh apply nên rất khó truy.
2. **`allowed-registries` của bản v1 chỉ cho `ghcr.io` + ECR.** Anh không có ECR, và app anh
   pull từ `docker.io` (`postgres`, `nginx`). Bật `Enforce` là chặn chính app mình. Allowlist
   phải khớp registry anh thật sự dùng.
3. **Field `validationFailureAction` đã deprecated từ Kyverno 1.12** → chuyển xuống
   `spec.rules[].validate.failureAction`. Bản v1 tự thú "field có thể khác theo version" —
   chỗ này phải đúng. Verify: `kubectl explain clusterpolicy.spec.rules.validate`.

Thứ tự rollout: `Audit` → đọc `kubectl get polr -A` → sửa app cho compliant → `Enforce`.
Và nhớ: rule match `kinds: ["Pod"]` được Kyverno **autogen** thành rule cho
Deployment/StatefulSet/DaemonSet — verify `kubectl get cpol <name> -o yaml | grep autogen`,
vì nếu không có thì Deployment apply thành công rồi Pod bị chặn âm thầm ở ReplicaSet.

Cuối cùng, đừng cài bằng `releases/latest/download/` — plan dạy pin digest thì chính nó
cũng phải pin version.

✅ Deploy sai chuẩn bị chặn kèm message rõ; app compliant deploy bình thường; xoá 1 pod
`calico-node` → nó **tạo lại được** (chứng minh exclude đúng).

🎤 1. Kyverno/OPA giải quyết gì mà code review tay không? 2. `Audit` vs `Enforce` — thứ tự
rollout vào cluster đang chạy? 3. Validating vs Mutating admission — dùng mutate làm gì?
4. Vì sao cần cả PSA **và** Kyverno? 5. Policy engine down thì cluster ra sao (`failurePolicy`)?

---

## M3 — Supply chain & image trust

🎯 Chỉ cho chạy image **được ký + quét sạch**, build từ base tối thiểu non-root.
🏦 Log4Shell dạy cả ngành. Cần biết image chứa gì (SBOM), chưa có CVE nghiêm trọng (scan
gate), và đúng là image mình build (signing). Đây là SLSA / Sigstore.

🛠️ ⚠️ **Module này buộc anh tự build image** — không ký được `postgres`/`nginx` của người
khác. Bản v1 giả định ECR; anh không có. Dùng **ghcr.io** (anh có GitHub) và build 1 app Go/
Python nhỏ để làm tầng `api`, thay PostgREST ở overlay lab.
- Dockerfile: multi-stage → `gcr.io/distroless/static-debian12:nonroot`, `USER nonroot`, pin digest.
- Scan **làm cổng chặn**, không chỉ report: `trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed`.
- SBOM: `syft <img> -o spdx-json`, đính kèm làm attestation.
- Ký **keyless bằng OIDC** trong GitHub Actions (`cosign sign --yes <digest>`) — đúng gu
  keyless của anh, và tránh phải quản private key. Ký theo **digest**, không theo tag.
- Cưỡng chế bằng Kyverno `verifyImages`. ⚠️ Khối YAML của bản v1 **không parse được** (block
  scalar `|-` đặt trong flow mapping `{ }`, và có dấu `}` lạc dòng riêng) — viết block style,
  và với keyless thì dùng `keyless: { issuer, subject }` chứ không `publicKeys`.

✅ Image chưa ký (hoặc sai issuer/subject) bị Kyverno từ chối; image ký đúng chạy được;
Trivy fail build khi có CVE CRITICAL.

🎤 1. SBOM là gì, ai cần và khi nào? 2. Cosign keyless chứng minh điều gì, và **không** chứng
minh điều gì? 3. Vì sao pin digest an toàn hơn pin tag? 4. `--ignore-unfixed` là đúng hay là
gian? 5. Admission verify signature làm chậm/ảnh hưởng gì lúc scale?

---

## M4 — Secrets: Vault + External Secrets (không phải AWS Secrets Manager)

🎯 Không còn Secret plaintext trong Git; giá trị thật chỉ sống trong Vault.
🏦 Secret trong Git = rò rỉ chờ ngày. Cần mã hoá, rotation, và tách quyền (dev không thấy
giá trị prod).

🛠️ ⚠️ Bản v1 dùng AWS Secrets Manager + IRSA. **Anh đã có Vault sẵn** — dùng nó:
- Vault chạy Docker trên NAS `https://192.168.1.254:8200`, KV v2, mount path `proxmox`, CA
  self-signed (đã có `caBundle` trong repo).
- Deploy **ESO v0.17.0** (Application đã viết sẵn trong
  `InfrastructureGitOps/.../apps/external-secrets-operator/app.yaml`, chưa deploy).
- Dùng **Vault Kubernetes auth**, không dùng token tĩnh: mỗi app 1 `SecretStore` + role
  (`bound_service_account_names` / `bound_service_account_namespaces`) — mẫu có sẵn ở
  `manifests/external-dns/base/secretstore.yaml`.
- `automountServiceAccountToken: false` ở mọi workload không cần gọi API server.
- Sealed Secrets: chỉ làm **so sánh**, không cần cài. Nếu cài thì phải backup private key của
  controller — **mất key = mất toàn bộ SealedSecret, không cứu được** (bản v1 không nhắc).

⚠️ Risk thật đáng kể và đáng kể ra trong interview: Vault của anh là **1 container đơn lẻ trên
NAS**, không HA, và giữ khoá của mọi thứ. NAS chết → không app nào lấy được secret. Nói được
"đây là single point of failure tôi biết và đây là cách tôi sẽ sửa" ăn điểm hơn là giả vờ nó ổn.
Cộng thêm: Vault **auto-unseal** chưa có → NAS reboot là Vault sealed, ESO fail.

✅ Repo chỉ còn `ExternalSecret` (không giá trị thật); Pod nhận đúng password; xoá Secret
trong cluster → ESO tự tạo lại từ Vault trong `refreshInterval`.

🎤 1. Vault K8s auth so với IRSA trên EKS — giống/khác chỗ nào? (đây là câu ăn tiền: anh
map được on-prem ↔ cloud) 2. `automountServiceAccountToken: false` chống được gì?
3. Rotate secret khi Pod đang chạy mà không downtime — làm sao? 4. Vault sealed thì blast
radius tới đâu? 5. Sealed Secrets vs ESO — chọn cái nào cho GitOps thuần?

---

## M5 — RBAC least-privilege

🎯 Không `cluster-admin` lảng vảng; mỗi workload một SA đúng quyền tối thiểu.
🏦 Least privilege + separation of duties là điều khoản cứng (ISO A.9, APRA CPS 234).

🛠️ SA riêng mỗi tầng; `Role` (không `ClusterRole`) bó trong namespace; siết tới
`resourceNames` cho đúng object. Audit bằng `kubectl auth can-i --list --as=system:serviceaccount:...`.
Soát quyền nguy hiểm: `kubectl get clusterrolebindings -o wide | grep -i cluster-admin`.
Thêm Kyverno rule cấm dùng SA `default`.

⚠️ Cluster anh dùng `admin.conf` / `super-admin.conf` làm kubeconfig — tức anh đang thao tác
bằng cert `cluster-admin` tĩnh, đúng thứ bank cấm. Kể được lộ trình đúng (OIDC/SSO → AD group
→ just-in-time, không kubeconfig admin tĩnh) là câu trả lời hay, kể cả khi homelab chưa làm.

✅ `can-i --list` cho SA app chỉ ra vài quyền; `can-i delete pods` = `no`; không workload nào
bind `cluster-admin`.

🎤 1. Role vs ClusterRole — khi nào **buộc** phải ClusterRole? 2. `resourceNames` siết thêm gì,
và verb nào nó **không** siết được? 3. Vì sao mọi Pod dùng SA `default` là tệ? 4. Aggregated
ClusterRole dùng khi nào?

---

## M6 — Zero-trust networking (Calico, mục tiêu demo thật)

🎯 Default-deny cả ingress **và** egress, chỉ mở đúng luồng.
🏦 Micro-segmentation chống lateral movement khi 1 Pod bị chiếm.

🛠️ ⚠️ Hai chỗ bản v1 sai: (a) nó bảo "check xem có Calico chưa, chưa thì cài" — **đã có
Calico**; (b) nó demo chặn IMDS `169.254.169.254`, thứ **không tồn tại trên Proxmox** → demo rỗng.

Mục tiêu demo đúng cho infra của anh: **chặn pod chạm hạ tầng nội bộ `192.168.1.0/24`** (NAS,
Vault, router, bastion) — rồi mở đúng một ngoại lệ: ESO → `192.168.1.254:8200`.
Đây *có* enforce thật, và là đúng câu chuyện "pod bị chiếm không được với tới secret store /
storage backend".
- `default-deny-all` (cả `Ingress` + `Egress`) cho lab ns.
- Mở egress DNS tới `kube-dns` port 53 UDP+TCP — **quên cái này là app chết DNS ngay**.
- Mở đúng tier: `web → api:8080`, `api → postgres:5432`.
- `ipBlock` cho ngoại lệ Vault. ⚠️ `except` **phải nằm trong cùng `ipBlock` với `cidr`** —
  bản v1 viết `except` không có `cidr`, không hợp lệ.
- Bonus self-managed: Calico `GlobalNetworkPolicy` — chặn ở tầng cluster, thứ NetworkPolicy
  chuẩn k8s không làm được.

**Kèm 1 finding thật:** ingress-nginx đang bật `--watch-ingress-without-class=true` → bất kỳ ai
tạo Ingress không khai `ingressClassName` cũng được serve, tenant khác chiếm được hostname.
Tắt cờ đó (qua kubespray addon vars) + Kyverno rule bắt buộc `ingressClassName`. Ví dụ
multi-tenancy rất cụ thể để kể.

✅ Pod tạm không gọi ra ngoài được; `web` **không** tới được `postgres:5432` (timeout) nhưng
`api` thì được; pod thường **không** tới được `192.168.1.254:8200`, riêng ESO thì được.

🎤 1. NetworkPolicy mặc định của k8s là allow hay deny, và điều đó nghĩa gì? 2. Vì sao
default-deny egress hay làm chết DNS, và fix thế nào? 3. Cùng YAML mà cluster này enforce
cluster kia không — vì sao? 4. NetworkPolicy có chặn được traffic node-level (NFS mount) không?
5. Trên EKS, tương đương của "chặn egress ra metadata" là gì và vì sao quan trọng?

---

## M7 — Resource governance & multi-tenancy

🎯 Namespace = ranh giới tenant, có quota + default limit.
🏦 Nhiều team chung nền tảng → công bằng tài nguyên + kiểm soát chi phí (FinOps).

🛠️ `ResourceQuota` (requests/limits cpu+mem, `pods`, `count/deployments.apps`,
`persistentvolumeclaims`), `LimitRange` (`default`, `defaultRequest`, `max`), `PriorityClass`
cho app quan trọng. ⚠️ Worker chỉ 3.4 CPU + 7Gi allocatable — quota bản v1 (`requests.cpu: 4`,
`8Gi`) là gần trọn **một** node; scale xuống cho khớp.

✅ Vượt quota → Pod mới bị từ chối kèm message; Pod quên set limit → nhận default từ LimitRange;
`kubectl get pod -o jsonpath='{.status.qosClass}'` cho ra đúng Guaranteed/Burstable như thiết kế.

🎤 1. ResourceQuota vs LimitRange? 2. Quên set requests → hệ luỵ scheduling và QoS?
3. PriorityClass ảnh hưởng eviction ra sao, và `preemptionPolicy` làm gì? 4. Ba QoS class và
thứ tự bị evict khi node hết memory?

---

## M8 — Resilience config

🎯 App sống sót qua bảo trì node.
🏦 Patch/upgrade node là việc thường xuyên; app không được rớt khi node bị drain.

🛠️ `terminationGracePeriodSeconds` + `preStop` (rút khỏi Endpoints trước khi chết),
`topologySpreadConstraints` theo `kubernetes.io/hostname` với `whenUnsatisfiable: DoNotSchedule`,
`PDB minAvailable`. Drill: `kubectl drain` 1 worker, chạy `hey` song song → 0 lỗi 5xx.
**Bonus:** label giả zone `topology.kubernetes.io/zone=az-a|b|c` lên 3 worker → demo được đúng
semantics zone-spread dù không có zone vật lý.

⚠️ `PDB minAvailable: 2` với `replicas: 2` → drain **bị chặn vĩnh viễn**. Chọn số cho khớp
replicas, và biết phân biệt "PDB đang bảo vệ" vs "PDB cấu hình sai gây deadlock".

✅ Trong lúc drain, endpoint không tụt dưới `minAvailable`; `hey` báo 0 lỗi; `rollout undo` về
được revision trước.

🎤 1. PDB giải quyết gì mà `replicas` không? 2. `preStop` + grace period phối hợp thế nào để
zero-downtime, và vì sao cần `preStop` khi endpoint chưa kịp propagate? 3. `DoNotSchedule` vs
`ScheduleAnyway`? 4. PDB có chặn được node chết đột ngột không?

---

→ Tiếp: [M9 → M15](part2-modules-m9-m15.md)
