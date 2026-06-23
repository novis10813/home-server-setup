# HugObsidian

HugObsidian 是 Obsidian QuickAdd 到 Hugo PaperMod 的接收服務，由 `docker-compose-app.yml` 管理，服務定義位於 `compose/apps/hugobsidian.yml`。

此服務屬於獨立 App 類服務，不接 HomeMQ/NATS。Obsidian 透過 REST API 上傳文章 JSON，服務將內容寫成 Hugo page bundle。

## 架構

- Source repo：`/mnt/raid1/novis/home-stack/hugobsidian`
- Compose：`${DOCKERDIR}/compose/apps/hugobsidian.yml`
- Image：`local/hugobsidian:latest`
- Host：`https://hugobsidian.${DOMAINNAME_1}`
- Traefik entrypoint：`websecure-internal`
- Middleware：`chain-no-auth@file`
- App auth：`X-API-Key`
- Hugo content mount：`${DATADIR}/hugo/content:/hugo/content`
- Service data mount：`${DATADIR}/hugobsidian:/data`

實際路徑範例（目前 `DATADIR=/mnt/raid1`）：

| 類型 | 路徑 | 說明 |
|------|------|------|
| Hugo 文章 | `/mnt/raid1/hugo/content/posts/<postId>/index.md` | Hugo page bundle 入口 |
| 附件 | `/mnt/raid1/hugo/content/posts/<postId>/<filename>` | 與文章放在同一個 bundle |
| Index | `/mnt/raid1/hugobsidian/index.json` | HugObsidian 服務索引 |
| Archive | `/mnt/raid1/hugobsidian/archive/<postId>-<timestamp>/` | DELETE 時歸檔的 bundle |

`hugo-builder` 會監看 `${DATADIR}/hugo/content`，HugObsidian 寫入或刪除文章後會觸發 Hugo 重新編譯。

## Secret

API key 放在：

```text
${DOCKERDIR}/secrets/hugobsidian.env
```

格式：

```dotenv
HUGOBSIDIAN_API_KEY=<secret>
```

此檔案不提交版控。Obsidian QuickAdd 需要把同一個值放到 `X-API-Key` header。

## API

| Method | Path | 認證 | 說明 |
|--------|------|------|------|
| `GET` | `/health` | 不需要 | 健康檢查 |
| `POST` | `/api/posts` | `X-API-Key` | 建立或更新文章 |
| `GET` | `/api/posts` | `X-API-Key` | 列出 index metadata |
| `GET` | `/api/posts/{postId}` | `X-API-Key` | 讀取文章 metadata 與 markdown |
| `POST` | `/api/posts/{postId}/publish` | `X-API-Key` | 設定 `draft: false` |
| `POST` | `/api/posts/{postId}/unpublish` | `X-API-Key` | 設定 `draft: true` |
| `DELETE` | `/api/posts/{postId}` | `X-API-Key` | 將 bundle 移到 archive |

建立與更新規則：

- 全新文章：request body 不帶 `postId`，服務產生 UUID。
- 更新文章：request body 帶既有 `postId`。
- request body 帶未知 `postId`：回 `404 post_not_found`，避免誤建錯誤 ID。

## QuickAdd 設定

Endpoint：

```text
https://hugobsidian.${DOMAINNAME_1}/api/posts
```

必要 headers：

```text
Content-Type: application/json
X-API-Key: <HUGOBSIDIAN_API_KEY>
```

若使用 Obsidian `requestUrl`，不要使用 `fetch(..., { mode: "no-cors" })`。`no-cors` 可能讓 Electron 不送出自訂 header，服務會回：

```json
{"detail":{"code":"missing_api_key","message":"Missing X-API-Key header"}}
```

狀態碼判斷：

| 狀態 | 意義 |
|------|------|
| `401 missing_api_key` | 沒收到 `X-API-Key` header |
| `403 invalid_api_key` | 有 header，但 key 錯 |
| `404 post_not_found` | 帶了不存在的 `postId` |
| `200` | 建立、更新或管理操作成功 |

## Payload

HugObsidian 接收第一層 JSON body，不需要 wrapper。

範例：

```json
{
  "title": "測試用 Blog",
  "description": "",
  "date": "2026-06-23T20:48:16+08:00",
  "tags": ["topic/example"],
  "categories": "Life",
  "author": "novis",
  "draft": true,
  "showToc": true,
  "TocOpen": false,
  "comments": true,
  "content": "測試一下 UwU",
  "attachments": []
}
```

Frontmatter 行為：

- `tags` / `categories` 可為字串或陣列，輸出時一律正規化成陣列。
- `draft` 控制 Hugo 發布狀態。
- `description`、`author` 與 PaperMod boolean 欄位會寫入 frontmatter。
- `filename`、`filepath`、`timestamp`、`createdAt`、`modifiedAt`、`content`、`attachments` 不會寫入 frontmatter。

附件行為：

- 支援 `image/png`、`image/jpeg`、`image/gif`、`image/webp`。
- 附件以 base64 放在 `attachments`。
- 拒絕路徑穿越與不安全檔名。
- Obsidian wiki image embed 會轉成 Hugo 可用的 Markdown image link。

## 部署與維護

啟動或更新服務：

```bash
cd /opt/docker
docker compose -f docker-compose-app.yml up -d --build hugobsidian
```

查看狀態：

```bash
docker compose -f docker-compose-app.yml ps hugobsidian
docker logs --tail 100 hugobsidian
```

健康檢查：

```bash
curl -k https://hugobsidian.${DOMAINNAME_1}/health
```

API smoke test：

```bash
api_key=$(sed -n 's/^HUGOBSIDIAN_API_KEY=//p' /opt/docker/secrets/hugobsidian.env)

curl -k -X POST "https://hugobsidian.${DOMAINNAME_1}/api/posts" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${api_key}" \
  --data '{"title":"Smoke Test","draft":true,"content":"hello"}'
```
