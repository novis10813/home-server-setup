# HA 2026.x API / YAML / template 變化（實測踩坑記錄）

本 instance 為 HA 2026.4.4。以下全部是 2026-09 實測踩過的坑，附原始錯誤訊息。
**外部文件（官方 docs）通常描述的是更新版，遇到不一致以容器安裝碼為準：**
`docker exec home-assistant sh -c "grep -rn '<關鍵字>' /usr/src/homeassistant/homeassistant/ | head"`

## WebSocket API

### 1. auth 握手
- 連線後第一則訊息是 `{"type":"auth_required","ha_version":"..."}`（**不是** `auth`）
- auth 回應**不能帶 `id`**：送 `{"type":"auth","access_token":"..."}`
  - 帶 id 的錯誤：`Auth message incorrectly formatted: extra keys not allowed @ data['id']. Got 1`
- 成功：`{"type":"auth_ok","ha_version":"..."}`；失敗：`auth_invalid`

### 2. call_service 格式
- 必填 **分開的** `domain` 和 `service` 欄位：
  ```json
  {"type":"call_service","domain":"automation","service":"reload","target":{"entity_id":"..."}}
  ```
- 舊格式 `"service":"domain/service"` → `required key not provided @ data['domain']. Got None`
- **成功回傳**：`{id, type:"result", context:{...}}`（**沒有** `success` 欄位）
- **失敗回傳**：`{success:false, error:{code, message}}`

### 3. automation.trigger 變成 entity service
- `homeassistant.trigger` 已移除（`Service homeassistant.trigger not found`）
- 正確：domain=`automation`, service=`trigger`, target=automation entity
- 手動 trigger 的 `trigger.trigger` 值**不是** `'time'`/`'state'`（是 `{"platform":None}` 之類的結構）——
  不要在 choose 裡比對它，用 default 分支接住（見下）

### 4. 讀 config
- automation config：WS `{"type":"automation/config","entity_id":"automation.xxx"}` → `{config:{...raw...}}`
- REST `GET /api/config/automation/config/<id>` 可用；**list 版（無 id）404**
- 舊 command 名稱在 2026.4 全部 `unknown_command`：`device/list`、`config/list_entries`、`logger/list`
  （`automation/config`、`call_service` 可用；其餘遇到就實測/查安裝碼）

### 5. REST service API
- `POST /api/services/<domain>/<service>` 在 2026.4 回 **400 Bad Request**（兩種 body 格式都試過）
- 一律改用 WS `call_service`

## YAML / reload 語意

### 6. reload_core_config 不再載入 YAML 整合
`homeassistant.reload_core_config` 現在只重處理 `homeassistant:` 核心設定
（location/units 等）。**新增 YAML 整合只能重啟容器。**
舊習慣（改完 configuration.yaml 按 reload core）在 2026.x 是 no-op。

### 7. domain reload service 的 chicken-and-egg
`rest.reload`、`automation.reload` 等 domain service 只在該 domain **載入成功後**存在。
YAML 有錯 → domain 沒載入 → reload service not found → 只能重啟。

### 8. check_config 不寫 log
`homeassistant.check_config` 執行完**沒有任何 log 輸出**，WS 也只回 context。
設定有沒有錯，唯一可靠來源是**啟動 log**：
`docker exec home-assistant sh -c "grep -a 'Invalid config' /config/home-assistant.log | tail"`

### 9. choose action 的預設分支 = 頂層 `default:` 鍵
```yaml
- choose:
    - conditions:
        - condition: template
          value_template: "{{ trigger.trigger == 'state' }}"
      sequence:
        - ...
  default:        # 與 choose: 同級（action 層），不是「無條件的分支」
  - ...
```
驗證碼（`homeassistant/helpers/script.py`）：`config[CONF_DEFAULT]`，執行時無分支匹配才跑 default。
寫成「無條件分支」會 YAML parse error。

## Template / 整合

### 10. regex filter 改名
- `regex_findindex` **已移除**：`No filter named 'regex_findindex'.`
- 現行（`helpers/template/extensions/regex.py`）：
  - `regex_findall(value, pattern, ignorecase)` → `re.findall`（**有 capture group 回 group 陣列**）
  - `regex_findall_index(value, pattern, index, ignorecase)` → 回 findall 結果的 `[index]`
  - 也有 `regex_match`、`regex_search`（bool）、`regex_replace`
- 安全寫法（避免無匹配時 IndexError 每 N 分鐘噴錯）：
  ```jinja
  {% set m = value | regex_findall('"videoDetails":\\{"videoId":"([A-Za-z0-9_-]{11})"') %}{% if m %}{{ m[0] }}{% else %}unknown{% endif %}
  ```

### 11. REST 整合 YAML
- 欄位是 `sensor:`（**不是** `sensors:`）：`'sensors' is an invalid option for 'rest', check: rest->0->sensors`
- sensor 的 `value_template` 裡 `value` = response body 文字（非 JSON payload）
