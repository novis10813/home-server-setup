# Infrastructure 概述

Infrastructure 對應 **`docker-compose-infrastructure.yml`**，負責**網關**與基礎服務，包含：

- **Traefik** — 反向代理、路由、TLS（Let's Encrypt DNS-Cloudflare）、服務發現（經 Socket Proxy）
- **Socket Proxy** — Docker API 安全代理，Traefik 透過 `tcp://socket-proxy:2375` 取得容器資訊
- **traefik-forward-auth** — OAuth 2.0 SSO，供 Traefik 的 forwardAuth 使用
- **Pi-hole** — DNS 與廣告攔截

---

## 本節文件

| 文件 | 說明 |
|------|------|
| [架構與目錄](architecture.md) | 技術棧、設計邏輯、目錄結構、網路與埠 |
| [設定與環境](configuration.md) | 環境變數、Secrets、啟動前準備 |
| [服務說明](services.md) | 各服務定義（Traefik、Socket Proxy、OAuth、Pi-hole） |
| [Traefik 規則](traefik-rules.md) | 動態規則、TLS、中介軟體鏈 |
| [操作與維護](operations.md) | 常用指令、維護、疑難排解 |

---

## 快速參考

- **啟動**：`docker compose -f docker-compose-infrastructure.yml up -d`
- **Dashboard**：`https://traefik.<DOMAINNAME_1>`（OAuth 保護）
- **設定檔**：`appdata/traefik/rules/`、`appdata/traefik/acme/`
