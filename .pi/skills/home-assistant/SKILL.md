---
name: home-assistant
description: >
  Operate and debug the Home Assistant on this home server (Docker container
  `home-assistant`, HA 2026.x): query states, control devices (lights, outlets,
  cast TV), create/modify automations and YAML config, reload/restart, YouTube
  live detection, and MCP access. Use this skill whenever the user mentions
  Home Assistant / HA / 智慧家居 / 自動化 (automations) / 燈 / 插座 / 電視 / TV /
  Tapo / 財經直播 / 播 YouTube, or asks to control, inspect, or debug anything
  running in the house — even if they don't say "Home Assistant" explicitly.
---

# Home Assistant（本 server）

HA 2026.x 跑在 Docker 容器 `home-assistant`（image `ghcr.io/home-assistant/home-assistant`），
compose 檔：`/opt/docker/compose/apps/home-assistant.yml`。

## 存取

| 用途 | 方法 |
|------|------|
| HA URL | `http://<t3_proxy_IP>:8123`。**IP 是動的**——每次先 `docker inspect home-assistant --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}}{{"\n"}}{{end}}'` 取 `t3_proxy` 那行的 IP，不要用記憶中的舊值 |
| 認證 | Long-lived access token，存於 `/opt/docker/.pi/mcp.json`（gitignored）的 `Authorization` header。所有 `/api/*` 呼叫都帶 `Authorization: Bearer <token>` |
| 查 states | `GET /api/states`（或 `/<entity_id>`） |
| 叫 service | **WS** `call_service`（格式見 `references/api-quirks.md`），REST `/api/services/...` 在 2026.x 會 400 |
| 讀 automation config | WS `{"type":"automation/config","entity_id":"automation.xxx"}` |
| 控設備（便捷） | `mcp` tool（pi-mcp-adapter → HA `/api/mcp`，server 名 `home-assistant`）：搜 `mcp({search:"..."})`、叫 `mcp({tool:"...",args:{}})` |
| WS client 腳本 | `node scripts/ha_ws.mjs <ha_url> <token> '<json 命令陣列>'`（auth 格式已處理好） |

**macvlan IP（192.168.0.250）host 連不到**（kernel 限制）——絕對不要用它。

## 寫 config（HA 設定檔）

設定目錄 `/mnt/raid1/homeassistant`（root-owned，本機 user 寫不了）：

1. 寫暫存檔 → `docker cp <file> home-assistant:/config/<name>`（容器內 root 可寫 bind mount）
2. 按 reload 矩陣套用（見下）
3. **驗證 = 看啟動 log 的 `Invalid config`**（`docker exec home-assistant sh -c "grep -a 'Invalid config' /config/home-assistant.log | tail"`）。`check_config` service 不寫 log，「沒輸出」≠ 通過

### Reload 矩陣（重要）

| 改動 | 套用方式 |
|------|----------|
| `automations.yaml` / `scripts.yaml` / `scenes.yaml` | WS `call_service` domain=`automation`（或 `script`/`scene`）service=`reload` |
| 已載入的 YAML 整合（如 `rest:`） | WS `call_service` domain=`rest` service=`reload`（domain 要先載入過才存在） |
| **新增** YAML 整合 | **只能 `docker restart home-assistant`**——`homeassistant.reload_core_config` 在 2026.x 只重處理 `homeassistant:` 核心設定，不載入整合 |

重啟後輪詢 **UI `/`**（不需認證，回 200 即好），**不要**輪詢 `/api/`——未認證打 `/api/` 會觸發 `http.ban` 警告（10 分鐘 100 次 invalid auth 會 IP ban）。重啟約 15–30 秒。

## 2026.x API 改動（踩過的地雷）

**動 WS、寫 YAML、寫 template 之前先讀 `references/api-quirks.md`**——WS auth 格式、
call_service 欄位、automation.trigger、choose default、regex filter 改名等。
遇到 `unknown_command` / `invalid_format` 時：grep 容器安裝碼
`docker exec home-assistant sh -c "grep -rn '<關鍵字>' /usr/src/homeassistant/homeassistant/ | head"`
比查外部文件快且對得上版本。

## 本 instance 關鍵 entities

| entity | 說明 |
|--------|------|
| `switch.ce_suo_men_qian_cha_zuo` | 廁所門前插座（Tapo 插頭，供燈用） |
| `media_player.ke_ting_dian_shi_2` | 客廳電視（cast；播 YouTube 用 `vnd.youtube://`，見 `references/youtube-cast.md`） |
| `sensor.yutinghao_live_video` | 財經皓角（@yutinghaofinance）直播 video ID 偵測（非直播 = unknown） |
| `sensor.sapporo_247_live_video` | 札幌 24/7 直播 video ID 偵測 |
| `automation.zao_shang_kan_zha_huang_zhi_bo` | 早上 8:30 開燈開 TV + 播直播（手動 Trigger = 完整 dry run） |

entity ID 是 friendly name 的 slug，**改過名字就變**——用 API 查，不要憑記憶。

## 其他

- YouTube / 直播偵測 / cast 播放模式：`references/youtube-cast.md`
- 網路拓撲、檔案權限、log、http.ban：`references/infrastructure.md`
- MCP（pi-mcp-adapter + HA mcp_server）與排障：`references/mcp-setup.md`
