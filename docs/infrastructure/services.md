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
- **Secrets**：`grafana_admin_password`（管理員密碼，以 bind mount 掛載）
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
2. 新增 Prometheus 資料來源：URL 為 `http://prometheus:9090`
3. 匯入 Traefik 儀表板：Dashboard ID `17346`

---

## 安全與慣例

- 所有服務：`security_opt: - no-new-privileges:true`、`restart: unless-stopped`。
- 敏感資料使用 Docker Secrets，不寫入環境變數。
- 新增服務時應：加入適當網路（多為 `t3_proxy`）、設定 Traefik labels、使用既有 middleware chain 保護端點、運行時資料放 `${DATADIR}/`。
