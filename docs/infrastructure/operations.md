# 操作與維護

## 常用指令

### 啟動 / 停止 / 日誌

```bash
# 啟動網關與相關服務
docker compose -f docker-compose-infrastructure.yml up -d

# 檢視即時日誌（全部）
docker compose -f docker-compose-infrastructure.yml logs -f

# 僅檢視特定服務
docker compose -f docker-compose-infrastructure.yml logs -f traefik
docker compose -f docker-compose-infrastructure.yml logs -f oauth
docker compose -f docker-compose-infrastructure.yml logs -f pihole

# 停止所有服務
docker compose -f docker-compose-infrastructure.yml down

# 重啟特定服務
docker compose -f docker-compose-infrastructure.yml restart traefik
```

### 設定驗證

```bash
# 驗證 Compose 語法與變數展開
docker compose -f docker-compose-infrastructure.yml config

# 檢查 Traefik 設定（容器內）
docker exec traefik traefik healthcheck
```

### Cron 排程服務監控與驗證

#### 1. 查看 `cron` 排程發送紀錄
由於 `cron` 服務已啟用詳細日誌，當排程被觸發時，你可以直接透過容器日誌查看發送指令：
```bash
docker logs cron
```
*正常執行時會輸出類似 `crond: USER root pid ... cmd wget...` 的紀錄。*

#### 2. 查看安全代理 `socket-proxy` 的存取紀錄
排程器所發送的重啟 API 請求會經過安全代理，你可以從中確認請求是否順利被批准與執行：
```bash
docker logs socket-proxy | grep minecraft
```
*成功時應看到 `[OK] POST /v1.41/containers/minecraft/restart` 的字樣。*

#### 3. 檢查目標容器的 Uptime
直接確認被重啟容器的運作時間與日誌：
```bash
docker ps -f name=minecraft --format "table {{.Names}}\t{{.Status}}"
```


### 憑證與 Secrets

```bash
# 建立 acme.json（首次設定）
touch appdata/traefik/acme/acme.json
echo '{}' > appdata/traefik/acme/acme.json
chmod 600 appdata/traefik/acme/acme.json

# 產生 Basic Auth 憑證
htpasswd -nb username password > secrets/basic_auth_credentials
```

---

## 存取位址（範例）

- **Traefik Dashboard（僅內網）**：`https://traefik.<DOMAINNAME_1>`（經 OAuth）
- **OAuth Portal**：`https://auth.<DOMAINNAME_1>`（目前同時掛在內/外網 HTTPS entrypoints，用於登入流程）
- **Pi-hole 管理**：`https://pihole.<DOMAINNAME_1>`（經 OAuth）
- 對外埠：80/81（HTTP）、443/444（HTTPS）、`TRAEFIK_PORT`（Traefik API；若啟用 `api.insecure=true`，務必以防火牆限制僅內網）

---

## 維護任務

### 更新容器映像

```bash
docker compose -f docker-compose-infrastructure.yml pull
docker compose -f docker-compose-infrastructure.yml up -d
```

### 修改與重新套用 Cron 排程

當你需要編輯重啟時間或新增其他容器的排程任務時，請按照下列步驟操作：

1. 編輯排程設定檔 `${DOCKERDIR}/appdata/cron/crontab`。
2. 重啟 `cron` 服務以重新載入設定：
   ```bash
   docker compose -f docker-compose-infrastructure.yml --profile network restart cron
   ```

### 備份建議

- `appdata/traefik/acme/acme.json`（Let's Encrypt 憑證）
- `appdata/traefik/rules/`（動態規則）
- `.env` 與 `secrets/`（敏感設定）

---

## 疑難排解

### Traefik 無法啟動

1. 檢查 `acme.json` 權限：`ls -la appdata/traefik/acme/acme.json`（應為 `600`）。
2. 確認 Secrets 檔案存在：`ls secrets/`（至少 `basic_auth_credentials`、`cf_dns_api_token`）。
3. 檢查 Socket Proxy：`docker logs socket-proxy`，確認 Traefik 能連 `tcp://socket-proxy:2375`。

### 憑證（ACME）問題

1. 確認 Cloudflare Token 具 Zone:DNS:Edit 權限。
2. 查看 Traefik 日誌：`docker logs traefik | grep -i acme`。
3. 確認 `auth.<DOMAINNAME_1>`、`traefik.<DOMAINNAME_1>` 等 DNS 解析正確（若走 Cloudflare 代理，需放行對應 IP）。

### OAuth 登入失敗

1. 檢查 `secrets/tfa_config` 與 `secrets/google_oauth_client_secret` 存在且內容正確。
2. 查看 oauth 容器日誌：`docker logs oauth`。
3. 確認 Google OAuth 應用已設定授權 redirect URI（例如 `https://auth.<DOMAINNAME_1>/portals/main/callback`）。

### Pi-hole 無法解析 / 管理頁打不開

1. 確認 Pi-hole 已加入 `t3_proxy` 且 IP 為 192.168.90.53（或與規則一致）。
2. 檢查 `${DATADIR}/pihole/` 權限與掛載。
3. 若經 Traefik 存取，確認 `pihole.<DOMAINNAME_1>` 的 router 與 middleware 設定正確。

---

## 參考資源

- [SimpleHomelab/Docker-Traefik](https://github.com/SimpleHomelab/Docker-Traefik)
- [Traefik v3 文件](https://doc.traefik.io/traefik/)
- [LinuxServer Socket Proxy](https://docs.linuxserver.io/images/docker-socket-proxy/)
