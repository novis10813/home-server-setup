# Traefik 動態規則

Traefik 的 File Provider 讀取 `appdata/traefik/rules/` 下的 YAML，作為動態設定。規則會即時監聽（`watch=true`）。

---

## TLS 選項

- **檔案**：`appdata/traefik/rules/01-tls.yml`
- **用途**：定義 TLS 選項 `tls-opts`（例如 `minVersion: VersionTLS12`），供 entrypoints 使用（`tls.options=tls-opts@file`）。

---

## 中介軟體鏈（Middleware Chains）

Chains 在 `appdata/traefik/rules/` 內以獨立檔案定義，供 Traefik labels 以 `chain-xxx@file` 引用。

| Chain | 檔案 | 組成 | 用途 |
|-------|------|------|------|
| `chain-oauth@file` | chain-oauth.yml | rate-limit → secure-headers → oauth | OAuth 保護（如 Dashboard、Pi-hole） |
| `chain-basic-auth@file` | chain-basic-auth.yml | rate-limit → secure-headers → basic-auth | Basic Auth 保護 |
| `chain-no-auth@file` | chain-no-auth.yml | rate-limit → secure-headers | 僅安全與限流，不認證（如 OAuth 登入頁、部分內部服務） |

---

## 個別 Middlewares

以下在 `appdata/traefik/rules/middlewares-*.yml` 中定義，並被上述 chain 引用：

- **middlewares-rate-limit**：請求限流。
- **middlewares-secure-headers**：安全標頭（如 HSTS、X-Frame-Options 等）。
- **middlewares-oauth**：`forwardAuth` 至 `http://oauth:4181/portals/main`，信任 X-Forwarded-*，並轉發 `X-Forwarded-User`、`X-Forwarded-Displayname`、`X-Authenticated-User`。
- **middlewares-basic-auth**：Basic Auth，使用者檔來自 secret `basic_auth_credentials`，realm `Traefik Basic Auth`。

其餘如 `middlewares-buffering`、`middlewares-geoblock` 等若存在，可依需求加入 chain 或單獨掛在 router 上。

---

## Traefik 標籤慣例

- Router：`<servicename>-rtr`（必要時加 `-http` 等後綴）。
- Service：`<servicename>-svc`。
- 規則格式：`traefik.http.routers.<name>.rule=Host(\`host.${DOMAINNAME_1}\`)`。
- **TLS（建議）**：由 Traefik entrypoint 統一啟用（`websecure-*`），一般服務 **不需要** 在 router labels 重複設定 `tls=true` / `tls.certresolver`。
  - 只有在「該服務需要不同的 TLS options / cert resolver / 憑證」時，才在該 router 上另外指定。
- 需保護時：`middlewares=chain-oauth@file` 或 `chain-basic-auth@file` / `chain-no-auth@file`。

---

## 憑證（ACME）

- **Resolver**：`dns-cloudflare`。
- **儲存**：`/acme.json`（對應 `appdata/traefik/acme/acme.json`，需 `chmod 600`）。
- **Challenge**：DNS，Cloudflare API Token 來自 secret `cf_dns_api_token`。
- **涵蓋網域**：`${DOMAINNAME_1}` 與 `*.${DOMAINNAME_1}`（在 traefik.yml 的 entrypoint 設定中指定）。
