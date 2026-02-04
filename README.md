# Home Server Docker 服務

本專案使用 **Docker Compose** 與 **Docker** 管理 Home Server 上的各項服務。

整體架構與命名方式參考 [SimpleHomelab/Docker-Traefik](https://github.com/SimpleHomelab/Docker-Traefik)：該專案在根目錄下為每台 Home Server 各準備一份 Compose 檔。由於目前僅有一台主機，這裡改為依**服務類型**劃分，每一份 Compose 對應一類職責。

---

## Compose 檔案與職責劃分

| Compose 檔案 | 職責 | 說明 |
|-------------|------|------|
| `docker-compose-infrastructure.yml` | 網關（Gateway） | Traefik + Socket Proxy |

後續若有其他類型（例如媒體服務、資料庫、自動化等），可再新增對應的 Compose 檔並在此表補充。

---

## Infrastructure：網關（Gateway）

Infrastructure 對應的 Compose 為 **`docker-compose-infrastructure.yml`**，負責**網關**，包含：

1. **Traefik** — 反向代理、路由、TLS（Let's Encrypt DNS-Cloudflare）、服務發現（經 Socket Proxy）  
2. **Socket Proxy** — Docker API 安全代理，Traefik 透過 `tcp://socket-proxy:2375` 取得容器資訊，不直接掛載 Docker socket  

網關動態設定與憑證：`appdata/traefik/rules/`、`appdata/traefik/acme/`；日誌：`logs/traefik/`。敏感資訊放 `secrets/`，勿提交版控。

### 啟動前準備

1. **環境變數**：複製 `.env.example` 為 `.env`，填寫 `DOCKERDIR`、`DOMAINNAME_1`、`TRAEFIK_PORT`、`LOCAL_IPS`（與選填 `CLOUDFLARE_IPS`）。  
2. **Secrets**：在 `secrets/` 放置 `basic_auth_credentials`（htpasswd 格式）、`cf_dns_api_token`（Cloudflare API token）。詳見 `secrets/README.md`。  
3. **ACME**：在 `appdata/traefik/acme/` 建立 `acme.json`（`echo '{}' > acme.json` 後 `chmod 600 acme.json`）。詳見 `appdata/traefik/acme/README.md`。

### 啟動與常用指令

```bash
# 啟動網關
docker compose -f docker-compose-infrastructure.yml up -d

# 檢視日誌
docker compose -f docker-compose-infrastructure.yml logs -f

# 停止
docker compose -f docker-compose-infrastructure.yml down
```

Dashboard：`https://traefik.<DOMAINNAME_1>`（需能解析該網域並通過 Basic Auth）。對外埠：80/81（HTTP）、443/444（HTTPS）、`TRAEFIK_PORT`（API）。

---

## 目錄結構（概要）

- `compose/infrastructure/` — 網關服務定義（socket-proxy.yml、traefik.yml）  
- `appdata/traefik/` — Traefik 動態規則、ACME 憑證  
- `configs/` — 其他服務設定檔  
- `credentials/` — 環境變數與憑證（不提交版控）  
- `secrets/` — 密碼、API Token（見 `secrets/README.md`）  
- `logs/` — 服務日誌（可加入 `.gitignore`）  

---

## 參考資源

- [SimpleHomelab/Docker-Traefik](https://github.com/SimpleHomelab/Docker-Traefik) — 多主機 Docker + Traefik 範例與學習資源  
