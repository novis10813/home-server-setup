# 服務說明

## Compose 主檔

`docker-compose-infrastructure.yml` 負責：

- 定義 **networks**：`default`、`socket_proxy`、`t3_proxy`
- 定義 **secrets**：`basic_auth_credentials`、`cf_dns_api_token`、`google_oauth_client_id`、`google_oauth_client_secret`
- **include** 下列子檔：socket-proxy、traefik、traefik-forward-auth、pihole

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
- **Dashboard**：`Host(traefik.${DOMAINNAME_1})`，middleware：`chain-oauth@file`。
- **掛載**：`appdata/traefik/rules` → `/rules`、`appdata/traefik/acme/acme.json` → `/acme.json`、`logs/traefik` → `/logs`。

---

## Traefik Forward Auth（OAuth SSO）

- **檔案**：`compose/infrastructure/traefik-forward-auth.yml`
- **映像**：`ghcr.io/italypaleale/traefik-forward-auth:4`
- **容器名**：`oauth`
- **網路**：`t3_proxy`
- **用途**：提供 OAuth 2.0 登入，供 Traefik 的 `forwardAuth` middleware 使用。
- **對外**：`Host(auth.${DOMAINNAME_1})`，middleware：`chain-no-auth@file`，port 4181。
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

## 安全與慣例

- 所有服務：`security_opt: - no-new-privileges:true`、`restart: unless-stopped`。
- 敏感資料使用 Docker Secrets，不寫入環境變數。
- 新增服務時應：加入適當網路（多為 `t3_proxy`）、設定 Traefik labels、使用既有 middleware chain 保護端點、運行時資料放 `${DATADIR}/`。
