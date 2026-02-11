# Home Server Docker 設定文件

本目錄整理目前專案的設定內容，供查閱與維護參考。內容基於根目錄的 `README.md`、`AGENTS.md` 以及實際 Compose、Traefik 規則等設定撰寫。

---

## 文件索引

依 **Compose 職責** 分層，左側導航為：Infrastructure、App、…；點入可看該類的詳細設定。

| 區塊 | 說明 |
|------|------|
| [Infrastructure](infrastructure/README.md) | 網關（Traefik、Socket Proxy、OAuth、Pi-hole）+ 監控（Prometheus、Grafana）— 架構、設定、服務、Traefik 規則、操作與維護 |
| [App](app/README.md) | 應用類服務（以 `docker-compose-app.yml` 管理，例如 Immich） |
| [Media](media/README.md) | 媒體服務（Jellyfin + Sonarr/Radarr/Prowlarr/qBittorrent） |

---

## 快速參考

- **主 Compose（不含監控）**：`docker compose -f docker-compose-infrastructure.yml up -d`
- **主 Compose（含監控）**：`docker compose -f docker-compose-infrastructure.yml --profile monitor up -d`
- **Dashboard（僅內網）**：`https://traefik.<DOMAINNAME_1>`（OAuth 保護）
- **Prometheus**：`https://prometheus.<DOMAINNAME_1>`（僅內網）
- **Grafana**：`https://grafana.<DOMAINNAME_1>`（OAuth 保護）
- **App Compose**：`docker compose -f docker-compose-app.yml up -d`
- **Immich**：`https://immich.<DOMAINNAME_1>`（僅內網）
- **Media Compose**：`docker compose -f docker-compose-media.yml up -d`
- **Jellyfin**：`https://jellyfin.<DOMAINNAME_1>`（僅內網）
- **設定檔**：`appdata/traefik/rules/`、`appdata/traefik/acme/`、`appdata/prometheus/`
- **敏感檔**：`secrets/`、`.env`（勿提交版控）

參考資源：[SimpleHomelab/Docker-Traefik](https://github.com/SimpleHomelab/Docker-Traefik)、[Traefik v3 文件](https://doc.traefik.io/traefik/)。

---

## 文件網頁（MkDocs）

本目錄可用 [MkDocs](https://www.mkdocs.org/) 建置成靜態網頁：

```bash
# 安裝依賴（建議使用虛擬環境）
pip install -r requirements-docs.txt

# 本地預覽（預設 http://127.0.0.1:8000）
mkdocs serve

# 建置輸出到 site/
mkdocs build
```

建置後的 `site/` 可部署至任何靜態主機或由 Traefik 提供服務。
