# WebDAV

WebDAV 服務用於 Zotero 論文附件同步，由 `docker-compose-app.yml` 管理，服務定義位於 `compose/apps/webdav.yml`。

## 存取

- **網址**：`https://webdav.${DOMAINNAME_1}`
- **Traefik entrypoint**：`websecure-internal`，僅限內網入口
- **認證**：Traefik Basic Auth，middleware 使用 `chain-basic-auth@file`
- **後端服務**：`rclone serve webdav`
- **資料目錄**：`${DATADIR}/webdav/zotero`（Zotero 使用的 WebDAV collection，對應 URL path `/zotero/`）

## Basic Auth

WebDAV 的帳號密碼由 Traefik 的 Basic Auth middleware 驗證，使用既有 secret：

```text
${DOCKERDIR}/secrets/basic_auth_credentials
```

建立或更新帳密：

```bash
htpasswd -nb <username> <password> > /opt/docker/secrets/basic_auth_credentials
```

更新 secret 後重啟 Traefik 讓 middleware 重新讀取檔案：

```bash
docker compose -f docker-compose-infrastructure.yml restart traefik
```

## 部署

先確認 WebDAV root 與 Zotero collection 目錄存在，且 `${PUID:-1000}:${PGID:-1000}` 有寫入權限：

```bash
mkdir -p ${DATADIR}/webdav/zotero
chown -R ${PUID:-1000}:${PGID:-1000} ${DATADIR}/webdav
```

啟動服務：

```bash
docker compose -f docker-compose-app.yml up -d webdav
```

查看狀態：

```bash
docker compose -f docker-compose-app.yml ps webdav
docker logs --tail 100 webdav
```

## Zotero 設定

在 Zotero 的 Sync 設定中選擇 WebDAV：

| 欄位 | 值 |
|------|----|
| URL | `https://webdav.${DOMAINNAME_1}/` |
| Username | `basic_auth_credentials` 中的使用者 |
| Password | `basic_auth_credentials` 中的密碼 |

Zotero 會自動在 URL 後面使用 `/zotero/` collection。Compose 因此將 `${DATADIR}/webdav` 掛到容器 `/data`，讓 `https://webdav.${DOMAINNAME_1}/zotero/` 對應到主機上的 `${DATADIR}/webdav/zotero/`。

設定完成後可使用 Zotero 的 WebDAV 驗證功能測試連線。

## 驗證

從內網測試 Basic Auth 與 WebDAV：

```bash
curl -k -u '<username>:<password>' -X PROPFIND https://webdav.${DOMAINNAME_1}/
```

外網入口沒有設定 router，因此不會透過 `websecure-external` 對外提供。
