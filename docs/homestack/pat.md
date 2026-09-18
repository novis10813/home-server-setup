# Pi Agent Task Manager (PAT)

`pat` 是 Pi coding agent 的自架控制台：Task 是一級物件，各機器上的 Worker
（systemd user service，非容器）管理 git worktree 與 tmux 內的 agent，
`pat` 容器是唯一的 Coordinator（FastAPI + PostgreSQL + 內建 React Dashboard）。

- Source repo: `/mnt/raid1/novis/home-stack/pi-agent-task-manager`（已同步至
  `github.com/novis10813/agent-manager`）
- Compose: `compose/homestack/pat.yml`（經 `docker-compose-homestack.yml` include）

## 架構

| 組件 | 位置 | 說明 |
|------|------|------|
| `pat`（Coordinator） | 本機容器，單 uvicorn process | Dashboard + REST/WS API；建立 Task 時執行 `git ls-remote` 需 Git read access |
| `pat-postgres` | 本機容器（postgres:16-alpine） | PAT 專用 database，與 immich 等服務完全隔離 |
| Worker | 每台跑 agent 的機器（含本機） | `pat-worker` systemd user service，经 Tailscale 以 WS 連回 Coordinator |
| 使用者 | Browser | 直接開 `http://<tailscale-ip>:8010` 輸入 shared token |

**服務邊界是 Tailscale**：Coordinator 只 bind `PAT_TAILSCALE_IP:8010`，
不接 Traefik（Dashboard 的 WS/SSE 需長連線，且認證走 shared token）。
單一 uvicorn process 是必要條件，勿啟用多 replica 或 `--workers`。

## 網路

| 網路 | 用途 |
|------|------|
| `homestack`（internal bridge） | `pat` → `pat-postgres:5432` |
| Tailscale | Worker 與 browser → `pat:8010` |

`pat-postgres` 不 publish 任何 host port，只有 `pat` 容器可到達。

## 資料掛載

| 路徑 | 內容 | 備份 |
|------|------|------|
| `${DATADIR}/pat/postgres/` | PostgreSQL 16 data directory | `pg_dumpall -U pat`（或 docker exec 等效） |
| `${DATADIR}/pat/` | Coordinator runtime（log，單檔輪替 20 MiB） | 不必備份；task 記錄與 event 在 DB |
| `${DOCKERDIR}/secrets/pat.env` | `POSTGRES_PASSWORD`、`DATABASE_URL`、`PAT_TOKEN`、`PAT_IDLE_TIMEOUT` | 與其他 secrets 一起備份，勿提交 |
| `${DOCKERDIR}/appdata/pat/`（未使用） | 未來私有 SSH repo 的 ssh_config / known_hosts | — |

`/mnt/raid1/pat` 需 uid 1000 可寫（容器內 `pat` user 為 uid 1000）。

## 認證與權限

- 所有 `/api/*` 與 Worker WS 皆需 `X-PAT-Token`（shared token，存於
  `secrets/pat.env`；Worker 端存於各機 `~/.config/pat/worker.toml`，chmod 600）。
- `PAT_IDLE_TIMEOUT`（預設 120 秒）：無 terminal 輸出多久後標記 needs_attention。
- 容器均 `no-new-privileges:true`、`restart: unless-stopped`；
  資源限制各 1g memory / 1.0 CPU。

### 私有 Git repo（Coordinator 端，選配）

Coordinator 建立 Task 需要 `git ls-remote`。public repo 不需要額外設定；
私有 SSH repo 在 compose override 加 read-only mounts（`appdata/pat/ssh_config`、
`known_hosts`、`secrets/pat_git_key`，key 設 uid 1000 可讀）或
`GIT_SSH_COMMAND`，參照 repo README。Worker 使用 host 自己的 Git 憑證。

## 操作命令

```bash
cd /opt/docker

# 首次部署 / 更新（build 自 repo，勿在 repo 目錄內 compose up）
docker compose -f docker-compose-homestack.yml up -d --build pat pat-postgres

# 狀態
docker compose -f docker-compose-homestack.yml ps pat pat-postgres
docker compose -f docker-compose-homestack.yml logs -f pat

# DB 維護（備份 / 還原）
docker exec pat-postgres pg_dumpall -U pat > pat_pg_backup_$(date +%F).sql
docker exec -i pat-postgres psql -U pat < pat_pg_backup_*.sql

# 變更 token（Worker 端 worker.toml 需同步更新並重啟 service）
# 編輯 secrets/pat.env 的 PAT_TOKEN 後：
docker compose -f docker-compose-homestack.yml up -d pat
```

v1 啟動時 `create_all`，沒有 migration；DB 內只放本服務的 tables。

## Worker 安裝（各機器，非容器）

依 repo README 的「每台 Worker 的 systemd user service」章節：
`uv tool install` repo → `~/.config/pat/worker.toml`（URL =
`http://<tailscale-ip>:8010`、相同 token、絕對 `root_dir`）→
`pat-worker.service` → `systemctl --user enable --now pat-worker`；
登出後要繼續跑就 `loginctl enable-linger <user>`。
Pi 不會被 Worker 自動安裝，各機需先裝好 pi 並登入 provider。

## 權限與安全注意

- `secrets/pat.env` 含 DB 密碼與 shared token，chmod 600，勿提交版控。
- 不要把其他應用的 tables 混進 `pat` database。
- Worker 端 `state/`（含 task registry）勿在任務運行中刪除。
