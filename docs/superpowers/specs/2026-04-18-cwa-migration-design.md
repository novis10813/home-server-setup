# 設計文件：遷移至 Calibre-Web-Automated + Kavita

**日期：** 2026-04-18

## 目標

將電子書管理堆疊從 `calibre (GUI) + calibre-web` 替換為 `calibre-web-automated (CWA)`，保留 Kavita 不動。

## 現況

| 服務 | 用途 | 狀態 |
|------|------|------|
| `calibre` (LinuxServer GUI) | 手動書庫管理 | 移除 |
| `calibre-web` (LinuxServer) | Web 閱讀介面 | 移除 |
| `kavita` | 漫畫/EPUB/PDF 閱讀 | 保留不動 |

## 目標架構

| 服務 | 用途 | 狀態 |
|------|------|------|
| `calibre-web-automated` | 書庫管理 + Web 閱讀介面 + 自動匯入 | 新增 |
| `kavita` | 漫畫/EPUB/PDF 閱讀 | 保留不動 |

## Volume 對應

| CWA 容器路徑 | Host 路徑 | 說明 |
|--------------|-----------|------|
| `/config` | `${DATADIR}/calibre/calibre-web-config` | 沿用舊 calibre-web config（保留用戶/設定） |
| `/calibre-library` | `${DATADIR}/calibre/books` | 現有 Calibre 書庫 |
| `/cwa-book-ingest` | `${DATADIR}/calibre/cwa-ingest` | 新建自動匯入暫存區（放入即自動加進書庫並刪除） |

Kavita 的 `/books` 掛載路徑（`${DATADIR}/calibre/books`）不變。

## Traefik 路由

- 沿用 `calibre.${DOMAINNAME_1}` hostname
- Port 8083 不變
- Middleware 沿用 `chain-no-auth@file`

## 檔案變更清單

1. **新增** `compose/apps/calibre-web-automated.yml`
2. **修改** `docker-compose-app.yml` — 移除 calibre、calibre-web 的 include，加入 calibre-web-automated
3. **保留** `compose/apps/kavita.yml`（不動）
4. **移除** `compose/apps/calibre.yml`（可選：保留檔案但不 include）
5. **移除** `compose/apps/calibre-web.yml`（可選：保留檔案但不 include）

## 遷移步驟

1. 停止 calibre 和 calibre-web 容器
2. 建立 `${DATADIR}/calibre/cwa-ingest` 資料夾
3. 部署新的 calibre-web-automated compose 設定
4. 啟動 CWA，確認 Web UI 可登入（沿用舊帳號）
5. 確認書庫正確載入

## 風險與回退

- CWA 的 `/config` 沿用舊設定，若 UI 無法載入，嘗試清空 config 後重新設定
- 原始 calibre-web 和 calibre 的 compose 檔案保留備用，隨時可重啟

## 不在範圍內

- Kavita 任何設定變更
- Traefik 規則重構
- 書庫資料遷移（路徑不變，不需要移動任何檔案）
