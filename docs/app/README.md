# App

本專案的 **App** 類服務使用 `docker-compose-app.yml` 管理（與 Infrastructure 分離），並透過外部網路 `t3_proxy` 交由 Traefik 反向代理。

## Compose 主檔

- **檔案**：`docker-compose-app.yml`
- **include**：`compose/apps/*.yml`

## 服務清單

| 服務 | Host | 內網（Internal） | 外網（External） | 認證 |
|------|------|------------------|------------------|------|
| Calibre-Web-Automated | `calibre.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | CWA 內建登入 + `chain-no-auth@file` |
| Home Assistant | `ha.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | HA 內建登入 + `chain-no-auth@file` |
| Immich | `immich.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | `chain-immich@file`（使用 Immich 內建認證，僅套用安全標頭/限流） |
| Kavita | `kavita.${DOMAINNAME_1}` | ✅ `websecure-internal` | ❌ | Kavita 內建登入 + `chain-no-auth-relaxed@file` |

### TLS 使用方式

- TLS 由 Traefik 的 `websecure-*` entrypoints 統一提供（憑證與 TLS options 皆在 Traefik 設定）。
- App 服務的 router labels 一般不需要重複設定 `tls=true` / `tls.certresolver`，除非該服務需要不同的 TLS 行為。
