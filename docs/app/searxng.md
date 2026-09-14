# SearXNG

SearXNG 是隱私友善的元搜尋引擎。本服務屬於 **App stack**，由 `docker-compose-app.yml` 管理，並透過 Traefik 提供內網 HTTPS 入口（公開 DNS 無 A record，外網不可達）。

## 架構

```
客戶端 (內網 / tailnet)
  → Traefik (websecure-internal :443)
      router: searxng-rtr
      middlewares: middlewares-rate-limit-searxng@file, chain-no-auth@file
  → searxng-nginx (結果快取層, t3_proxy)
      /search 60s、/autocompleter 300s、上游錯誤回 stale
  → searxng (搜尋本體, t3_proxy)
  → 上游引擎 (brave、bing、wikipedia ...)
```

- **網址**：`https://search.${DOMAINNAME_1}`
- **Traefik entrypoint**：`websecure-internal`
- **網路**：`t3_proxy`；Traefik 路由到 `searxng-nginx`（非 `searxng`）
- **JSON API**：`/search?format=json`（供 AI agent 使用）

### 快取（searxng-nginx）

- `/search`：60 秒；cache key 含搜尋偏好 cookies（categories/language/locale/safesearch/engines），不同偏好不共用
- `/autocompleter`：300 秒
- `proxy_cache_use_stale error timeout updating ...`：上游引擎掛掉時回上次的結果
- 響應 header `X-Cache-Status`（MISS/HIT）可觀察命中率
- 快取在容器內（`max_size=256m`、`inactive=24h`），**不持久化**——TTL 短，重建容器不影響

### Rate limit（Traefik middleware）

- `middlewares-rate-limit-searxng`（`appdata/traefik/rules/middlewares-rate-limit.yml`）：token bucket，**每客戶端 IP** 持續 30 req/min、burst 100
- 超過回 429；正常瀏覽器頁面載入與 JSON API 使用不受影響，只壓住跑飛的 script
- 注意：這限的是「客戶端 → 本實例」的流量，**不是** SearXNG → 上游引擎的流量；減少上游負載靠的是快取與引擎選擇

### 引擎選擇（重要）

本 server 的對外 IP 曾被多個上游引擎標記（2026-09 日誌：duckduckgo 大量 CAPTCHA、startpage CAPTCHA、wikipedia 間歇 429、karmasearch/mojeek 403）。`appdata/searxng/settings.yml` 的 `engines:` 區塊因此**停用**了這些引擎，避免每次搜尋都撞牆並加深封鎖；目前主力為 **brave** 與 **bing**（含 zh-TW），google 對本 IP 靜默回 0 結果（保留觀察）。

- 上游引擎對被標記 IP 的封鎖通常數天至數週隨請求量下降而衰減
- 想重新啟用某引擎：把 `settings.yml` 對應條目改為 `disabled: false`，`docker compose -f docker-compose-app.yml up -d --force-recreate searxng`，觀察 `docker logs searxng` 是否仍有該引擎的 CAPTCHA/429/403
- 判斷引擎健康：`server-timing` 響應 header 列出實際運行的引擎；`unresponsive_engines`（JSON API）或容器日誌 ERROR 列出被擋的

## 設定檔位置

| 設定檔 | 路徑 | 是否版控 |
|--------|------|----------|
| SearXNG 主設定（含引擎清單） | `appdata/searxng/settings.yml` | 是 |
| nginx 快取設定 | `appdata/searxng/nginx.conf` | 是 |
| Wikidata 引擎自定義 | `appdata/searxng/wikidata.py` | 是 |
| 引擎快取 | `appdata/searxng/engines_cache/` | 否 |
| Rate limit middleware | `appdata/traefik/rules/middlewares-rate-limit.yml` | 是 |

`appdata/searxng` 必須包含 `settings.yml` 與 `wikidata.py`；Compose 會把 `settings.yml`、`wikidata.py`、`nginx.conf` 掛載到對應容器。

## 常用指令

```bash
# 改動 settings.yml 後必須 --force-recreate（bind mount 變動不會自動重建）
docker compose -f docker-compose-app.yml up -d --force-recreate searxng
docker compose -f docker-compose-app.yml up -d searxng-nginx
docker compose -f docker-compose-app.yml ps searxng searxng-nginx
docker compose -f docker-compose-app.yml logs -f searxng

# 快取命中觀察
curl -sk -D- -o /dev/null 'https://search.novis.page/search?q=test&format=json' | grep -i x-cache-status
```

## 備份

備份 `appdata/searxng/`。其中可能包含服務設定，不應把 runtime secrets 或敏感資料提交到 Git。nginx 快取不持久化，無須備份。

## 疑難排解

| 症狀 | 處理 |
|------|------|
| HTTPS 入口無法連線 | 檢查 Traefik labels（在 `searxng-nginx` 服務上）、`docker compose ... config`、`t3_proxy` 與 `websecure-internal`；用 `http://127.0.0.1:8080/api/http/routers` 看 router 的 `status`/`error` |
| router `status: disabled` | 看 API 的 `error` 欄位（常見：middleware 漏寫 `@file` provider 後綴） |
| 搜尋結果異常 / 0 結果 | 看 JSON 的 `unresponsive_engines` 與 `docker logs searxng` 的引擎 ERROR；被擋引擎在 `settings.yml` 停用，健康引擎（brave/bing）會自動在 suspend 期後恢復 |
| 上游引擎 CAPTCHA/429 頻繁 | 先減量（快取/限流已在上線）；數週後日誌若持續乾淨，再逐一重啟被停用的引擎 |
| 429 來自本實例 | `middlewares-rate-limit-searxng` 的 per-IP 上限（30/min）；確認是客戶端行為異常，勿隨意調高 |
| 找不到 Wikidata 引擎 | 確認 `appdata/searxng/wikidata.py` 存在且可讀 |
