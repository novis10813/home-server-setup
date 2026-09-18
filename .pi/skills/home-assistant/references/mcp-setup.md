# MCP：pi-mcp-adapter + HA mcp_server（本 instance 已裝好）

## 現狀（project-local，不碰 global）

| 項目 | 位置 / 狀態 |
|------|------------|
| adapter 套件 | `pi install -l npm:pi-mcp-adapter` → `/opt/docker/.pi/settings.json` + `/opt/docker/.pi/npm/`（gitignored） |
| server 設定 | `/opt/docker/.pi/mcp.json`（gitignored）：`home-assistant` → `http://<t3_proxy_IP>:8123/api/mcp`，header `Authorization: Bearer <long-lived token>` |
| HA 端整合 | `mcp_server`（Model Context Protocol **Server**），暴露 **Assist API**，19 個 tools |
| token 位置 | 就在 `.pi/mcp.json` 的 Authorization header（與 REST/WS 用同一支 long-lived token） |

## 怎麼用（pi session 內）

```
mcp({})                          # 狀態：0/1 servers → 連不上；1/1 → OK
mcp({ connect: "home-assistant" })
mcp({ search: "turn off" })      # 找 tool
mcp({ describe: "<tool>" })      # 看參數
mcp({ tool: "home-assistant_HassTurnOff", args: { name: "廁所門前插座" } })
mcpScript(...)                   # 多次 MCP 呼叫的 JS 批次
```

## 端點與整合方向（別搞反）

- HA 的 MCP 端點是 **`/api/mcp`**（Streamable HTTP，stateless）——**不是** `/api/mcp_server/...`
- HA 有**兩個**長得像的整合：
  - **Model Context Protocol Server**（`mcp_server`）→ HA 當 server 暴露給外部 client ← **要裝這個**
  - **Model Context Protocol**（`mcp`）→ HA 當 client 去連外面的 MCP server（方向反了）

## 能做什么 / 不能做什么

**能**（Assist API tools）：開關設備（`HassTurnOn`/`HassTurnOff`，用 friendly name 或 area 找）、
媒體播放控制、廣播、todo 清單、`GetLiveContext`（即時家庭狀態）、`GetDateTime`。
注意：MCP 只能動 **exposed** 給 voice assistant 的 entities（HA UI: voice assistants → expose）。

**不能**：automations CRUD、script 管理、config 改動——這些走 REST/WS API
（本 skill 的 `scripts/ha_ws.mjs` + `references/api-quirks.md`），或 `mcp` 控不到的部分用 bash curl。

## 排障

| 症狀 | 原因 / 解法 |
|------|-----------|
| `0/1 servers`、`not listening; disconnected` | pi 沒重啟（裝完 adapter 要重啟 pi）；或 IP 變了（見 infrastructure.md） |
| `connect` 回 `404` | HA 端 `mcp_server` 整合沒裝（HA UI 加整合）；或 URL 錯（必須是 `/api/mcp`） |
| `401` | token 錯/失效 → 換 `.pi/mcp.json` 的 Authorization |
| tools 少 / 動不到某設備 | 該 entity 沒 expose 給 Assist API |

## 重装/遷移 checklist（換機器或 IP 變了）

1. 新位置 `pi install -l npm:pi-mcp-adapter`
2. 取新 t3_proxy IP（`docker inspect`）
3. 寫 `.pi/mcp.json`（url + Authorization），gitignore 它
4. HA 端確認 `mcp_server` 整合存在（WS `automation/config` 之類的管理走 API；整合增刪在 HA UI）
5. 重啟 pi → `mcp({})` 應顯示 `1/1 servers`
