# Hermes Agent

[Hermes Agent](https://github.com/NousResearch/hermes-agent) 是 Nous Research 的可自架 AI agent，支援持久化記憶、工具呼叫、messaging gateway，以及 OpenAI-compatible API。本服務屬於 **AI stack**，不是一般 App stack。

## 架構與網路邊界

```text
Traefik
  ├─ https://hermes-api.${DOMAINNAME_1} → Hermes API :8642
  └─ https://hermes.${DOMAINNAME_1}     → Hermes Dashboard :9119

Hermes
  ├─ /opt/data ← host ${DATADIR}/hermes（相容掛載）
  ├─ ${DATADIR}/hermes ← host 同路徑掛載（sandbox bind source）
  ├─ t3_proxy ← Traefik 對外部（內部 HTTPS）入口
  ├─ ai_services ← SearXNG 等 AI service-to-service 流量
  └─ ai_control → hermes-socket-proxy → Docker daemon

Hermes sandbox（Docker default bridge）
  └─ host.docker.internal → host docker0 :9090/9091 → Hermes iron-proxy
```

Hermes 主服務加入 `t3_proxy`、`ai_services` 與 `ai_control`；sandbox 在 enforced iron-proxy 模式下保持 Docker 預設 `bridge`，不加入這三個 Compose network。`ai_control` 只承載 Hermes 對 control plane 的 Docker API 流量；它不是讓 sandbox 直接接觸管理網路的捷徑。host docker0 上的 9090/9091 只提供 sandbox egress proxy，不得對 LAN/WAN 發布。

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
| AI service network | `ai_services`（Hermes 與 SearXNG service-to-service 流量） |
| Docker control network | `ai_control`（僅限 control plane 路由） |
| Sandbox network | Docker 預設 `bridge`（enforced iron-proxy 模式） |
| Host-only proxy port | docker0 上的 `9090/9091`，不得對 LAN/WAN 開放 |
| API/Dashboard host port | 無，僅透過 Traefik `websecure-internal` |

## Host-visible data path 契約

Hermes 的資料目錄必須以同一個 host-visible 路徑提供給需要讀寫它的控制平面與 sandbox。標準契約是：

```text
host data root:              ${DATADIR}/hermes
Hermes canonical data root: ${DATADIR}/hermes
Hermes compatibility mount: /opt/data
```

Compose 會把同一個 host 目錄同時掛到 `/opt/data` 與 container 內的 `${DATADIR}/hermes`，並將 `HERMES_HOME`、`HERMES_WRITE_SAFE_ROOT`、`TERMINAL_SANDBOX_DIR` 指向後者。如此 Hermes 傳給 host Docker daemon 的 sandbox、skills、cache 與 proxy bind source 都是 daemon 可解析的 host absolute path。若只讓 Hermes 使用 `/opt/data`，host daemon 會把它解讀為 host `/opt/data`，造成錯誤目錄或空 bind mount。

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

Hermes 主服務與 SearXNG 等 AI 服務之間使用 `ai_services`，可透過 `http://searxng:8080` 直接存取。`t3_proxy` 只承載 Traefik north-south 流量，不能當成 sandbox 隔離措施。

Hermes 使用 Docker client 的 `DOCKER_HOST` 指向專用 control plane：

```dotenv
DOCKER_HOST=tcp://hermes-socket-proxy:2375
```

目前 Hermes 的 `proxy.enforce_on_docker: true` 會拒絕 `docker_extra_args` 中的 `--network`/`--net`，避免 sandbox 以額外網路覆寫 egress 邊界。因此 sandbox 保持 Docker 預設 `bridge`，不直接加入 `ai_services`；SearXNG 的內部 Docker DNS endpoint 是供 Hermes 主服務使用。不要用 `hermes config set terminal.docker_extra_args '["--network=ai_services"]'`：該 CLI 目前會把 JSON 文字存成 YAML string，而不是 list，且 enforced proxy 即使收到正確 list 也會拒絕 network override。

若 `proxy.enabled: true`，必須先完成一次 `hermes egress setup --no-restart`。Hermes 在容器內無法偵測 host 的 `docker0`，上游預設會把 iron-proxy 綁到 container loopback，host Docker 建立的 sandbox 無法連線。本 Compose 的 `post_start` hook 會把既有 `proxy.yaml` listener 改成 container 的 `0.0.0.0:9090/9091`，再啟動 proxy；port publishing 則只綁定 host `${HERMES_EGRESS_BIND_IP:-172.17.0.1}`（docker0），不對 LAN/WAN 暴露。部署前必須以 `ip -4 -o addr show docker0` 驗證該位址。

iron-proxy v0.39 會在 HTTPS `CONNECT` 尚未帶有 tunneled `Authorization` header 時套用 `replace.require: true`，導致所有 HTTPS tunnel 先被 403 拒絕。Hook 因此會把 generated secret rules 的 `require` 改為 `false`；allowlist 與 proxy-token replacement 仍啟用，provider 真實 credential 仍不會注入 sandbox，但「缺少 proxy token 時對 allowlisted upstream 一律 fail-closed」的保證不再成立。升級 iron-proxy 後應重新測試並優先移除此相容性修正。

不要把 9090/9091 綁到 host `0.0.0.0`、LAN IP、Traefik 或其他共享入口。Credential replacement 仍要求 minted proxy token，所有 upstream 仍受 allowlist 限制；此外仍要限制 CPU、memory、filesystem、capability 與 bind source。

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
