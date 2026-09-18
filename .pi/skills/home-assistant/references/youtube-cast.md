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

## cast TV 播 YouTube（vnd.youtube:// 格式）

本 instance 的客廳電視 = `media_player.ke_ting_dian_shi_2`（cast）。
`media_player.play_media` 的 `data.media`：

```yaml
media:
  media_content_id: "vnd.youtube://{{ trigger.to }}"   # video ID（直播 ID 也照樣用）
  media_content_type: app
  metadata:
    navigateIds:
    - {}
    - media_content_type: ''
      media_content_id: __MANUAL_ENTRY__
    browse_entity_id: media_player.ke_ting_dian_shi_2
```

`__MANUAL_ENTRY__` 是 UI「手動輸入 video ID」路徑生成的 navigate 格式，服務呼叫照抄即可。

## 自動化模式：固定時間開播 + 直播上線自動切換

本 instance 的 `automation.zao_shang_kan_zha_huang_zhi_bo` 用的結構（完整 YAML 見
`/mnt/raid1/homeassistant/automations.yaml`）：

- **triggers**：
  - `time` 08:30（每天）
  - `state`：`sensor.yutinghao_live_video`（sensor 出現新 video ID = 直播上線）
- **actions**：`choose`
  - 條件分支（`trigger.trigger == 'state'`）：直播上線時，若 TV 開著（`on`/`playing`）且週一~五 → 播 `vnd.youtube://{{ trigger.to }}`
  - `default:` 分支（time + 手動 Trigger）：TV turn_on → switch turn_on → delay 10s → 播 template 選定的影片

**default 分支的影片選擇 template**（優先級：週一~五的財經直播 > 札幌 24/7 > 固定 fallback ID）：

```jinja
vnd.youtube://{% set yut = states('sensor.yutinghao_live_video') %}{% set sap = states('sensor.sapporo_247_live_video') %}{% set vid = 'TPIzbMwlrOI' %}{% if sap not in ('unknown', 'unavailable') %}{% set vid = sap %}{% endif %}{% if now().weekday() < 5 and yut not in ('unknown', 'unavailable') %}{% set vid = yut %}{% endif %}{{ vid }}
```

**為什麼要兩層**：財經直播 8:30 整開始，8:30 那一刻 `/live` 頁面還沒上線（幾秒~幾分鐘延遲），
所以 8:30 先播 24/7 墊場，state trigger 在下一輪 scan（2 分鐘內）抓到直播 ID 後自動切換。
`mode: single` 避免兩支觸發重疊。

## 排障

- TV `media_title` 常回報 `None`（cast status 延遲）——**以實體電視畫面為準**
- 偵測不到直播但確認有播：直接 `curl -A "Mozilla/5.0" https://www.youtube.com/@<handle>/live | grep -o '"videoDetails":{"videoId":"[^"]*"'` 看頁面到底有沒有
- 24/7 頻道 handle 拿不到時改用 channel ID：watch 頁 grep `"channelId":"UC..."`
