# Hugo

Hugo 靜態網站由 `docker-compose-app.yml` 管理，服務定義位於 `compose/apps/hugo.yml`。

## 架構

- Site config/layouts：`${DOCKERDIR}/appdata/hugo/site`
- Content：`${DATADIR}/hugo/content`
- Static assets：`${DATADIR}/hugo/static`
- Build output：`${DATADIR}/hugo/public`
- Builder：`hugo-builder` 使用 inotify 監看 Hugo source，變更時執行完整 clean build
- Runtime：`hugo` 使用 `nginxinc/nginx-unprivileged:stable-alpine` 只服務靜態檔
- Host：`https://${DOMAINNAME_1}`
- Middleware：`chain-no-auth@file`

Traefik 負責 TLS 與 root domain router；Hugo container 不直接對外開 port。`hugo-builder` 不掛 Traefik，只負責監看內容並輸出靜態檔。

## 發布文章與附件

文章與附件都放在 `${DATADIR}/hugo` 底下。以目前 `.env` 的 `DATADIR=/mnt/raid1` 來說，實際路徑如下：

| 類型 | 路徑 | 說明 |
|------|------|------|
| 文章 | `${DATADIR}/hugo/content` | Markdown 內容，例如首頁、文章、頁面 |
| 圖片與附件 | `${DATADIR}/hugo/static` | 會原樣輸出到網站根路徑 |
| 編譯輸出 | `${DATADIR}/hugo/public` | Hugo 產生的 HTML/CSS/JS，由 nginx 服務 |

新增文章請放在：

```text
${DATADIR}/hugo/content/posts/my-post.md
```

實際路徑範例：

```text
/mnt/raid1/hugo/content/posts/my-post.md
```

文章範例：

```markdown
---
title: "My Post"
date: 2026-06-21
draft: false
---

文章內容。
```

圖片與附件請放在：

```text
${DATADIR}/hugo/static/images/example.jpg
```

實際路徑範例：

```text
/mnt/raid1/hugo/static/images/example.jpg
```

文章內引用圖片：

```markdown
![example](/images/example.jpg)
```

若放一般附件，例如 PDF：

```text
/mnt/raid1/hugo/static/files/report.pdf
```

文章內連結：

```markdown
[下載報告](/files/report.pdf)
```

儲存、移動或刪除文章/附件後，`hugo-builder` 會自動重新編譯到 `${DATADIR}/hugo/public`，不需要重新 build nginx image。刪除文章時會先清空舊輸出，避免 stale HTML 留在 `public/`。

備份時應備份 `${DATADIR}/hugo/content` 與 `${DATADIR}/hugo/static`。`${DATADIR}/hugo/public` 是可重新產生的輸出，不需要當作主要資料備份。

## 維護操作

若修改 `${DOCKERDIR}/appdata/hugo/site` 內的設定或 layout，也會由 watcher 偵測並重新編譯。服務啟動指令：

```bash
docker compose -f docker-compose-app.yml up -d hugo-builder hugo
```

若有修改 `appdata/hugo/builder/` 內的 builder Dockerfile 或 script，需重新 build builder image：

```bash
docker compose -f docker-compose-app.yml up -d --build hugo-builder
```
