# NATS

[NATS Server](https://docs.nats.io/) 在本專案中作為 Home stack 的訊息與 **JetStream** 持久化串流後端。客戶端使用 **`nats://`（TCP 4222）**；**HTTP 監控**（8222）僅透過 Traefik 內網路由提供。

## 存取方式

| 端點 | 說明 |
|------|------|
| **客戶端** | 容器內連 `nats:4222`（須與 `nats` 共用一張 Docker 網路，例如 `t3_proxy`；見下方「本機開發」） |
| **監控（HTTP）** | `https://nats.${DOMAINNAME_1}` — `websecure-internal`、`chain-no-auth@file`，後端連線至容器 **8222** |

**未**將 **4222** publish 至主機時，宿主機上的程式無法使用 `localhost:4222`，需改接 Docker 網路或在 Compose 中加上 `127.0.0.1:4222:4222`（僅本機）。

## 設定與資料路徑

| 路徑 | 用途 |
|------|------|
| `compose/homestack/nats.yml` | 服務定義（映像、volume、Traefik labels、`t3_proxy`） |
| `appdata/nats/nats-server.conf` | 主設定（port、JetStream、`server_name`）— **版控** |
| `${DATADIR}/nats` | JetStream 等執行時資料（掛載為容器內 `/data`）— **備份對象** |

## 認證

**無認證**。NATS port 4222 未對外 publish，僅限 `t3_proxy` Docker 網路內的容器直接連線，以網路隔離作為安全邊界。客戶端連線 URL：`nats://nats:4222`。

## JetStream 與單機模式

- **JetStream** 存於 `store_dir: /data`（即 `${DATADIR}/nats`），並設定記憶體／檔案上限（見 `nats-server.conf`）。
- 目前為 **單機 JetStream**：設定中 **勿**加入 `cluster {}`；未設定 `cluster.routes` 時啟用 cluster 會導致 JetStream 無法啟動。若未來要多節點叢集，需另行設定 cluster 與 routes。

## 環境變數

`.env` / `.env.example` 中與 NATS 相關者例如：

- **`NATS_VERSION`** — 映像標籤（預設與 compose 內一致即可）

## 常用指令

```bash
docker compose -f docker-compose-homestack.yml up -d nats
docker compose -f docker-compose-homestack.yml exec nats nats-server -t -c /nats-server.conf
```

調整 `appdata/nats/nats-server.conf` 後，請 **`up -d` 或 `--force-recreate nats`** 使設定生效。

## 本機開發連線

1. **在容器內跑測試**（與 NATS 同一網路）：  
   `docker run --rm -it --network t3_proxy ...`，連線位址 `nats://nats:4222`。
2. **在主機跑 Python / 其它程式**：對 Compose 的 `nats` 服務加上 `ports: - "127.0.0.1:4222:4222"`，或自行評估是否使用。

## 參考

- [NATS Server 文件](https://docs.nats.io/running-a-nats-service/introduction)
- [JetStream](https://docs.nats.io/nats-concepts/jetstream)
