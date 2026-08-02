# Secrets

Place the following files here (do not commit their contents):

| File | Used by | Description |
|------|---------|-------------|
| `basic_auth_credentials` | Traefik | HTTP Basic Auth for dashboard (htpasswd format). Generate: `htpasswd -nb user password` |
| `cf_dns_api_token` | Traefik | Cloudflare API token for Let's Encrypt DNS challenge. Create a token with Zone:DNS:Edit. |
| `telegram_bot_token` | Alertmanager | Telegram Bot Token for sending alerts. Create via [@BotFather](https://t.me/BotFather). |
| `discord_webhook_url` | Alertmanager | Discord Webhook URL for sending alerts. Create in Discord channel settings → Integrations → Webhooks. |
| `cli-proxy-api-config.yaml` | CLIProxyAPI | API proxy configuration, including client API keys. See below. |
Ensure `basic_auth_credentials` and `cf_dns_api_token` exist before starting the **Infrastructure** stack.

### Alertmanager (Telegram / Discord)

**Telegram Bot Token:**
1. 開啟 Telegram，搜尋 [@BotFather](https://t.me/BotFather)
2. 發送 `/newbot`，依指示建立 Bot
3. 複製 Bot Token 到 `secrets/telegram_bot_token`
4. 在 `.env` 設定 `TELEGRAM_CHAT_ID`（使用 [@userinfobot](https://t.me/userinfobot) 獲取）

**Discord Webhook URL:**
1. 進入 Discord 頻道設定 → 整合 → Webhooks
2. 建立新 Webhook，複製 URL
3. 貼到 `secrets/discord_webhook_url`

### NATS (Home stack)

NATS 不使用認證（依賴 `t3_proxy` Docker 網路隔離）。啟動前確認 `appdata/nats/nats-server.conf` 存在即可。

### CLIProxyAPI

建立 `secrets/cli-proxy-api-config.yaml`，並將範例值替換為高強度、隨機的 API key。此 key 是呼叫 API 時的 Bearer token，請勿使用上游範例中的 `your-api-key-*` 值。

```yaml
host: ""
port: 8317

remote-management:
  allow-remote: false
  secret-key: ""
  disable-control-panel: true

auth-dir: "/root/.cli-proxy-api"
api-keys:
  - "replace-with-a-long-random-api-key"

logging-to-file: true
logs-max-total-size-mb: 512
```

保留 `remote-management.secret-key` 為空可停用管理 API；設定檔以 Docker Secret 唯讀掛載，因此不可透過管理 UI 修改。帳號 OAuth 憑證會寫入 `${DATADIR}/cli-proxy-api/auths/`，不在這個 secret 中。
