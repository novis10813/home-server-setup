# YouTube 直播偵測 + cast TV 播放（已驗證模式）

## 直播偵測：頻道 `/live` 頁面

**原理**（2026-09 實測）：
- 頻道**直播中**：`https://www.youtube.com/@<handle>/live`（或 `https://www.youtube.com/channel/<channel_id>/live`）
  的頁面**含** `"videoDetails":{"videoId":"<直播videoId>"`（不管有没有 302 重定向，body 裡都有）
- **非直播**：同一 URL 回頻道頁/空頁，**不含** `videoDetails` → 偵測不到 → unknown

**不要用 RSS 判斷「直播開始」**：`https://www.youtube.com/feeds/videos.xml?channel_id=UC...`
的 `<published>` 是直播**結束**時間（例：8:30–9:00 的直播，entry 約 9:05 才出現）。
RSS 只適合拿「最近已結束的影片」，不適合「現在直播中嗎」。

**24/7 直播的 video ID 會隨時間換**（主播重開直播）——不要 hardcode，用偵測跟隨。
（例：札幌 24/7 的 ID 在 2026-05 是 `TPIzbMwlrOI`，2026-09 已變 `3DKzPUylj_w`。）

## REST sensor 範例（configuration.yaml）

```yaml
rest:
  - resource: "https://www.youtube.com/@yutinghaofinance/live"
    scan_interval:
      minutes: 2            # 越小越快偵測到直播開始
    headers:
      User-Agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    sensor:                 # 是 sensor: 不是 sensors:
      - name: YutingHao Live Video
        unique_id: yt_yutinghao_live_video
        value_template: >-
          {% set m = value | regex_findall('"videoDetails":\\{"videoId":"([A-Za-z0-9_-]{11})"') %}{% if m %}{{ m[0] }}{% else %}unknown{% endif %}
```

- entity ID = name 的 slug：`sensor.yutinghao_live_video`
- 直播中 = video ID；非直播 = `unknown`
- 本 instance 現有的：`sensor.yutinghao_live_video`（財經皓角，2 分鐘，早上 8:30 自動化用）

## TV 播 YouTube：走 Cast，不要走 Android TV Remote 深層連結

客廳電視在 HA 有兩組 entity（同一台 Google TV）：

| entity | 平台 | 用途 |
|--------|------|------|
| `media_player.ke_ting_dian_shi` | cast | **播 YouTube** |
| `media_player.ke_ting_dian_shi_2` / `remote.ke_ting_dian_shi` | androidtv_remote | 開關機、送按鍵 |

**地雷（2026-09-25 實測）**：對 androidtv_remote 的 `media_player.ke_ting_dian_shi_2` 送
`play_media` `vnd.youtube://<id>`（`media_content_type: app`）= 深層連結冷啟動 YouTube App，
會**卡在「選擇帳號／誰在觀看？」頁**，要人按一下才進影片。
改用 Cast（YouTube 接收端，app_id `233637DE`，與手機投放同路徑）直接進影片，不經帳號頁：

```yaml
action: media_player.play_media
target:
  entity_id: media_player.ke_ting_dian_shi
data:
  media_content_type: cast
  media_content_id: '{"app_name": "youtube", "media_id": "<video_id>"}'
```

已包成 `script.tv_cast_youtube`（`/mnt/raid1/homeassistant/scripts.yaml`，參數 `video_id`）。

**首次投放常失敗**：YouTube 接收端剛啟動時拿不到 screen_id →
`400 Client Error: screen_ids parameter error ... get_lounge_token_batch`，再投一次就成功。
這是 `requests` 的 HTTPError，**不是 HomeAssistantError，`continue_on_error` 接不住**
（`helpers/script.py` `_handle_exception`），直接呼叫會中止整個自動化。
所以自動化用 `script.turn_on`（非阻塞，錯誤留在 script 內）+ `repeat`：
`wait_for_trigger` 等 `tv_cast_youtube_done` 事件 15 秒，沒收到就再投，最多 3 次。
`script.tv_cast_youtube` 在 `play_media` 成功後才發這個事件（失敗時 `play_media` 拋錯，走不到這步）。

**不要用 `media_content_id` 確認投放成功**（2026-10 實測）：Cast 播 YouTube 時該屬性回報空字串，
等待永遠逾時 → 每 15 秒重投、共 3 次。使用者在這 45 秒內切到別支影片會被拉回來。

## 自動化模式（2026-09 簡化版）

`automation.zao_shang_kan_zha_huang_zhi_bo` 現行結構（完整 YAML 見
`/mnt/raid1/homeassistant/automations.yaml`）：

- **triggers**：只有一支 `time` 08:30（`weekday: mon~fri`）。**無 state trigger**。
- **actions**：`media_player.turn_on`（TV entity）→ `switch.turn_on`（門前插座 entity）
  → `delay 10s` → `if sensor ≠ unknown/unavailable` 才以 `script.turn_on script.tv_cast_youtube`
  （`video_id: {{ states('sensor.yutinghao_live_video') }}`）Cast 播放，失敗重試最多 3 次（見上節）。
  全部用 **entity_id** 而非 device_id（device_id 會失效且不可讀）。

**設計沿革**：舊版（2026-02）有 state trigger + 札幌 24/7 fallback，理由是「8:30 整
`/live` 頁面還沒上線」。**實測推翻**：2026-09 直播 ID 約 8:00 前就發布（YouTube
提前建立直播），8:30 讀 sensor 直接拿到 ID，fallback 與 state trigger 從未被用到，
2026-09 依使用者要求移除（週末不觸發、無 24/7 墊場）。若日後直播 ID 發布習慣
改變（8:30 時仍 unknown），再考慮加回偵測補播。

**注意**：`/live` 偵測只適合「頻道同時只有一條直播」的情況（如財經皓角）。多條直播的頻道改用下一節的 `/streams` 清單。

## 列出頻道所有直播：`/streams` 頁（2026-10）

頻道 `/live` 頁只回傳「其中一條」直播。同頻道同時有多條時（朝日新聞LIVE 同時 11 條），
`/live` 挑到哪條不可控（2026-10 實測：想看札幌，`/live` 回的是伊丹空港）。

`https://www.youtube.com/channel/<UC...>/streams`（或 `/@handle/streams`）的 `ytInitialData` 內，
每支影片是一個 `lockupViewModel`（2026-10 已不是 `videoRenderer`），`contentId` = video ID，
直播中的縮圖帶 `THUMBNAIL_OVERLAY_BADGE_STYLE_LIVE`。一頁約 1.2MB。

實作（HA config 目錄，非版控）：

| 元件 | 位置 | 說明 |
|------|------|------|
| `/config/yt_live/yt_live_streams.py` | 腳本 | 參數 = 頻道（`UC...` 或 `@handle`，可多個）；輸出 `{"count","streams":[{channel,id,title}],"errors"}`。單一頻道失敗只記進 `errors` |
| `sensor.youtube_live_streams` | `configuration.yaml` `command_line:` | 每 10 分鐘跑腳本；state = 直播數，attribute `streams` / `errors` |
| `input_select.yt_live_stream` | `configuration.yaml` `input_select:` | 下拉選單，選項格式「頻道｜標題前 40 字 [videoID]」 |
| `automation.youtube_zhi_bo_qing_dan_tong_bu_dao_xia_la_xuan_dan` | `automations.yaml`（id `yt_live_update_options`） | sensor 變動或 HA 啟動時 `input_select.set_options`；目前選擇仍在清單內會被保留 |
| `script.tv_cast_selected_live` | `scripts.yaml` | 從選項尾端 `[videoID]` 取 ID 投放，失敗最多重試 3 次（每次等 15 秒 `tv_cast_youtube_done` 事件）；取不到 ID（「目前沒有直播」）直接結束 |

video ID 寫在選項文字裡，而不是用 index 對回 sensor，因此 sensor 剛好刷新時也不會播錯。

**新增頻道**：在 `command_line` sensor 的 `command` 尾端加頻道 ID 或 `@handle` → `docker cp` 回容器 →
`command_line.reload`（WS `call_service`，domain 已載入）。channel ID 取法：
`curl -s -A "Mozilla/5.0" "https://www.youtube.com/watch?v=<id>" | grep -o '"channelId":"[^"]*"' | head -1`

## Dashboard「YouTube 直播」分頁（客廳 dashboard 第二頁）

路徑 `dashboard-default` 的 `live` view：一個 `vertical-stack`（markdown 縮圖 + entities 卡），下方保留 `media-control`。

- 縮圖：markdown 卡以 template 從 `input_select.yt_live_stream` 取 `[videoID]`，組 `https://i.ytimg.com/vi/<id>/hqdefault_live.jpg`
- entities 卡：`input_select.yt_live_stream`、button row（`script.turn_on` → `script.tv_cast_selected_live`）、`sensor.youtube_live_streams`（直播數）
- 清單內頻道：Hokkaido Kurashi no Yomimono（`UCIMs8atP2qoxcfAvhiFlzGQ`）、朝日新聞LIVE（`UCaHr0a1x8zmQ1dxanCeuesA`）、
  台北觀光即時影像 @taipeitravelofficial（`UCJLjpq7pTJRbP3vtx0LxB9Q`）
- 2026-10 前是每頻道一張卡（REST `/live` sensor + `script.tv_cast_live`），因 `/live` 只回一條而換掉，舊 sensor 與 script 已刪除

### 改 dashboard 的方法

dashboard 存在 `/config/.storage/lovelace.dashboard_default`（UI storage 模式），
**不要直接改檔案**。用 WS `lovelace/config/save`（`url_path` 為 `dashboard-default`）：先
`docker cp` 備份檔案，讀出 JSON 的 `data.config`，改完後整份送出：

```bash
node scripts/ha_ws.mjs <ha_url> <token> '[{"type":"lovelace/config/save","url_path":"dashboard-default","config":{...整份 config...}}]'
```

`lovelace/config`（讀）在 storage 模式下也要帶 `url_path`，不帶會回 `config_not_found`。

## 排障

- TV `media_title` 常回報 `None`（cast status 延遲）——**以實體電視畫面為準**
- 偵測不到直播但確認有播：直接 `curl -A "Mozilla/5.0" https://www.youtube.com/@<handle>/live | grep -o '"videoDetails":{"videoId":"[^"]*"'` 看頁面到底有沒有
- 24/7 頻道 handle 拿不到時改用 channel ID：watch 頁 grep `"channelId":"UC..."`
