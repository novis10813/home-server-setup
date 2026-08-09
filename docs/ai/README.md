# AI stack

本專案的 **AI stack** 集中管理 AI agent、搜尋工具與其他供 AI workflow 使用的服務，與一般 App stack 分開。服務 compose 入口為 `docker-compose-ai.yml`；本文件區的服務仍可透過 Infrastructure stack 建立的 Traefik 與外部網路提供內部 HTTPS 入口。

## 服務清單

| 服務 | 用途 | 說明 |
|------|------|------|
| [Hermes Agent](hermes.md) | 自架 AI agent | Gateway、Dashboard、持久化記憶與可選的 sandbox/backend 控制平面 |
| [SearXNG](searxng.md) | 隱私友善元搜尋 | 提供 AI agent 使用的搜尋引擎，並提供內部 HTTPS 入口 |

## Compose 主檔

- **檔案**：`docker-compose-ai.yml`
- **服務定義**：AI stack 的 compose include 檔
- **前置條件**：先建立 Infrastructure stack，以及其提供的 `t3_proxy` 外部網路。

啟動或檢查 AI 服務時使用：

```bash
docker compose -f docker-compose-ai.yml up -d
docker compose -f docker-compose-ai.yml ps
```

AI stack 尚未啟用的服務，不應以 `docker-compose-app.yml` 啟動；App 文件中的舊連結僅為相容 stub，正式內容請以本區為準。
