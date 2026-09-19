# 服務說明

## Compose 主檔

`docker-compose-infrastructure.yml` 負責：

- 定義 **networks**：`default`、`socket_proxy`、`t3_proxy`
- 定義 **secrets**：`basic_auth_credentials`、`cf_dns_api_token`、`google_oauth_client_id`、`google_oauth_client_secret`、`grafana_admin_password`
- **include** 下列子檔：socket-proxy、traefik、traefik-forward-auth、pihole、prometheus、grafana、node-exporter、cadvisor

---

## Socket Proxy（Docker API 安全代理）

- **檔案**：`compose/infrastructure/socket-proxy.yml`
- **映像**：`lscr.io/linuxserver/socket-proxy:latest`
- **用途**：代理 Docker API，Traefik 透過 `tcp://socket-proxy:2375` 取得容器資訊，不直接掛載 Docker socket。
- **網路**：僅接 `socket_proxy`（192.168.91.254）。
- **權限**：僅開放 Traefik 所需（CONTAINERS、IMAGES、NETWORKS、SERVICES、TASKS、VOLUMES、INFO、EVENTS、POST 等），`read_only: true`、`tmpfs` /run。

---

## Traefik（反向代理）

- **檔案**：`compose/infrastructure/traefik.yml`
- **映像**：`traefik:3.6.7`
- **依賴**：`socket-proxy`
- **網路**：`t3_proxy`（192.168.90.254）、`socket_proxy`
- **Entrypoints**：
  - `web-internal` / `web-external`：80 / 81（HTTP，皆導向 HTTPS）
  - `websecure-internal` / `websecure-external`：443 / 444（HTTPS，含 HTTP/3）
  - `traefik`：8080（Dashboard API）
- **Provider**：Docker 經 Socket Proxy（`tcp://socket-proxy:2375`）、File 動態規則（`/rules`）。
- **TLS**：Let's Encrypt DNS-Cloudflare（`acme.json`）、TLS 選項 `tls-opts@file`。
- **Dashboard**：`Host(traefik.${DOMAINNAME_1})`，middleware：`chain-oauth@file`（**僅內網**：`websecure-internal`）。
- **掛載**：`appdata/traefik/rules` → `/rules`、`appdata/traefik/acme/acme.json` → `/acme.json`、`logs/traefik` → `/logs`。

### 對內 / 對外開放清單（以 Traefik Router entrypoints 為準）

| 服務 | Host | 內網（Internal） | 外網（External） | 保護方式 |
|------|------|------------------|------------------|----------|
| Traefik Dashboard | `traefik.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | `chain-oauth@file` |
| OAuth Portal | `auth.${DOMAINNAME_1}` | ✅ `websecure-internal` | ✅ `websecure-external` | `chain-no-auth@file`（登入頁本身不再套 OAuth） |
| Pi-hole | `pihole.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | `pihole-redirect` + `chain-oauth@file` |
| Prometheus | `prometheus.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | `chain-oauth@file` |
| Grafana | `grafana.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | `chain-oauth@file` |

---

## Traefik Forward Auth（OAuth SSO）

- **檔案**：`compose/infrastructure/traefik-forward-auth.yml`
- **映像**：`ghcr.io/italypaleale/traefik-forward-auth:4`
- **容器名**：`oauth`
- **網路**：`t3_proxy`
- **用途**：提供 OAuth 2.0 登入，供 Traefik 的 `forwardAuth` middleware 使用。
- **入口**：`Host(auth.${DOMAINNAME_1})`，middleware：`chain-no-auth@file`，port 4181（目前同時掛在內/外網 HTTPS entrypoints）。
- **Secrets**：`tfa_config`（設定檔）、`google_oauth_client_secret`。

---

## Pi-hole（DNS）

- **檔案**：`compose/infrastructure/pihole.yml`
- **映像**：`pihole/pihole:latest`
- **網路**：`t3_proxy`（192.168.90.53）
- **埠**：53/tcp、53/udp（DNS）；8053→80（Web 備用）。
- **資料**：`${DATADIR}/pihole/` → `/etc/pihole`。
- **Traefik**：
  - `pihole.${DOMAINNAME_1}`：HTTPS、`pihole-redirect`（根路徑→`/admin/`）+ `chain-oauth@file`。
  - HTTP 用 `web-internal` 並以 `chain-no-auth@file` 導向 HTTPS。
- **環境**：`TZ`、`FTLCONF_webserver_api_password`（預設 `admin`）、`FTLCONF_dns_listeningMode`、`FTLCONF_misc_etc_dnsmasq_d`。

---

## Prometheus（指標收集）

- **檔案**：`compose/infrastructure/prometheus.yml`
- **映像**：`prom/prometheus:v3.9.1`
- **容器名**：`prometheus`
- **Profile**：`monitor`（需以 `--profile monitor` 啟動）
- **網路**：`t3_proxy`
- **用途**：收集與儲存時間序列指標，用於監控 Traefik 與其他服務。
- **資料**：`${DATADIR}/prometheus/` → `/prometheus`（運行時資料）
- **設定**：`${DOCKERDIR}/appdata/prometheus/prometheus.yml` → `/etc/prometheus/prometheus.yml`（抓取設定）
- **Traefik**：
  - `prometheus.${DOMAINNAME_1}`：HTTPS、`chain-oauth@file`（OAuth 保護、僅內網存取）
  - 僅使用 `websecure-internal` entrypoint，不對外開放

### 預設 Scrape Targets

- `prometheus:9090` — Prometheus 自身指標
- `traefik:8080` — Traefik 指標（需在 Traefik 啟用 `--metrics.prometheus=true`）
- `node-exporter:9100` — 主機層級指標（CPU、記憶體、磁碟、網路）
- `cadvisor:8080` — 容器層級指標
- `crypto-relay:9090` — Crypto relay 同步指標

---

## Node Exporter（主機指標）

- **檔案**：`compose/infrastructure/node-exporter.yml`
- **映像**：`prom/node-exporter:v1.9.1`
- **容器名**：`node-exporter`
- **Profile**：`monitor`（需以 `--profile monitor` 啟動）
- **網路**：`t3_proxy`
- **用途**：收集主機層級指標，包含 CPU 使用率、記憶體、磁碟 I/O、網路流量、檔案系統等。
- **掛載**：
  - `/proc` → `/host/proc:ro`
  - `/sys` → `/host/sys:ro`
  - `/` → `/rootfs:ro`
- **特殊設定**：`pid: host`（需存取主機 PID namespace）
- **Port**：9100（僅內部，供 Prometheus 抓取）
- **已知限制**：netdev collector 只能看到容器自己的介面（`eth0`/`lo`），看不到 host 的 `enp4s0`（bind mount `/proc` 到容器後 `/proc/net` 跟著容器 netns 走）。曾嘗試 `network_mode: host` 迴避，但 host 有一個未解機制會無聲丟棄「容器 → host 未發布 port」的 TCP SYN（無任何 firewall 規則），導致 prometheus 抓不到；詳見 `compose/infrastructure/node-exporter.yml` 註解。解決前，主機網路流量面板不放在 Mission Control。

---

## cAdvisor（容器指標）

- **檔案**：`compose/infrastructure/cadvisor.yml`
- **映像**：`gcr.io/cadvisor/cadvisor:v0.52.1`
- **容器名**：`cadvisor`
- **Profile**：`monitor`（需以 `--profile monitor` 啟動）
- **網路**：`t3_proxy`
- **用途**：收集容器層級指標，包含每個容器的 CPU、記憶體、網路使用量。
- **掛載**：
  - `/` → `/rootfs:ro`
  - `/var/run` → `/var/run:ro`
  - `/sys` → `/sys:ro`
  - `/var/lib/docker` → `/var/lib/docker:ro`
  - `/dev/disk` → `/dev/disk:ro`
- **特殊設定**：`privileged: true`（需存取 cgroups 與 Docker）、`--docker_only=true`
- **Port**：8080（僅內部，供 Prometheus 抓取）

---

## Grafana（監控儀表板）

- **檔案**：`compose/infrastructure/grafana.yml`
- **映像**：`grafana/grafana:12.3.2`
- **容器名**：`grafana`
- **Profile**：`monitor`（需以 `--profile monitor` 啟動）
- **網路**：`t3_proxy`
- **用途**：視覺化 Prometheus 收集的指標，提供儀表板與告警功能。
- **資料**：`${DATADIR}/grafana/` → `/var/lib/grafana`（運行時資料）
- **Secrets**：`grafana_admin_password`（管理員密碼，Docker secrets 機制；**勿改用 bind mount**——host 600 權限檔綁入後容器 entrypoint（uid 472）讀不到，GF_SECURITY_ADMIN_PASSWORD 會變空）
- **Provisioning**：
  - Data sources：`${DOCKERDIR}/appdata/grafana/provisioning/datasources/`（含 `prometheus.yaml`，uid=`prometheus`）
  - Dashboards：`${DOCKERDIR}/appdata/grafana/provisioning/dashboards/`（provider）＋ `${DOCKERDIR}/appdata/grafana/dashboards/`（JSON）
- **Traefik**：
  - `grafana.${DOMAINNAME_1}`：HTTPS、`chain-oauth@file`（OAuth 保護）
  - 僅使用 `websecure-internal` entrypoint（僅內網存取）
- **環境**：
  - `GF_SECURITY_ADMIN_USER=admin`
  - `GF_SECURITY_ADMIN_PASSWORD__FILE=/run/secrets/grafana_admin_password`
  - `GF_USERS_ALLOW_SIGN_UP=false`
  - `GF_SERVER_ROOT_URL=https://grafana.${DOMAINNAME_1}`

### 初始設定

1. 首次登入使用 admin 帳號與 secrets 中設定的密碼
2. 新增 Prometheus 資料來源：URL 為 `http://prometheus:9090`（現已 provisioning，uid=`prometheus`）
3. 匯入 Traefik 儀表板：Dashboard ID `17346`

### Mission Control 儀表板（家服務總覽）

- **位置**：Grafana → Mission Control 資料夾 → 「Mission Control - 家服務總覽」（uid `mission-control`）
- **檔案**：`appdata/grafana/dashboards/mission-control.json`（file provisioning，30 秒自動同步；**改面板請改 JSON 檔**，UI 修改會被覆蓋）
- **內容**：
  - 總覽 stat：uptime、load、記憶體/磁碟使用率、容器數、5xx 比例、近 1 小時重啟容器數、抓取健康
  - 主機：CPU/負載、記憶體、磁碟 I/O 與可用空間
  - 容器（cAdvisor）：CPU/記憶體 Top 8、運行時間表（紅色 = 近 1 小時重啟）
  - Traefik：entrypoint 請求速率、服務 Top 10、status code 分佈、open connections
  - Loki：容器日誌量、近期 error/fatal/panic 日誌（無 per-container 過濾，promtail docker stage 未產生 `container_name` label，待修）
- **Data source**：預設 Prometheus（uid `prometheus`）＋ Loki（uid `loki`）。另有一個 UI 手動建立的 prometheus data source（uid `afcibdrcz6ayod`）供舊 community dashboards 使用，勿刪。

### 管理員密碼重設（忘記/失同步時）

```bash
docker exec grafana /usr/share/grafana/bin/grafana-cli admin reset-admin-password "$(cat /opt/docker/secrets/grafana_admin_password)" /usr/share/grafana
```

注意：直接改 `grafana.db` 的 bcrypt hash 無效（Grafana 12 用自己的 hash 格式，需經 grafana-cli / UI / API 寫入）。

---

## Cron（容器重啟排程器）

- **檔案**：`compose/infrastructure/cron.yml`
- **映像**：`alpine:latest`
- **依賴**：`socket-proxy`
- **網路**：`socket_proxy`
- **用途**：執行內建的 `crond`，透過 `socket-proxy` 發送安全的 Docker API 請求，定時對特定容器執行重啟、啟動或停止等維護任務，無須掛載宿主機 `/var/run/docker.sock`。
- **設定**：`${DOCKERDIR}/appdata/cron/crontab` 唯讀掛載至 `/etc/crontabs/root`。
- **安全性**：啟用 `no-new-privileges:true`，加入最低資源限制，且隔離於業務網路之外，僅連接 `socket_proxy`。

---

## 安全與慣例

- 所有服務：`security_opt: - no-new-privileges:true`、`restart: unless-stopped`。
- 敏感資料使用 Docker Secrets，不寫入環境變數。
- 新增服務時應：加入適當網路（多為 `t3_proxy`）、設定 Traefik labels、使用既有 middleware chain 保護端點、運行時資料放 `${DATADIR}/`。
