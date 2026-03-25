# Home stack（自訂服務）

**Home stack** 用 **`docker-compose-homestack.yml`** 管理本機開發或家用的自訂程式與基礎元件（與 Infrastructure、App、Media 分離），目前包含 **NATS**（訊息 / JetStream），後續可擴充同類服務。

## Compose 主檔

| 項目 | 說明 |
|------|------|
| **檔案** | `docker-compose-homestack.yml` |
| **Secrets** | `nats_auth` → `${DOCKERDIR}/secrets/nats_auth.conf`（見 `secrets/README.md`） |
| **網路** | `t3_proxy`（external，與 Traefik 與其它已代理服務互通）、`homestack`（內部 bridge，供日後只給自訂服務使用） |

## 服務一覽

| 服務 | 說明 | 詳細文件 |
|------|------|----------|
| NATS | 訊息佇列與 JetStream；客戶端協定 **不**經 Traefik 暴露 | [NATS](nats.md) |

## 啟動與維護

```bash
cd ${DOCKERDIR}

# 首次請確認 secrets/nats_auth.conf、appdata/nats/nats-server.conf 已就緒
docker compose -f docker-compose-homestack.yml up -d

docker compose -f docker-compose-homestack.yml logs -f nats
docker compose -f docker-compose-homestack.yml down
```

環境變數範例見根目錄 `.env.example`（`NATS_VERSION` 等）。
