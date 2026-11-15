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
- 對外埠：80/81（HTTP）、443/444（HTTPS）、`TRAEFIK_PORT`（Traefik API；`api.insecure=true`，主機埠僅綁定 `127.0.0.1`）

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
4. Pi-hole 剛重建或重啟時，健康檢查約 30 秒內為 `starting`，期間 Traefik 不會路由它，網頁會暫時回 404。

### Tailscale 裝置無法解析或連不到內部服務

1. 確認容器運行：`docker ps | grep tailscale-dns`，並測試 `dig @<TAILSCALE_DNS_IP> pihole.<DOMAINNAME_1>` 應回 Tailscale IP。
2. 容器啟動失敗且出現 `cannot assign requested address`：Docker 比 `tailscaled` 先啟動。檢查 `systemctl show docker.service -p After` 是否含 `tailscaled.service`（見服務說明的開機順序）。
3. 確認 Tailscale 管理後台的 Global nameserver 為 Tailscale IP，且 Override DNS servers 已開啟。
4. 瀏覽器若啟用安全 DNS（DoH）指定供應商，會繞過 Tailscale DNS，需改回自動或關閉。
5. Linux 裝置需執行 `tailscale set --accept-dns=true` 才會使用 Tailscale DNS。

---

## 備份（Immich → Google Drive）

以下指令在 `/opt/docker` 執行。

```bash
# 手動備份（前景執行，可看輸出）
docker start -a restic-backup

# 查看快照
docker compose -f docker-compose-infrastructure.yml --profile backup run --rm \
  --entrypoint restic restic-backup snapshots

# 檢查倉庫結構；加 --read-data-subset=5% 可抽樣讀取資料驗證
docker compose -f docker-compose-infrastructure.yml --profile backup run --rm \
  --entrypoint restic restic-backup check

# 驗證單一檔案內容（不寫入磁碟）：與原始檔比對 SHA-256
docker compose -f docker-compose-infrastructure.yml --profile backup run --rm -T \
  --entrypoint restic restic-backup dump latest /source/library/backups/<檔名> | sha256sum

# 還原到指定資料夾
docker compose -f docker-compose-infrastructure.yml --profile backup run --rm \
  -v /tmp/restore:/restore --entrypoint restic restic-backup restore latest --target /restore
```

- 重新建立容器：`docker compose -f docker-compose-infrastructure.yml --profile backup build restic-backup`，再 `... --profile backup create restic-backup`。
- 腳本內用迴圈呼叫 `docker compose run` 時，要加 `-T` 並把標準輸入導向 `/dev/null`，否則會讀走迴圈的輸入。
- 排程確認：`docker exec cron crontab -l`；`appdata/cron/crontab` 只在 `cron` 容器啟動時載入，修改後需 `docker restart cron`。
- 失敗排查：`docker logs restic-backup`。常見原因是 Google 授權失效（OAuth 同意畫面又回到測試狀態、token 被撤銷）或 `restic_password` 與倉庫不符。
- 已驗證：首次快照約 52 GiB，`restic check` 無錯誤，抽樣 5 個檔案（含資料庫備份與照片）的 SHA-256 與原始檔一致。**Immich 資料庫的還原流程尚未實測**，實際還原時請依 Immich 官方文件操作。

---

## 災難復原（Disaster Recovery）

整台主機或系統硬碟損毀時，透過 **GitHub（Compose 與設定檔）＋ 離線保存的 Bootstrap 憑證 ＋ Google Drive（三個 `restic` 倉庫）** 重建環境。

### 事前準備（必須離線保存在密碼管理器）

- `secrets/restic_password`
- `secrets/rclone/rclone.conf`（內含 Google OAuth `client_id`、`client_secret`、`refresh_token`；若 token 過期可用同一組憑證執行 `rclone config reconnect gdrive:` 重新授權）

### Step 1：重建主機環境與 OS 前置設定

1. 安裝 `docker`、`docker-compose-plugin`、`tailscale`、`git`，並建立對應的使用者與 `homeserver` 群組（對齊 `.env` 的 `PUID` / `PGID`）。
2. 設定 Docker 在 `tailscaled` 之後啟動（否則綁定 `${TAILSCALE_DNS_IP}:53` 的 `tailscale-dns` 與 `${PAT_TAILSCALE_IP}:8010` 的 `pat` 開機會因 Tailscale 介面尚未就緒而失敗）：

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/after-tailscale.conf <<'EOF'
[Unit]
After=tailscaled.service
Wants=tailscaled.service
EOF
sudo systemctl daemon-reload
```

3. 登入 Tailscale（`sudo tailscale up`）。若新系統的 `systemd-resolved` 佔用 53 埠導致 `pihole` 無法綁定，於 `/etc/systemd/resolved.conf` 設定 `DNSStubListener=no` 後重啟 `systemd-resolved`。
4. **確認資料磁碟**：若只是系統碟損毀、`/mnt/raid1`（`DATADIR`）資料碟完好，先掛載進 `/etc/fstab`，即可跳過 Step 5 與 Step 6 的大量下載還原。
5. Clone repo 與建立暫時環境：

```bash
git clone <your-repo-url> /opt/docker
cd /opt/docker

# 建立暫時 .env 供 restic-backup 使用（完整 .env 稍後會從備份還原）
cat > .env <<'EOF'
DOCKERDIR=/opt/docker
DATADIR=/mnt/raid1
TZ=Asia/Taipei
EOF

# 建立 restic-backup 依賴的外部網路（其餘 t3_proxy / socket_proxy / ha_macvlan 由 infrastructure compose 建立）
docker network create homestack
```

### Step 2：放回 Bootstrap 憑證並驗證備份倉庫

```bash
mkdir -p secrets/rclone
# 將離線保存的內容寫入 secrets/restic_password 與 secrets/rclone/rclone.conf
chmod 600 secrets/restic_password secrets/rclone/rclone.conf

# 需要空的 market-data-backup.env 才能啟動 restic-backup（實際值稍後從 config 還原）
touch secrets/market-data-backup.env

docker compose -f docker-compose-infrastructure.yml --profile backup build restic-backup

# 驗證能正常列出 config 倉庫快照
docker compose -f docker-compose-infrastructure.yml --profile backup run --rm \
  -e RESTIC_REPOSITORY=rclone:gdrive:restic/config \
  --entrypoint restic restic-backup snapshots
```

### Step 3：還原設定、Secrets 與服務資料（`restic/config`）

```bash
mkdir -p /tmp/restore-config
docker compose -f docker-compose-infrastructure.yml --profile backup run --rm \
  -e RESTIC_REPOSITORY=rclone:gdrive:restic/config \
  -v /tmp/restore-config:/restore \
  --entrypoint restic restic-backup restore latest --target /restore

# 放回環境檔、secrets 與憑證（勿覆蓋剛放進去的 restic_password 與 rclone/）
cp /tmp/restore-config/source/docker/.env /opt/docker/.env
cp -rn /tmp/restore-config/source/docker/secrets/* /opt/docker/secrets/
install -m 600 /tmp/restore-config/source/docker/appdata/traefik/acme/acme.json /opt/docker/appdata/traefik/acme/acme.json
cp /tmp/restore-config/source/docker/appdata/couchdb/local.ini /opt/docker/appdata/couchdb/local.ini

# 放回各服務的 DATADIR（依實際 DATADIR 路徑調整）
cp -a /tmp/restore-config/source/data/. /mnt/raid1/
rm -rf /tmp/restore-config
```

> **換新機檢查**：
> - 確認主機網卡名稱是否仍為 `enp4s0`（`docker-compose-infrastructure.yml` 的 `ha_macvlan`），若不同須先修改。
> - 若新主機的 LAN IP 或 Tailscale IP（`tailscale ip -4`）有變動，更新 `.env` 的 `LAN_IP`、`TAILSCALE_DNS_IP`、`PAT_TAILSCALE_IP`，並在 Tailscale Admin Console 更新 Nameserver 指向新的 `TAILSCALE_DNS_IP`。

### Step 4：啟動基礎設施

```bash
docker compose -f docker-compose-infrastructure.yml --profile network up -d
docker compose -f docker-compose-infrastructure.yml --profile monitor up -d
docker compose -f docker-compose-infrastructure.yml --profile backup create restic-backup
```

確認 Traefik、Pi-hole、Tailscale DNS、Prometheus/Alertmanager 正常後再往下一步。

### Step 5：還原 Immich 照片與資料庫（`restic/immich`）

```bash
# 1. 還原 library（upload、backups、profile）
mkdir -p /tmp/restore-immich
docker compose -f docker-compose-infrastructure.yml --profile backup run --rm \
  -e RESTIC_REPOSITORY=rclone:gdrive:restic/immich \
  -v /tmp/restore-immich:/restore \
  --entrypoint restic restic-backup restore latest --target /restore

mkdir -p /mnt/raid1/immich/library
cp -a /tmp/restore-immich/source/library/. /mnt/raid1/immich/library/
rm -rf /tmp/restore-immich

# 2. 先單獨啟動資料庫，待 healthy 後匯入最新 .sql.gz 備份
docker compose -f docker-compose-app.yml up -d immich-database
gunzip --stdout /mnt/raid1/immich/library/backups/<最新備份>.sql.gz \
  | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
  | docker exec -i immich_postgres psql --dbname=postgres --username=postgres

# 3. 啟動全部 App 與 Media 服務
docker compose -f docker-compose-app.yml up -d
docker compose -f docker-compose-media.yml up -d
```

### Step 6：還原 Market Data 與啟動 Homestack（`restic/market-data`）

```bash
# 1. 先啟動 MinIO 並初始化 bucket
docker compose -f docker-compose-homestack.yml up -d minio minio-init

# 2. 從 restic/market-data 還原到暫存目錄，再同步回 MinIO
mkdir -p /mnt/raid1/restic-backup/market-data-staging
docker compose -f docker-compose-infrastructure.yml --profile backup run --rm \
  -e RESTIC_REPOSITORY=rclone:gdrive:restic/market-data \
  --entrypoint restic restic-backup restore latest --target /

# 3. 使用 secrets/minio.env 的管理員帳號（備份帳號僅唯讀）將 /staging 回傳到 minio:market-data
docker compose -f docker-compose-infrastructure.yml --profile backup run --rm \
  --env-file secrets/minio.env \
  --entrypoint sh restic-backup -c '
    RCLONE_CONFIG_MINIO_ACCESS_KEY_ID="$MINIO_ROOT_USER" \
    RCLONE_CONFIG_MINIO_SECRET_ACCESS_KEY="$MINIO_ROOT_PASSWORD" \
    rclone copy /staging minio:market-data --transfers 8 --checkers 16
  '

# 4. 啟動剩餘 Homestack 服務
docker compose -f docker-compose-homestack.yml up -d
```

> **注意**：`backup.sh` 預設不備份 CouchDB 資料目錄、Kavita/Calibre 書庫、WebDAV（Zotero）與 PAT Postgres，重建後這些服務需從其他裝置重新同步或手動恢復。

---

## 參考資源

- [SimpleHomelab/Docker-Traefik](https://github.com/SimpleHomelab/Docker-Traefik)
- [Traefik v3 文件](https://doc.traefik.io/traefik/)
- [LinuxServer Socket Proxy](https://docs.linuxserver.io/images/docker-socket-proxy/)
