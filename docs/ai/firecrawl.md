# Firecrawl

[Firecrawl](https://github.com/mendableai/firecrawl) 是專為 LLM 設計的自架網頁抓取引擎，負責 Hermes Agent 的 `web_extract` 工具（`web.extract_backend: firecrawl`）。本服務屬於 **AI stack**，由 `docker-compose-ai.yml` 管理。

## 架構與網路邊界

```text
Hermes (ai_services) ──▶ http://firecrawl:3002
                               │
                    firecrawl_internal（internal bridge）
                               ├─ firecrawl-playwright :3000
                               └─ firecrawl-redis      :6379
```

Firecrawl API 容器加入 `ai_services`（供 Hermes 呼叫）與 `firecrawl_internal`（與 playwright/redis 通訊）。`playwright-service` 與 `redis` 僅在 `firecrawl_internal`，不對外暴露。本服務**不掛 Traefik**，亦不開啟 `USE_DB_AUTHENTICATION`；完全依賴 Docker 網路隔離限制存取範圍。

| 容器 | 角色 | 網路 |
|------|------|------|
| `firecrawl` | REST API（`/v1/scrape`） | `ai_services` + `firecrawl_internal` |
| `firecrawl-playwright` | Headless Chromium 渲染引擎 | `firecrawl_internal` |
| `firecrawl-redis` | Task queue（BullMQ） | `firecrawl_internal` |

> **注意**：目前僅部署同步 `/v1/scrape`（單頁擷取），不含 `worker` 容器，故不支援非同步 `/v1/crawl` 全站爬蟲。

## 首次啟動

```bash
docker compose -f docker-compose-ai.yml up -d firecrawl firecrawl-playwright firecrawl-redis
docker compose -f docker-compose-ai.yml logs -f firecrawl
```

## 啟用 Hermes web_extract

1. **確認 `FIRECRAWL_API_URL` 已注入 Hermes 容器**（由 `compose/ai/hermes.yml` 設定，值為 `http://firecrawl:3002`）。

2. **編輯 Hermes 設定檔**，指定 extract backend：

   ```bash
   # 在 host 上編輯，或 exec 進 hermes 容器
   vi ${DATADIR}/hermes/config.yaml
   ```

   ```yaml
   web:
     search_backend: "searxng"
     extract_backend: "firecrawl"
   ```

3. **重啟 Hermes** 使設定生效：

   ```bash
   docker compose -f docker-compose-ai.yml restart hermes
   ```

4. **驗證工具可用**：

   ```bash
   docker exec hermes hermes doctor
   # 應顯示 ✓ web 工具可用
   ```

## 環境變數

`.env` 中可覆寫資源上限：

| 變數 | 說明 | 預設 |
|------|------|------|
| `FIRECRAWL_VERSION` | API 映像標籤 | `latest` |
| `FIRECRAWL_PLAYWRIGHT_VERSION` | Playwright 映像標籤 | `latest` |
| `FIRECRAWL_MEMORY_LIMIT` | API 容器記憶體上限 | `1g` |
| `FIRECRAWL_CPU_LIMIT` | API 容器 CPU 上限 | `1.0` |
| `FIRECRAWL_PLAYWRIGHT_MEMORY_LIMIT` | Playwright 記憶體上限 | `2g` |
| `FIRECRAWL_PLAYWRIGHT_CPU_LIMIT` | Playwright CPU 上限 | `2.0` |
| `FIRECRAWL_REDIS_MEMORY_LIMIT` | Redis 記憶體上限 | `256m` |
| `FIRECRAWL_REDIS_CPU_LIMIT` | Redis CPU 上限 | `0.25` |

## 常用指令

```bash
# 啟動
docker compose -f docker-compose-ai.yml up -d firecrawl firecrawl-playwright firecrawl-redis

# 查看日誌
docker compose -f docker-compose-ai.yml logs -f firecrawl

# 停止
docker compose -f docker-compose-ai.yml stop firecrawl firecrawl-playwright firecrawl-redis

# 快速測試 API（在 hermes 容器內）
docker exec hermes curl -s http://firecrawl:3002/v1/scrape \
  -X POST -H "Content-Type: application/json" \
  -d '{"url": "https://example.com", "formats": ["markdown"]}' | python3 -m json.tool
```

## 疑難排解

| 症狀 | 可能原因 | 處理 |
|------|----------|------|
| `web_extract` 仍回報 SearXNG 錯誤 | `config.yaml` 未更新或 Hermes 未重啟 | 確認 `web.extract_backend: firecrawl`，重啟 Hermes |
| `firecrawl` API 連線失敗 | 容器未啟動或 `ai_services` 網路問題 | 從 hermes 容器測試 `curl http://firecrawl:3002` |
| Playwright OOM Crash | `shm_size` 不足或記憶體上限太低 | 預設已設 `shm_size: 1g`；若仍崩潰，調高 `FIRECRAWL_PLAYWRIGHT_MEMORY_LIMIT` |

## 參考文件

- [Firecrawl GitHub](https://github.com/mendableai/firecrawl)
- [Firecrawl Self-Host Guide](https://docs.firecrawl.dev/self-host/guide)
