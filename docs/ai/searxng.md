# SearXNG

SearXNG 是隱私友善的元搜尋引擎，聚合多個搜尋引擎結果，主要供 AI agent 與內部使用者查詢。本服務屬於 **AI stack**，由 `docker-compose-ai.yml` 管理。

## 服務入口與分工

SearXNG 有兩種不同用途的入口：

- **容器內部入口**：`http://searxng:8080`。AI agent、Hermes sandbox 或同一 `ai_services` 網路中的服務使用此 endpoint，流量不需要繞過 Traefik，也不應依賴 host port。
- **Traefik HTTPS endpoint**：`https://search.${DOMAINNAME_1}`。供內部使用者或不在 `ai_services` 的受管制客戶端使用，透過 `websecure-internal` 提供 TLS 與入口策略。

Traefik HTTPS endpoint 是使用者入口；`http://searxng:8080` 是 service-to-service 入口。兩者不是互相替代，也不代表容器內部 HTTP 會被公開到 host。

```text
AI agent / sandbox ── ai_services ──▶ http://searxng:8080
使用者 ── HTTPS ──▶ Traefik (websecure-internal) ──▶ searxng:8080
```

| 容器 | 角色 | 對外埠 | 網路 |
|------|------|--------|------|
| `searxng` | 搜尋引擎核心 | 無直接暴露（經由 Traefik） | `ai_services`、`t3_proxy` |

## 設定檔位置

| 設定檔 | 路徑 | 是否版控 |
|--------|------|----------|
| SearXNG 主設定 | `appdata/searxng/settings.yml` | 是 |
| Wikidata 引擎自定義 | `appdata/searxng/wikidata.py` | 是（修正 [searxng#6051](https://github.com/searxng/searxng/issues/6051)） |
| 引擎快取 | `appdata/searxng/engines_cache/` | 否 |

> **注意**：`appdata/searxng` 目錄應包含 `settings.yml` 與 `wikidata.py`。因為 [searxng#6051](https://github.com/searxng/searxng/issues/6051) 這個 bug，必須掛載自定義的 `wikidata.py` 來修正引擎行為。

## 第一次部署

```bash
# 1. 建立 appdata 必要目錄
mkdir -p /opt/docker/appdata/searxng/engines_cache

# 2. 準備設定檔（確保 settings.yml 與 wikidata.py 已放置於 appdata/searxng/）

# 3. 啟動服務
docker compose -f docker-compose-ai.yml up -d searxng
```

## 常用指令

```bash
docker compose -f docker-compose-ai.yml up -d searxng
docker compose -f docker-compose-ai.yml stop searxng
docker compose -f docker-compose-ai.yml logs -f searxng
```

## 環境變數

| 變數 | 說明 | 預設 |
|------|------|------|
| `TZ` | 時區 | `${TZ}` |
| `DOMAINNAME_1` | 主要網域（用於生成 `SEARXNG_BASE_URL`） | `${DOMAINNAME_1}` |

## 備份

備份設定檔：

```bash
tar -czvf searxng-config-$(date +%Y%m%d-%H%M%S).tar.gz -C "/opt/docker/appdata" searxng
```

備份檔可能包含服務設定，不應將 runtime secrets 或含敏感資料的檔案提交到 Git。

## 疑難排解

| 症狀 | 可能原因 | 處理 |
|------|----------|------|
| AI agent 無法搜尋 | 未加入 `ai_services`，或使用了錯誤的入口 | 從 AI service 網路測試 `http://searxng:8080`；不要在容器內使用 Traefik hostname 取代內部 endpoint |
| 使用者 HTTPS 入口無法連線 | Traefik router、DNS 或 `websecure-internal` 設定問題 | 檢查 Traefik labels、內部 DNS 與 TLS 入口 |
| 搜尋結果不正確 | `settings.yml` 引擎配置錯誤 | 檢查 `appdata/searxng/settings.yml` |
| 找不到 Wikidata 引擎 | `wikidata.py` 檔案缺失或路徑錯誤 | 確認 `appdata/searxng/wikidata.py` 已存在 |
