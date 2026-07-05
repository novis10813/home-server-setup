# code-server

code-server 服務提供瀏覽器版 VS Code，用於從內網編輯本專案的 Docker Compose 設定。服務由 `docker-compose-app.yml` 管理，服務定義位於 `compose/apps/code-server.yml`。

## 存取

- **網址**：`https://code.${DOMAINNAME_1}`
- **Traefik entrypoint**：`websecure-internal`，僅限內網入口
- **認證**：Traefik OAuth，middleware 使用 `chain-oauth@file`
- **後端服務**：LinuxServer code-server，容器內 port `8443`

## 掛載

| 主機路徑 | 容器路徑 | 用途 |
|----------|----------|------|
| `${DATADIR}/code-server/config` | `/config` | code-server 設定與擴充套件資料 |
| `${DOCKERDIR}` | `/config/workspace/docker` | 本專案工作區 |

`DEFAULT_WORKSPACE` 已設定為 `/config/workspace/docker`，登入後會直接開啟此專案。

## 部署

先確認 code-server 設定目錄存在，且 `${PUID:-1000}:${PGID:-1000}` 有寫入權限：

```bash
mkdir -p ${DATADIR}/code-server/config
chown -R ${PUID:-1000}:${PGID:-1000} ${DATADIR}/code-server
```

啟動服務：

```bash
docker compose -f docker-compose-app.yml up -d code-server
```

查看狀態：

```bash
docker compose -f docker-compose-app.yml ps code-server
docker logs --tail 100 code-server
```

外網入口沒有設定 router，因此不會透過 `websecure-external` 對外提供。
