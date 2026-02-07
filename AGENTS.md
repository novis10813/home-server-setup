# AGENTS.md - AI 協作開發指南

> 本文件供 AI 編碼助手（如 Claude、Copilot）在此專案中協作開發時參考。

## 專案概述

**Home Server Docker 服務** — 以 Docker Compose 管理的基礎設施配置庫，用於部署和管理 Home Server 網關服務。

### 主要技術棧
- **容器化**：Docker、Docker Compose（使用 `include` 語法）
- **反向代理**：Traefik v3（3.6.7）
- **安全代理**：LinuxServer Socket Proxy（Docker API 安全存取）
- **SSO 認證**：traefik-forward-auth（OAuth 2.0）
- **憑證管理**：Let's Encrypt + Cloudflare DNS Challenge

### 設計邏輯
1. **職責分離**：依服務類型劃分 Compose 檔案（目前僅有 `infrastructure`）
2. **安全優先**：Socket Proxy 隔離 Docker API；所有容器啟用 `no-new-privileges`
3. **環境變數驅動**：敏感設定與可變參數皆透過 `.env` 與 Docker Secrets 管理
4. **配置與資料分離**：
   - `${DOCKERDIR}/appdata/` — 手寫設定檔（版控追蹤）
   - `${DATADIR}/` — 容器運行時資料（不版控，如資料庫、快取）
5. **參考來源**：架構參考 [SimpleHomelab/Docker-Traefik](https://github.com/SimpleHomelab/Docker-Traefik)

## 目錄結構

```
/opt/docker/
├── docker-compose-infrastructure.yml  # 主入口 Compose（include 子檔案）
├── .env.example                        # 環境變數範本（複製為 .env 使用）
├── .env                                # 本機環境變數（勿提交）
├── compose/
│   └── infrastructure/
│       ├── traefik.yml                 # Traefik 反向代理服務定義
│       ├── socket-proxy.yml            # Docker API 安全代理
│       └── traefik_forward_auth.yml    # OAuth SSO 服務
├── appdata/
│   └── traefik/
│       ├── rules/                      # Traefik 動態規則（middlewares、chains）
│       │   ├── 01-tls.yml
│       │   ├── chain-oauth.yml
│       │   ├── chain-basic-auth.yml
│       │   ├── chain-no-auth.yml
│       │   └── middlewares-*.yml
│       └── acme/
│           └── acme.json               # Let's Encrypt 憑證儲存（chmod 600）
├── secrets/                            # 敏感檔案（勿提交版控）
│   ├── basic_auth_credentials          # htpasswd 格式
│   └── cf_dns_api_token                # Cloudflare DNS API Token
└── logs/
    └── traefik/                        # Traefik 存取日誌與錯誤日誌
```

## 常用指令

### 啟動 / 停止 / 日誌

```bash
# 啟動網關服務
docker compose -f docker-compose-infrastructure.yml up -d

# 檢視即時日誌
docker compose -f docker-compose-infrastructure.yml logs -f

# 僅檢視特定服務日誌
docker compose -f docker-compose-infrastructure.yml logs -f traefik

# 停止所有服務
docker compose -f docker-compose-infrastructure.yml down

# 重啟特定服務
docker compose -f docker-compose-infrastructure.yml restart traefik
```

### 設定驗證

```bash
# 驗證 Compose 語法
docker compose -f docker-compose-infrastructure.yml config

# 檢查 Traefik 設定（進入容器）
docker exec traefik traefik healthcheck
```

### 憑證與 Secrets

```bash
# 建立 acme.json（首次設定）
touch appdata/traefik/acme/acme.json
echo '{}' > appdata/traefik/acme/acme.json
chmod 600 appdata/traefik/acme/acme.json

# 產生 htpasswd 憑證
htpasswd -nb username password > secrets/basic_auth_credentials
```

## 環境變數說明

| 變數 | 說明 | 範例 |
|-----|------|------|
| `DOCKERDIR` | 專案根目錄絕對路徑 | `/opt/docker` |
| `DATADIR` | 容器運行時資料路徑 | `/mnt/raid1` |
| `TZ` | 時區 | `Asia/Taipei` |
| `DOMAINNAME_1` | 主要網域 | `example.com` |
| `TRAEFIK_PORT` | Traefik Dashboard 主機埠 | `8080` |
| `LOCAL_IPS` | 信任的內網 IP CIDR | `192.168.0.0/16,10.0.0.0/8` |
| `CLOUDFLARE_IPS` | Cloudflare IP 範圍 | 見 `.env.example` |

## 網路架構

| 網路名稱 | 子網 | 用途 |
|---------|------|------|
| `t3_proxy` | `192.168.90.0/24` | Traefik 與後端服務通訊 |
| `socket_proxy` | `192.168.91.0/24` | Traefik 與 Socket Proxy 通訊 |

### 埠對應
- `80` / `81`：HTTP（內部 / 外部）
- `443` / `444`：HTTPS（內部 / 外部）
- `${TRAEFIK_PORT}`：Dashboard API

## 程式碼風格指南

### YAML 檔案慣例
- **檔名**：小寫 + 短橫線（kebab-case），如 `socket-proxy.yml`、`chain-basic-auth.yml`
- **縮排**：2 空格，不使用 Tab
- **註解**：使用 `#` 開頭，重要段落以 `###` 分隔
- **環境變數**：使用 `${VAR}` 或 `${VAR:-default}` 語法

### Docker Compose 慣例
- 所有服務必須設定 `container_name`
- 必須啟用 `security_opt: - no-new-privileges:true`
- 重啟策略：`restart: unless-stopped`
- 敏感資料使用 Docker Secrets，不直接寫入環境變數

### Traefik 標籤慣例
- Router 命名：`servicename-rtr`
- Service 命名：`servicename-svc`
- 格式：`traefik.http.routers.<name>.rule=Host(...)`

### 中介軟體鏈（Middleware Chains）
- `chain-oauth@file`：OAuth 認證 + 安全標頭 + 限流
- `chain-basic-auth@file`：Basic Auth + 安全標頭 + 限流
- `chain-no-auth@file`：僅安全標頭（無認證）

## 安全注意事項

### 禁止提交的檔案
- `.env`（使用 `.env.example` 作為範本）
- `secrets/*`（除了 `README.md`）
- `appdata/traefik/acme/acme.json`（包含私鑰）
- 任何包含密碼、Token、私鑰的檔案

### 新增服務檢查清單
1. [ ] 設定 `no-new-privileges:true`
2. [ ] 使用 `restart: unless-stopped`
3. [ ] 加入適當網路（通常是 `t3_proxy`）
4. [ ] 設定正確的 Traefik labels
5. [ ] 使用 middleware chain 保護端點
6. [ ] 敏感資料使用 Secrets 或環境變數
7. [ ] 運行時資料掛載到 `${DATADIR}/service-name/`（不使用 `appdata/`）

## 維護任務

### 更新容器映像
```bash
docker compose -f docker-compose-infrastructure.yml pull
docker compose -f docker-compose-infrastructure.yml up -d
```

### 備份
- 備份 `appdata/traefik/acme/acme.json`（Let's Encrypt 憑證）
- 備份 `appdata/traefik/rules/`（動態規則）
- 備份 `.env` 與 `secrets/`

## 疑難排解

### Traefik 無法啟動
1. 檢查 `acme.json` 權限：`ls -la appdata/traefik/acme/acme.json`（應為 `600`）
2. 驗證 Secrets 檔案存在：`ls secrets/`
3. 檢查 Socket Proxy：`docker logs socket-proxy`

### 憑證問題
1. 檢查 Cloudflare Token 權限（需 Zone:DNS:Edit）
2. 查看 Traefik 日誌：`docker logs traefik | grep -i acme`
3. 確認 DNS 解析正確

## 參考資源

- [SimpleHomelab/Docker-Traefik](https://github.com/SimpleHomelab/Docker-Traefik)
- [Traefik v3 文件](https://doc.traefik.io/traefik/)
- [LinuxServer Socket Proxy](https://docs.linuxserver.io/images/docker-socket-proxy/)
