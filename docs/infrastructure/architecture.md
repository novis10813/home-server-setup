# 架構與目錄結構

## 專案概述

**Home Server Docker 服務** — 以 Docker Compose 管理的基礎設施配置庫，用於部署與管理 Home Server 網關及相關服務。架構與命名參考 [SimpleHomelab/Docker-Traefik](https://github.com/SimpleHomelab/Docker-Traefik)；因目前僅有一台主機，改為依**服務類型**劃分 Compose，每份 Compose 對應一類職責。

---

## 技術棧

| 類別 | 技術 |
|------|------|
| 容器化 | Docker、Docker Compose（`include` 語法） |
| 反向代理 | Traefik v3（3.6.7） |
| Docker API 代理 | LinuxServer Socket Proxy |
| SSO 認證 | traefik-forward-auth（OAuth 2.0） |
| 憑證 | Let's Encrypt + Cloudflare DNS Challenge |
| 監控 | Prometheus v3.9.1 + Grafana 12.3.2（profile: `monitor`） |

---

## 設計邏輯

1. **職責分離**：依服務類型劃分 Compose（目前為 `infrastructure`：網關 + OAuth + Pi-hole + 監控）。
2. **安全優先**：Socket Proxy 隔離 Docker API；所有容器啟用 `no-new-privileges:true`。
3. **環境變數驅動**：敏感與可變參數透過 `.env` 與 Docker Secrets 管理。
4. **配置與資料分離**：
   - `${DOCKERDIR}/appdata/` — 手寫設定（版控）
   - `${DATADIR}/` — 容器運行時資料（不版控，如資料庫、快取）。
5. **參考來源**：架構參考 SimpleHomelab/Docker-Traefik。

---

## Compose 檔案與職責

| Compose 檔案 | 職責 | 說明 |
|-------------|------|------|
| `docker-compose-infrastructure.yml` | 網關（Gateway）+ 監控 | Traefik + Socket Proxy + OAuth + Pi-hole + Prometheus + Grafana |

主檔透過 `include` 引入：

- `compose/infrastructure/socket-proxy.yml`
- `compose/infrastructure/traefik.yml`
- `compose/infrastructure/traefik-forward-auth.yml`
- `compose/infrastructure/pihole.yml`
- `compose/infrastructure/prometheus.yml`（profile: monitor）
- `compose/infrastructure/grafana.yml`（profile: monitor）

---

## 目錄結構

```
/opt/docker/
├── docker-compose-infrastructure.yml   # 主入口（networks、secrets、include）
├── .env.example                        # 環境變數範本（複製為 .env）
├── .env                                # 本機環境變數（勿提交）
├── compose/
│   └── infrastructure/
│       ├── traefik.yml                 # Traefik 反向代理
│       ├── socket-proxy.yml           # Docker API 安全代理
│       ├── traefik-forward-auth.yml   # OAuth SSO
│       ├── pihole.yml                 # Pi-hole DNS
│       ├── prometheus.yml             # Prometheus 監控（profile: monitor）
│       └── grafana.yml                # Grafana 儀表板（profile: monitor）
├── appdata/
│   ├── traefik/
│   │   ├── rules/                     # 動態規則（middlewares、chains）
│   │   │   ├── 01-tls.yml
│   │   │   ├── chain-oauth.yml, chain-basic-auth.yml, chain-no-auth.yml
│   │   │   └── middlewares-*.yml
│   │   └── acme/
│   │       └── acme.json              # Let's Encrypt 憑證（chmod 600）
│   └── prometheus/
│       └── prometheus.yml             # Prometheus 抓取設定
├── secrets/                            # 敏感檔案（勿提交）
│   ├── basic_auth_credentials
│   ├── cf_dns_api_token
│   ├── google_oauth_client_id
│   ├── google_oauth_client_secret
│   ├── tfa_config                     # traefik-forward-auth 設定
│   ├── grafana_admin_password         # Grafana 管理員密碼
│   └── README.md
└── logs/
    └── traefik/                       # Traefik 日誌
```

---

## 網路架構

| 網路名稱 | 子網 | 用途 |
|---------|------|------|
| `t3_proxy` | 192.168.90.0/24 | Traefik 與後端服務（OAuth、Pi-hole 等） |
| `socket_proxy` | 192.168.91.0/24 | Traefik 與 Socket Proxy 通訊 |

### 固定 IP（範例）

- Traefik：192.168.90.254（t3_proxy）
- Socket Proxy：192.168.91.254（socket_proxy）
- Pi-hole：192.168.90.53（t3_proxy）

### 埠對應

| 主機埠 | 容器埠 | 用途 |
|--------|--------|------|
| 80 | 80 | HTTP（內部 entrypoint `web-internal`） |
| 81 | 81 | HTTP（外部 `web-external`） |
| 443 | 443 | HTTPS（內部 `websecure-internal`） |
| 444 | 444 | HTTPS（外部 `websecure-external`） |
| `${TRAEFIK_PORT}` | 8080 | Traefik Dashboard API |
| 53 | 53 | Pi-hole DNS（TCP/UDP） |
| 8053 | 80 | Pi-hole Web 備用 |

HTTP 對外（81）與對內（80）皆會強制導向對應的 HTTPS entrypoint。
