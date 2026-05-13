# SearXNG

隱私友善的元搜尋引擎 (Metasearch Engine)，主要用於聚合多個搜尋引擎的結果，並提供給 AI Agent 使用。

## 架構

```
用戶/AI Agent ─HTTPS─▶ Traefik (`websecure-internal`) ─▶ searxng (port 8080, `chain-no-auth`)
                                                      └─ 網路: `t3_proxy`
```

| 容器 | 角色 | 對外埠 | 加入網路 |
|------|------|--------|----------|
| `searxng` | 搜尋引擎核心 | 無直接暴露 (經由 Traefik) | `t3_proxy` |

## 環境變數（.env）

| 變數 | 說明 | 預設 |
|------|------|------|
| `TZ` | 時區 | `${TZ}` |
| `DOMAINNAME_1` | 主要網域 (用於生成 `SEARXNG_BASE_URL`) | `${DOMAINNAME_1}` |

## 設定檔位置

| 設定檔 | 路徑 | 是否版控 |
|--------|------|----------|
| SearXNG 主設定 | `appdata/searxng/settings.yml` | ✅ |
| Wikidata 引擎自定義 | `appdata/searxng/wikidata.py` | ✅ (用於修正 [searxng#6051](https://github.com/searxng/searxng/issues/6051)) |
| 引擎快取 | `appdata/searxng/engines_cache/` | ❌ |

> **注意**：`appdata/searxng` 目錄應包含 `settings.yml` 與 `wikidata.py`。因為 [searxng#6051](https://github.com/searxng/searxng/issues/6051) 這個 Bug，我們必須掛載自定義的 `wikidata.py` 來修正引擎行為。

## 第一次部署

```bash
# 1. 建立 appdata 必要目錄
mkdir -p /opt/docker/appdata/searxng/engines_cache

# 2. 準備設定檔 (確保 settings.yml 與 wikidata.py 已放置於 appdata/searxng/)

# 3. 啟動服務
docker compose -f docker-compose-app.yml up -d searxng
```

## 常用指令

```bash
# 啟動 / 停止
docker compose -f docker-compose-app.yml up -d searxng
docker compose -f docker-compose-app.yml stop searxng

# 查看 Log
docker compose -f docker-compose-app.yml logs -f searxng
```

## 備份

備份設定檔：

```bash
tar -czvf searxng-config-$(date +%Y%m%d-%H%M%S).tar.gz -C "/opt/docker/appdata" searxng
```

## 疑難排解

| 症狀 | 可能原因 | 處理 |
|------|----------|------|
| 搜尋結果不正確 | `settings.yml` 引擎配置錯誤 | 檢查 `appdata/searxng/settings.yml` |
| 找不到 Wikidata 引擎 | `wikidata.py` 檔案缺失或路徑錯誤 | 確認 `appdata/searxng/wikidata.py` 已存在 |
