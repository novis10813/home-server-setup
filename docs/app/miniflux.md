# Miniflux

Miniflux 是極簡的自架 RSS 閱讀器。本服務屬於 **App stack**，由 `docker-compose-app.yml` 管理，僅提供內網 HTTPS 入口。

## 架構

```
客戶端 (內網 / tailnet)
  → Traefik (websecure-internal :443)
      router: miniflux-rtr
      middlewares: chain-no-auth-relaxed@file
  → miniflux (t3_proxy + default)
  → miniflux-db (PostgreSQL 17, 僅 default 網路)
```

- **網址**：`https://rss.${DOMAINNAME_1}`
- **Compose**：`compose/apps/miniflux.yml`
- **認證**：Miniflux 內建登入（管理員帳號於首次啟動時建立）

## 資料與 Secrets

| 項目 | 位置 |
|------|------|
| PostgreSQL 資料 | `${DATADIR}/miniflux/postgres` |
| 資料庫密碼 | `secrets/miniflux_db_password` |
| `DATABASE_URL`（含密碼） | `secrets/miniflux_database_url` |
| 管理員密碼 | `secrets/miniflux_admin_password` |

- 管理員帳號預設 `admin`，可用 `.env` 的 `MINIFLUX_ADMIN_USER` 覆寫。
- `CREATE_ADMIN` 只在使用者不存在時建立，之後改密碼請在 Miniflux 介面操作。
- 映像版本可用 `MINIFLUX_VERSION` 固定。

## 備份

- 備份 `secrets/` 與 PostgreSQL 資料；目前尚未納入自動備份。
- 匯出：`docker exec miniflux-db pg_dump -U miniflux miniflux > miniflux.sql`
- 訂閱也可從介面匯出 OPML。

## 操作

```bash
docker compose -f docker-compose-app.yml up -d miniflux miniflux-db
docker logs miniflux
cat secrets/miniflux_admin_password   # 取得初始管理員密碼
```
