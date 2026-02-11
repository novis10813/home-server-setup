# Media

本專案的 **Media** 類服務使用 `docker-compose-media.yml` 管理，透過外部網路 `t3_proxy` 交由 Traefik 反向代理。

## Compose 主檔

- **檔案**：`docker-compose-media.yml`
- **include**：`compose/media/*.yml`

## 服務清單

| 服務 | Host | 內網（Internal） | 外網（External） | 認證 |
|------|------|------------------|------------------|------|
| Jellyfin | `jellyfin.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | Jellyfin 內建登入 + `chain-no-auth@file` |
| Jellyseerr | `jellyseerr.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | Jellyseerr 內建登入 + `chain-no-auth@file` |
| Sonarr | `sonarr.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | Sonarr 內建登入 + `chain-no-auth@file` |
| Radarr | `radarr.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | Radarr 內建登入 + `chain-no-auth@file` |
| Prowlarr | `prowlarr.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | Prowlarr 內建登入 + `chain-no-auth@file` |
| qBittorrent | `qbittorrent.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | qBittorrent 內建登入 + `chain-no-auth@file` |

## 目錄結構（Hardlink 友善）

所有服務共用 `${DATADIR}/media/`，確保 Sonarr / Radarr 可以用 hardlink 方式搬檔，避免重複占用空間。

```
${DATADIR}/media/
├── downloads/
│   ├── tv/      # Sonarr category
│   └── movies/  # Radarr category
├── tv/          # Sonarr library
└── movies/      # Radarr library
```

## 啟動指令

```bash
docker compose -f docker-compose-media.yml up -d
```

## 初次設定建議

1. **qBittorrent**
   - 登入後修改預設密碼
   - 下載路徑設定為 `/data/media/downloads`
   - 建立 category：`tv`、`movies`
2. **Sonarr / Radarr**
   - 下載客戶端設定 qBittorrent（Host：`qbittorrent`，Port：`8080`）
   - Root Folder：
     - Sonarr：`/data/media/tv`
     - Radarr：`/data/media/movies`
3. **Prowlarr**
   - 加入 Indexer（例如 Nyaa）
   - 設定 Application 連接 Sonarr / Radarr
4. **Jellyseerr**
   - 連接 Jellyfin（Host：`http://jellyfin:8096`）
   - 選擇要同步的 Libraries
   - （可選）連接 Sonarr / Radarr 做自動請求

## Jellyfin 硬體加速（AMD Vega 11）

Jellyfin 已掛載 `/dev/dri`，可在 **Dashboard → Playback** 啟用 VAAPI 硬體加速轉碼。
