# 設定與環境

## 環境變數

複製 `.env.example` 為 `.env` 後依本機環境調整。勿將 `.env` 提交版控。

| 變數 | 說明 | 範例 |
|-----|------|------|
| `DOCKERDIR` | 專案根目錄絕對路徑 | `/opt/docker` |
| `DATADIR` | 容器運行時資料路徑（不版控） | `/mnt/raid1` |
| `TZ` | 時區 | `Asia/Taipei` |
| `LOCAL_IPS` | 信任的內網/本機 IP（CIDR，逗號分隔），用於 X-Forwarded-* | `127.0.0.1/32,10.0.0.0/8,192.168.0.0/16,172.16.0.0/12` |
| `CLOUDFLARE_IPS` | Cloudflare 代理 IP 範圍（選填，見 [Cloudflare IPs](https://www.cloudflare.com/ips/)） | 見 `.env.example` |
| `DOMAINNAME_1` | 主要網域；Dashboard 為 `traefik.<DOMAINNAME_1>` | `example.com` |
| `TRAEFIK_PORT` | Traefik API/Dashboard（insecure）主機埠（建議僅內網或以防火牆限制） | `8080` |
| `GOOGLE_OAUTH_CLIENT_ID` | Google OAuth Client ID（可放 .env） | `xxxx.apps.googleusercontent.com` |
| `HOST_IP` | 主機 IP（Pi-hole 等用途，建議與本機 IP 一致） | `192.168.x.x` |

Google OAuth Client Secret 由 `secrets/google_oauth_client_secret` 管理，不要寫入 `.env`。

---

## Secrets（敏感檔案）

以下檔案放在 `secrets/`，勿提交版控。啟動前需存在對應檔案（依實際使用的服務）。

| 檔案 | 使用處 | 說明 |
|------|--------|------|
| `basic_auth_credentials` | Traefik | HTTP Basic Auth（htpasswd）。產生：`htpasswd -nb user password > secrets/basic_auth_credentials` |
| `cf_dns_api_token` | Traefik | Cloudflare API Token，Let's Encrypt DNS Challenge 用。需 Zone:DNS:Edit 權限。 |
| `google_oauth_client_id` | （可選） | Google OAuth Client ID，若不以環境變數提供則放此檔。 |
| `google_oauth_client_secret` | traefik-forward-auth | Google OAuth Client Secret。 |
| `tfa_config` | traefik-forward-auth | traefik-forward-auth 設定 YAML（client_id、client_secret 路徑、domain 等）。 |
| `grafana_admin_password` | Grafana | Grafana 管理員密碼。密碼需符合 Grafana 密碼政策（長度、複雜度）。 |

詳見 `secrets/README.md`（若已補充 OAuth 說明可一併參考）。

---

## 啟動前準備

1. **環境變數**：複製 `.env.example` 為 `.env`，填寫 `DOCKERDIR`、`DOMAINNAME_1`、`TRAEFIK_PORT`、`LOCAL_IPS`，以及選填 `CLOUDFLARE_IPS`、OAuth、`HOST_IP` 等。
2. **Secrets**：在 `secrets/` 建立上述所需檔案（Basic Auth、Cloudflare Token、OAuth 用 `google_oauth_client_secret` 與 `tfa_config`）。
3. **ACME**：在 `appdata/traefik/acme/` 建立 `acme.json`：
   ```bash
   touch appdata/traefik/acme/acme.json && echo '{}' > appdata/traefik/acme/acme.json && chmod 600 appdata/traefik/acme/acme.json
   ```
   詳見 `appdata/traefik/acme/README.md`。

---

## 禁止提交的檔案

- `.env`
- `secrets/*`（除 `secrets/README.md`）
- `appdata/traefik/acme/acme.json`
- 任何含密碼、Token、私鑰的檔案
