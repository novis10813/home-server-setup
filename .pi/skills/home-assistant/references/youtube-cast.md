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
- 本 instance 現有的：`sensor.yutinghao_live_video`（財經皓角，2 分鐘）、`sensor.sapporo_247_live_video`（札幌 24/7，10 分鐘，channel URL `UCIMs8atP2qoxcfAvhiFlzGQ`）

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
`wait_template` 等 `state_attr('media_player.ke_ting_dian_shi','media_content_id') == <video_id>`
15 秒，沒成功就再投，最多 3 次。

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

**注意**：`sensor.sapporo_247_live_video` 已無自動化使用，但**保留**作為 24/7 直播偵測模式的活範例（持續驗證中，要對任何 24/7 頻道做偵測直接抄這個 sensor 改 URL）；成本 = 每 10 分鐘抓一次 YouTube 頁面。

## Dashboard「YouTube 直播」分頁（客廳 dashboard 第二頁）

路徑 `dashboard-default` 的 `live` view：一列 `horizontal-stack`，每個頻道一張
`vertical-stack`（markdown 縮圖 + mushroom-template-card），下方保留 `media-control`。

- 縮圖：markdown 卡內以 template 組 `https://i.ytimg.com/vi/<sensor 值>/hqdefault_live.jpg`
- 點擊：`script.turn_on` → `script.tv_cast_live`，變數 `sensor_entity`（存 video ID 的 sensor）
- `script.tv_cast_live`（`scripts.yaml`）：sensor 為 unknown/unavailable 時直接結束；否則呼叫
  `script.tv_cast_youtube`，最多重試 3 次（每次等 15 秒確認 `media_content_id`）
- 現有頻道：札幌 24/7（`sensor.sapporo_247_live_video`）、朝日新聞 札幌 LIVE
  （`sensor.asahi_sapporo_live_video`，channel `UCaHr0a1x8zmQ1dxanCeuesA`）

**限制**：頻道 `/live` 頁只回傳「其中一條」直播，所以同頻道有多條直播時，卡片播的不一定是你貼的那個連結。
要固定播某一條就不能用 sensor，得直接寫死 video ID（直播結束後要手動換）。

### 新增一個頻道

1. 取 channel ID：`curl -s -A "Mozilla/5.0" "https://www.youtube.com/watch?v=<id>" | grep -o '"channelId":"[^"]*"' | head -1`
2. 在 `configuration.yaml` 的 `rest:` 下加一組 sensor（複製既有的，改 `resource` URL、`name`、`unique_id`，
   `scan_interval` 建議 10 分鐘）。
3. `docker cp` 回容器後 **`docker restart home-assistant`**（新增 YAML 整合只能重啟，見 SKILL.md reload 矩陣），
   確認 log 無 `Invalid config`，且 `sensor.<name>` 有 video ID。
4. 複製 dashboard 的一張 `vertical-stack`，把 sensor entity_id 與標題換掉。

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
