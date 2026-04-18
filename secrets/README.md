# Secrets

Place the following files here (do not commit their contents):

| File | Used by | Description |
|------|---------|-------------|
| `basic_auth_credentials` | Traefik | HTTP Basic Auth for dashboard (htpasswd format). Generate: `htpasswd -nb user password` |
| `cf_dns_api_token` | Traefik | Cloudflare API token for Let's Encrypt DNS challenge. Create a token with Zone:DNS:Edit. |
| `telegram_bot_token` | Alertmanager | Telegram Bot Token for sending alerts. Create via [@BotFather](https://t.me/BotFather). |
| `discord_webhook_url` | Alertmanager | Discord Webhook URL for sending alerts. Create in Discord channel settings → Integrations → Webhooks. |
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
