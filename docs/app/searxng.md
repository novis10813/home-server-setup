# SearXNG

SearXNG 是隱私友善的元搜尋引擎。本服務屬於 **App stack**，由 `docker-compose-app.yml` 管理，並透過 Traefik 提供內網 HTTPS 入口。

## 服務入口

- **網址**：`https://search.${DOMAINNAME_1}`
- **Traefik entrypoint**：`websecure-internal`
- **容器埠**：`8080`，不直接發布到 host
- **網路**：`t3_proxy`
- **中介軟體**：`chain-no-auth@file`

## 設定檔位置

| 設定檔 | 路徑 | 是否版控 |
|--------|------|----------|
| SearXNG 主設定 | `appdata/searxng/settings.yml` | 是 |
| Wikidata 引擎自定義 | `appdata/searxng/wikidata.py` | 是 |
| 引擎快取 | `appdata/searxng/engines_cache/` | 否 |

`appdata/searxng` 必須包含 `settings.yml` 與 `wikidata.py`；Compose 會把它們掛載到容器的 `/etc/searxng` 與引擎目錄。

## 常用指令

```bash
docker compose -f docker-compose-app.yml up -d searxng
docker compose -f docker-compose-app.yml ps searxng
docker compose -f docker-compose-app.yml logs -f searxng
docker compose -f docker-compose-app.yml stop searxng
```

## 備份

備份 `appdata/searxng/`。其中可能包含服務設定，不應把 runtime secrets 或敏感資料提交到 Git。

## 疑難排解

| 症狀 | 處理 |
|------|------|
| HTTPS 入口無法連線 | 檢查 Traefik labels、內部 DNS、`t3_proxy` 與 `websecure-internal` |
| 搜尋結果異常 | 檢查 `appdata/searxng/settings.yml` 的引擎設定 |
| 找不到 Wikidata 引擎 | 確認 `appdata/searxng/wikidata.py` 存在且可讀 |
