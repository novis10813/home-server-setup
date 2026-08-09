# Hermes Agent

[Hermes Agent](https://github.com/NousResearch/hermes-agent) 是 Nous Research 的可自架 AI agent，支援持久化記憶、工具呼叫、messaging gateway，以及 OpenAI-compatible API。

本 repo 將 Hermes 放在 **App stack**，使用官方 Docker image，並透過 Traefik 的 internal HTTPS 入口提供服務。

## 架構

```text
Traefik
  ├─ https://hermes-api.${DOMAINNAME_1}  → Hermes API :8642
  └─ https://hermes.${DOMAINNAME_1}      → Hermes Dashboard :9119

Hermes
  └─ /opt/data ← ${DATADIR}/hermes
```

| 項目 | 設定 |
|------|------|
| Compose service | `hermes` |
| Container | `hermes` |
| Image | `nousresearch/hermes-agent:${HERMES_VERSION:-latest}` |
| Command | `gateway run` |
| Runtime data | `${DATADIR}/hermes` |
| API | `8642`，需要 `API_SERVER_KEY` |
| Dashboard | `9119`，需要 Hermes 自身的認證設定 |
| Docker network | `t3_proxy` |
| 外部 host port | 無，僅透過 Traefik `websecure-internal` |

Compose 定義：`compose/apps/hermes.yml`。

## 首次初始化

先確認 Infrastructure stack 已建立 `t3_proxy`：

```bash
docker network inspect t3_proxy >/dev/null
```

建立 runtime data 目錄：

```bash
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

至少需要配置 API server key：

```dotenv
API_SERVER_KEY=<長隨機 API key>
```

Dashboard 綁定 `0.0.0.0` 時，也需要 Hermes 自身的 authentication provider。初次部署可使用 Basic Auth：

```dotenv
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=<長隨機密碼>
HERMES_DASHBOARD_BASIC_AUTH_SECRET=<穩定的長隨機 secret>
```

產生隨機值的範例：

```bash
openssl rand -hex 32
```

請確保 runtime secret 不會被提交到 Git：

```bash
chmod 600 "${DATADIR}/hermes/.env"
```

Traefik 入口的認證分層如下：

- API：`chain-no-auth@file`，由 Hermes `API_SERVER_KEY` 負責 API authentication。
- Dashboard：`chain-oauth@file`，另外保留 Hermes 自身的 authentication provider。

## 使用現有 CLIProxyAPI

本 repo 已有 CLIProxyAPI，容器內部 endpoint 為：

```text
http://cli-proxy-api:8317/v1
```

若要讓 Hermes 使用 CLIProxyAPI，先確認 CLIProxyAPI 已經有可用的 provider credential，再編輯：

```text
${DATADIR}/hermes/config.yaml
```

加入或合併以下設定：

```yaml
providers:
  cliproxy:
    api: http://cli-proxy-api:8317/v1
    key_env: CLIPROXY_API_KEY
    transport: chat_completions

model:
  provider: custom:cliproxy
  default: <CLIProxyAPI /v1/models 中的實際 model ID>
```

並在 Hermes runtime `.env` 放入 CLIProxyAPI 的 client API key：

```dotenv
CLIPROXY_API_KEY=<與 cli-proxy-api-config.yaml 的 api-keys 相同>
```

不要把實際 key 寫入 `config.yaml` 或 repository。`model.default` 必須使用 CLIProxyAPI 實際回傳的 model ID，不要自行猜測。

## 之後啟動 Hermes

本次安裝不會執行以下啟動命令。完成 setup 與設定後，再由管理者自行決定是否啟動：

```bash
docker compose -f docker-compose-app.yml up -d hermes
```

啟動後可查看：

```bash
docker compose -f docker-compose-app.yml ps hermes
docker compose -f docker-compose-app.yml logs -f hermes
```

入口為：

```text
https://hermes-api.${DOMAINNAME_1}
https://hermes.${DOMAINNAME_1}
```

API smoke test：

```bash
curl -fsS \
  -H "Authorization: Bearer <API_SERVER_KEY>" \
  "https://hermes-api.${DOMAINNAME_1}/v1/models"
```

## 更新

Docker 安裝不使用 `hermes update`。更新 image 後重新建立 service：

```bash
docker compose -f docker-compose-app.yml pull hermes
docker compose -f docker-compose-app.yml up -d hermes
```

如果需要可重現部署，請在 `.env` 設定經測試的 `HERMES_VERSION`，不要長期依賴 `latest`。

## 備份

至少備份：

```text
${DATADIR}/hermes/
```

其中可能包含：

- `config.yaml`
- `.env` 與 provider credentials
- sessions
- memories
- skills
- profiles
- gateway 設定
- logs

## Docker backend 注意事項

Hermes 支援將 terminal backend 設為 Docker，但這需要 Hermes 控制 Docker daemon。不要在初次部署時直接加入：

```yaml
- /var/run/docker.sock:/var/run/docker.sock
```

Docker socket 幾乎等同授予 agent 管理 host Docker 的權限。若日後需要讓 Hermes 修改本 repo 或執行 Docker Compose，應先設計隔離的 workspace、專用 socket proxy 與最小權限 policy。

目前 repo 的 `socket-proxy` 是給 Traefik 使用，並未開啟 Hermes 可能需要的所有 Docker API 操作，因此不能直接假設它可以作為 Hermes backend。

## 參考文件

- [Hermes Agent GitHub](https://github.com/NousResearch/hermes-agent)
- [Hermes Docker deployment](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/docker.md)
- [Hermes installation](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/getting-started/installation.md)
- [Hermes provider configuration](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/providers.md)
