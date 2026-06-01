# Home stack（自訂服務）

**Home stack** 用 **`docker-compose-homestack.yml`** 管理本機開發或家用的自訂程式與基礎元件（與 Infrastructure、App、Media 分離），目前包含 NATS、QuestDB 與交易平台服務。

## Compose 主檔

| 項目 | 說明 |
|------|------|
| **檔案** | `docker-compose-homestack.yml` |
| **Secrets** | 無（NATS 不使用認證，依賴 Docker 網路隔離） |
| **網路** | `t3_proxy`（external，與 Traefik 與其它已代理服務互通）、`homestack`（內部 bridge，供日後只給自訂服務使用） |

## 服務一覽

| 服務 | 說明 | 詳細文件 |
|------|------|----------|
| NATS | 訊息佇列與 JetStream；客戶端協定 **不**經 Traefik 暴露 | [NATS](nats.md) |
| crypto-relay | Binance WebSocket → NATS 市場資料 relay | root repo `ROADMAP.md` |
| financial-dashboard | `dash.${DOMAINNAME_1}` liquidity 與 recording policies UI | root repo `ROADMAP.md` |
| market-data-recorder | SQLite 長期錄製政策 → QuestDB；admin API 僅供內網反代 | root repo `ROADMAP.md` |

## 啟動與維護

```bash
cd ${DOCKERDIR}

# 首次請確認 appdata/nats/nats-server.conf 已就緒
docker compose -f docker-compose-homestack.yml up -d

docker compose -f docker-compose-homestack.yml logs -f nats
docker compose -f docker-compose-homestack.yml down
```

環境變數範例見根目錄 `.env.example`（`NATS_VERSION` 等）。

## Recorder 資料與管理 API

`market-data-recorder` 將 SQLite policy database 掛載在
`${DATADIR}/market-data-recorder/recording.db`。這是執行時資料，不放在
`${DOCKERDIR}`。

Recorder admin server 在容器內監聽 `:8080`，僅加入 `t3_proxy` / `homestack`
內網，不設定 Traefik labels。`financial-dashboard` 的 Nginx 將
`/api/recordings` 直接反代到 `market-data-recorder:8080`，沿用
`dash.${DOMAINNAME_1}` 的 OAuth 保護。
