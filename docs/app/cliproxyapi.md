# CLIProxyAPI

[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) 將 Codex、Claude Code 與其他支援的 CLI 帳號包裝成相容 OpenAI、Gemini、Claude 與 Codex 的 API。服務只透過內網 Traefik HTTPS 入口提供，並同時要求 Traefik OAuth 與 CLIProxyAPI API key。

## 架構

```
API Client ─HTTPS + OAuth + Bearer key─▶ Traefik (`websecure-internal`)
                                         └▶ cli-proxy-api (port 8317)
                                              ├─ auths: ${DATADIR}/cli-proxy-api/auths
                                              └─ logs:  ${DATADIR}/cli-proxy-api/logs
```

| 容器 | Host | 網路 | 直接對外埠 |
|------|------|------|------------|
| `cli-proxy-api` | `cliproxy.${DOMAINNAME_1}`（API）<br>`cliproxyapi.${DOMAINNAME_1}`（管理頁） | `t3_proxy` | 無 |

## 初次部署

1. 依照專案根目錄的 `secrets/README.md` 建立 `secrets/cli-proxy-api-config.yaml`，將 `api-keys` 的範例值替換成隨機長字串。
2. 建立執行時資料目錄：

   ```bash
   mkdir -p "${DATADIR}/cli-proxy-api/auths" "${DATADIR}/cli-proxy-api/logs" "${DATADIR}/cli-proxy-api/plugins"
   ```

3. 啟動服務：

   ```bash
   docker compose -f docker-compose-app.yml up -d cli-proxy-api
   ```

4. 以 Codex device-code flow 新增帳號憑證：

   ```bash
   docker compose -f docker-compose-app.yml exec -it cli-proxy-api ./CLIProxyAPI -codex-device-login
   ```

   指令會顯示 device code 與登入網址；完成登入後，憑證會保存在 `${DATADIR}/cli-proxy-api/auths/`。其他 provider 的 OAuth 登入旗標請以 `./CLIProxyAPI -help` 查詢。

## 用戶端設定

API base URL 是 `https://cliproxy.${DOMAINNAME_1}/v1`。使用 `secrets/cli-proxy-api-config.yaml` 中 `api-keys` 的值作為 Bearer token，例如：

```bash
curl https://cliproxy.${DOMAINNAME_1}/v1/models \
  -H "Authorization: Bearer <cli-proxy-api-key>"
```

API client 不需通過 Traefik OAuth，只需使用 CLIProxyAPI Bearer token 驗證。API router 仍限於內網 HTTPS 入口，並保留 Traefik 限流與安全標頭；不要直接發布 `8317` 到主機。

## 管理頁

在瀏覽器開啟 `https://cliproxyapi.${DOMAINNAME_1}`。此網址會在 Traefik OAuth 驗證後重新導向 CLIProxyAPI 的內建管理頁。管理頁還需要 `remote-management.secret-key` 的管理金鑰；它與 API client 使用的 `api-keys` 是不同的憑證，並只儲存在 `secrets/cli-proxy-api-config.yaml`。

設定檔以 Docker Secret 唯讀掛載，因此管理頁無法寫回 YAML 設定；請在主機修改該 secret 後重新建立容器。

## 常用指令

```bash
# 查看狀態與日誌
docker compose -f docker-compose-app.yml ps cli-proxy-api
docker compose -f docker-compose-app.yml logs -f cli-proxy-api

# 更新映像
docker compose -f docker-compose-app.yml pull cli-proxy-api
docker compose -f docker-compose-app.yml up -d cli-proxy-api
```

## 備份

備份 `${DATADIR}/cli-proxy-api/auths/`（OAuth 憑證）與 `secrets/cli-proxy-api-config.yaml`（API key 與設定）。日誌與 plugins 可依保留需求選擇備份。
