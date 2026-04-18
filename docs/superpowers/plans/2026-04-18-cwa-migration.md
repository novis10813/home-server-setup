# CWA Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將 calibre GUI + calibre-web 替換為 calibre-web-automated，Kavita 保持不動。

**Architecture:** 新增 `compose/apps/calibre-web-automated.yml`，沿用現有 config 和 books 資料夾路徑；從 `docker-compose-app.yml` 移除 calibre 與 calibre-web 的 include。Traefik hostname 和 port 不變。

**Tech Stack:** Docker Compose, Traefik, crocodilestick/calibre-web-automated

---

## 檔案結構

| 動作 | 路徑 |
|------|------|
| 新增 | `compose/apps/calibre-web-automated.yml` |
| 修改 | `docker-compose-app.yml` |
| 不動 | `compose/apps/kavita.yml` |
| 停用（保留備用） | `compose/apps/calibre.yml` |
| 停用（保留備用） | `compose/apps/calibre-web.yml` |

---

### Task 1: 停止舊容器並準備環境

**Files:**
- 無檔案變更，僅操作容器與資料夾

- [ ] **Step 1: 停止 calibre 和 calibre-web 容器**

```bash
docker compose -f docker-compose-app.yml stop calibre calibre-web
```

預期輸出：
```
[+] Stopping 2/2
 ✔ Container calibre-web  Stopped
 ✔ Container calibre      Stopped
```

- [ ] **Step 2: 建立 cwa-ingest 資料夾**

（將 `$DATADIR` 替換為你的實際路徑，例如 `/mnt/data`）

```bash
mkdir -p $DATADIR/calibre/cwa-ingest
```

- [ ] **Step 3: 確認既有資料夾存在**

```bash
ls $DATADIR/calibre/
```

預期看到：`books/`、`calibre-web-config/`、`config/`、`cwa-ingest/`

- [ ] **Step 4: Commit（此時尚無檔案變更，可略過）**

---

### Task 2: 新增 calibre-web-automated compose 設定

**Files:**
- Create: `compose/apps/calibre-web-automated.yml`

- [ ] **Step 1: 建立 `compose/apps/calibre-web-automated.yml`**

內容如下：

```yaml
# Calibre-Web-Automated - eBook management with auto-import
# https://github.com/crocodilestick/Calibre-Web-Automated

services:
  ###########################################################################
  # Calibre-Web-Automated
  ###########################################################################
  calibre-web-automated:
    container_name: calibre-web-automated
    image: crocodilestick/calibre-web-automated:latest
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - t3_proxy
    volumes:
      - ${DATADIR}/calibre/calibre-web-config:/config
      - ${DATADIR}/calibre/books:/calibre-library
      - ${DATADIR}/calibre/cwa-ingest:/cwa-book-ingest
      - /etc/localtime:/etc/localtime:ro
    environment:
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - TZ=${TZ}
    labels:
      - "traefik.enable=true"
      ## HTTP Router
      - "traefik.http.routers.cwa-rtr-http.entrypoints=web-internal"
      - "traefik.http.routers.cwa-rtr-http.rule=Host(`calibre.${DOMAINNAME_1}`)"
      - "traefik.http.routers.cwa-rtr-http.middlewares=chain-no-auth@file"
      ## HTTPS Router
      - "traefik.http.routers.cwa-rtr.entrypoints=websecure-internal"
      - "traefik.http.routers.cwa-rtr.rule=Host(`calibre.${DOMAINNAME_1}`)"
      - "traefik.http.routers.cwa-rtr.middlewares=chain-no-auth@file"
      ## Service
      - "traefik.http.routers.cwa-rtr.service=cwa-svc"
      - "traefik.http.services.cwa-svc.loadbalancer.server.port=8083"
```

- [ ] **Step 2: Commit**

```bash
git add compose/apps/calibre-web-automated.yml
git commit -m "feat: add calibre-web-automated compose service"
```

---

### Task 3: 更新 docker-compose-app.yml

**Files:**
- Modify: `docker-compose-app.yml`

- [ ] **Step 1: 移除 calibre 和 calibre-web 的 include，加入 calibre-web-automated**

將 `docker-compose-app.yml` 的 include 區塊從：

```yaml
include:
  - compose/apps/calibre.yml
  - compose/apps/calibre-web.yml
  - compose/apps/home-assistant.yml
  - compose/apps/immich.yml
  - compose/apps/kavita.yml
  - compose/apps/minecraft.yml
```

改為：

```yaml
include:
  - compose/apps/calibre-web-automated.yml
  - compose/apps/home-assistant.yml
  - compose/apps/immich.yml
  - compose/apps/kavita.yml
  - compose/apps/minecraft.yml
```

- [ ] **Step 2: 驗證 compose 語法**

```bash
docker compose -f docker-compose-app.yml config --quiet
```

預期：無錯誤輸出（exit code 0）

- [ ] **Step 3: Commit**

```bash
git add docker-compose-app.yml
git commit -m "feat: replace calibre+calibre-web with calibre-web-automated"
```

---

### Task 4: 啟動並驗證

**Files:**
- 無變更

- [ ] **Step 1: 拉取 CWA image 並啟動**

```bash
docker compose -f docker-compose-app.yml up -d calibre-web-automated
```

預期輸出：
```
[+] Running 1/1
 ✔ Container calibre-web-automated  Started
```

- [ ] **Step 2: 確認容器正常運行**

```bash
docker ps --filter name=calibre-web-automated --format "table {{.Names}}\t{{.Status}}"
```

預期：`calibre-web-automated` 狀態為 `Up`

- [ ] **Step 3: 查看啟動日誌，確認無錯誤**

```bash
docker logs calibre-web-automated --tail 50
```

注意確認：
- 無 `permission denied` 錯誤（若有，檢查 PUID/PGID 是否符合 books 資料夾的擁有者）
- 有 `metadata.db` 被偵測到的訊息

- [ ] **Step 4: 開啟 Web UI 確認書庫載入**

瀏覽 `https://calibre.<DOMAINNAME_1>`，以舊帳號登入，確認書庫正常顯示。

- [ ] **Step 5: 確認 Kavita 仍正常（不受影響）**

瀏覽 `https://kavita.<DOMAINNAME_1>`，確認書庫仍可存取。

---

## 回退方式

若 CWA 啟動失敗或 UI 無法登入：

```bash
# 停止 CWA
docker compose -f docker-compose-app.yml stop calibre-web-automated

# 將 docker-compose-app.yml 的 include 還原為原始設定（git revert 或手動）
git revert HEAD~1

# 重啟舊服務
docker compose -f docker-compose-app.yml up -d calibre calibre-web
```

若 config 沿用導致 UI 問題，可嘗試：
```bash
# 備份後清空 config，讓 CWA 重新初始化
cp -r $DATADIR/calibre/calibre-web-config $DATADIR/calibre/calibre-web-config.bak
rm -rf $DATADIR/calibre/calibre-web-config/*
docker restart calibre-web-automated
```
