# Hermes Agent

[Hermes Agent](https://github.com/NousResearch/hermes-agent) 是 Nous Research 的可自架 AI agent，支援持久化記憶、工具呼叫、messaging gateway，以及 OpenAI-compatible API。本服務屬於 **AI stack**，不是一般 App stack。

## 架構與網路邊界

```text
Traefik
  ├─ https://hermes-api.${DOMAINNAME_1} → Hermes API :8642
  └─ https://hermes.${DOMAINNAME_1}     → Hermes Dashboard :9119

Hermes
  ├─ /opt/data ← host ${DATADIR}/hermes
  ├─ t3_proxy  ← Traefik 對外部（內部 HTTPS）入口
  └─ ai_services ← SearXNG 等 AI service-to-service 流量

Hermes sandbox
  └─ ai_control → 專用 Docker control plane / socket proxy → Docker daemon
```

目前 compose 服務的基礎網路是 `t3_proxy`。若啟用 sandbox/backend，`ai_services` 與 `ai_control` 是必須明確配置的隔離邊界，不應以把 host Docker socket 直接掛進 Hermes 取代。`ai_control` 只承載 Hermes 對 control plane 的 Docker API 流量；它不是讓 sandbox 直接接觸管理網路的捷徑。

| 項目 | 設定 |
|------|------|
| Compose service | `hermes` |
| Container | `hermes` |
| Image | `nousresearch/hermes-agent:${HERMES_VERSION:-latest}` |
| Command | `gateway run` |
| Runtime data | `${DATADIR}/hermes` |
| API | `8642`，需要 Hermes `API_SERVER_KEY` |
| Dashboard | `9119`，需要 Hermes 自身的認證設定 |
| Proxy network | `t3_proxy` |
| AI service network | `ai_services`（sandbox 與 AI service-to-service 流量） |
| Docker control network | `ai_control`（僅限 control plane 路由） |
| 外部 host port | 無，僅透過 Traefik `websecure-internal` |

## Host-visible data path 契約

Hermes 的資料目錄必須以同一個 host-visible 路徑提供給需要讀寫它的控制平面與 sandbox。標準契約是：

```text
host:      ${DATADIR}/hermes
container: /opt/data
```

也就是說，`DOCKER_HOST` 指向的 Docker daemon 在建立 sandbox container 時，必須能看見並解析 host 上的 `${DATADIR}/hermes`。不能只把 `/opt/data` 當成 Hermes container 內的路徑，或改用 daemon host 不存在的相對路徑；否則 sandbox 的 bind mount 會失敗，或意外掛載到錯誤位置。啟用前請確認 `${DATADIR}` 對 Docker daemon 與其 runtime 都是可用的絕對 host 路徑。

## 首次初始化

先確認 Infrastructure stack 已建立 `t3_proxy`，並準備 runtime data 目錄：

```bash
docker network inspect t3_proxy >/dev/null
mkdir -p "${DATADIR}/hermes"
```

官方建議使用 one-shot container 執行 setup wizard：

```bash
docker run --rm -it \
  -v "${DATADIR}/hermes:/opt/data" \
  nousresearch/hermes-agent:${HERMES_VERSION:-latest} setup
```

setup wizard 可選擇 Nous Portal 或其他 provider。也可以在容器內使用：

```bash
hermes model
hermes doctor
```

本 repo 的 Hermes service 不會直接掛載 Docker socket，也不會將 API 或 Dashboard port publish 到 host。

## API 與 Dashboard 認證

Hermes 的設定與 credentials 會持久化在：

```text
${DATADIR}/hermes/.env
```

至少需要配置 API server key；實際 secret 只應存在 runtime data，不得提交到 Git：

```dotenv
API_SERVER_KEY=<長隨機 API key>
```

Dashboard 綁定 `0.0.0.0` 時，也需要 Hermes 自身的 authentication provider。初次部署可使用 Basic Auth：

```dotenv
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=<長隨機密碼>
HERMES_DASHBOARD_BASIC_AUTH_SECRET=<穩定的長隨機 secret>
```

Traefik 入口的認證分層如下：

- API：`chain-no-auth@file`，由 Hermes `API_SERVER_KEY` 負責 API authentication。
- Dashboard：`chain-oauth@file`，另外保留 Hermes 自身的 authentication provider。

## AI service 與 sandbox

Hermes 與 SearXNG 等 AI 服務之間，應使用 `ai_services`；例如 sandbox 需要搜尋時，透過服務名稱與內部 port 連線，而不是暴露 host port。`t3_proxy` 是 Traefik 對外部入口網路，不能當成 sandbox 的唯一隔離措施。

若需要 Hermes 建立或管理 sandbox，設定會使用 Docker client 的 `DOCKER_HOST` 指向專用 control plane，例如：

```dotenv
DOCKER_HOST=tcp://ai-control:2375
```

實際 hostname、TLS 與 API 權限必須與 AI compose 定義一致；不要把 Docker socket 路徑或 credential 寫入本文件。sandbox 應加入 `ai_services`，並依需求限制 CPU、memory、filesystem 與 capability。

### Socket Proxy 的真實安全邊界

專用 Socket Proxy 是 **route gate**：它可以限制 Hermes 哪些 Docker API route 能被送到 daemon，降低誤用面；但 stock Socket Proxy 不能限制 `containers/create` payload 內要求的 bind mounts、capabilities、privileged 設定或其他 container 權限。因此它不是強 sandbox，也不能把 host Docker 高權限風險變成低權限風險。

只要 Hermes 能讓 Docker daemon 建立具 host filesystem、host network、特權 capability 或其他高權限設定的 container，就仍可能取得 host Docker 等級的控制能力。不要把 route gate 宣稱成安全邊界；需要更強隔離時，應使用獨立 Docker daemon、rootless Docker、受限 workspace，以及對 create payload 做 policy enforcement 的 control plane。

未來升級方向是將 AI control plane 遷移到 rootless Docker，並重新驗證 volume、network、UID/GID 與 sandbox 行為。在 rootless 部署完成前，應把 `DOCKER_HOST` 視為通往 host Docker daemon 的高權限介面，僅在明確接受此風險與完成 policy review 後啟用。

## 使用現有 CLIProxyAPI

若要讓 Hermes 使用 CLIProxyAPI，容器內部 endpoint 為：

```text
http://cli-proxy-api:8317/v1
```

先確認 CLIProxyAPI 已有可用的 provider credential，再編輯：

```text
${DATADIR}/hermes/config.yaml
```

不要把實際 key 寫入 `config.yaml` 或 repository。`model.default` 必須使用 CLIProxyAPI 實際回傳的 model ID，不要自行猜測。

## 啟動、更新與備份

完成 setup 與設定後，再由管理者自行決定是否啟動：

```bash
docker compose -f docker-compose-ai.yml up -d hermes
docker compose -f docker-compose-ai.yml ps hermes
docker compose -f docker-compose-ai.yml logs -f hermes
```

入口為 `https://hermes-api.${DOMAINNAME_1}` 與 `https://hermes.${DOMAINNAME_1}`。更新 image 後：

```bash
docker compose -f docker-compose-ai.yml pull hermes
docker compose -f docker-compose-ai.yml up -d hermes
```

需要可重現部署時，請設定經測試的 `HERMES_VERSION`，不要長期依賴 `latest`。至少備份：

```text
${DATADIR}/hermes/
```

其中可能包含 `config.yaml`、`.env` 與 provider credentials、sessions、memories、skills、profiles、gateway 設定及 logs。備份檔同樣不得提交到 Git。

## 參考文件

- [Hermes Agent GitHub](https://github.com/NousResearch/hermes-agent)
- [Hermes Docker deployment](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/docker.md)
- [Hermes installation](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/getting-started/installation.md)
- [Hermes provider configuration](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/providers.md)
