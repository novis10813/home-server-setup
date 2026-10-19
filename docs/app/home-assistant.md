# Home Assistant

Home Assistant 以單一容器部署，經 Traefik 以內網 HTTPS 子網域提供服務。

## 存取

- **網址**：`https://ha.${DOMAINNAME_1}`
- **認證**：使用 Home Assistant 內建登入；Traefik 套用 `chain-oauth@file`

## 網路架構

Home Assistant 同時連接兩個網路：

| 網路 | 用途 |
|---|---|
| `t3_proxy` | 讓 Traefik 以 Docker provider 發現並代理（動態 IP）|
| `ha_macvlan` | 給 HA 一個真實的 LAN IP，讓 mDNS 自動發現正常運作 |

### 為什麼需要 macvlan

Docker 的 bridge network 會阻擋 multicast 封包（UDP 5353），導致 mDNS / Zeroconf 完全失效。HomeKit、ESPHome、Sonos、Chromecast 等智慧家居裝置的自動發現全部仰賴 mDNS，因此需要透過 macvlan 讓 HA 拿到一個真實的 LAN IP，讓區網上的設備能直接找到它。

### 建立 ha_macvlan 網路

`ha_macvlan` 不由 Compose 管理，需手動建立（僅需執行一次）：

```bash
docker network create \
  --driver macvlan \
  --opt parent=enp4s0 \
  --subnet 192.168.0.0/24 \
  --gateway 192.168.0.1 \
  --ip-range 192.168.0.240/28 \
  ha_macvlan
```

- `parent`：主機對外的實體網卡（用 `ip link show` 確認）
- `ip-range`：限縮在 `.240–.254`，避免與 DHCP 衝突，請確認路由器的 DHCP 範圍不與此重疊

> **注意**：macvlan 有一個 kernel 層級的限制——宿主機本身無法直接和 macvlan 容器通訊（無法 ping 到 HA 的 LAN IP）。這不影響實際使用，因為 Traefik 走 t3_proxy、區網設備走 macvlan，但 debug 時要留意。

## 反向代理（Traefik）必設

HA 收到來自 Traefik 的請求時，必須明確信任該代理，否則會出現 reverse proxy 錯誤。

在 `${DATADIR}/homeassistant/configuration.yaml` 中加入（若已有 `http:` 區塊則合併）：

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 192.168.90.254   # Traefik 在 t3_proxy 的固定 IP
```

儲存後重啟容器使設定生效：

```bash
docker compose -f docker-compose-app.yml restart home-assistant
```

## 資料目錄

- 設定與運行時資料：`${DATADIR}/homeassistant`（對應容器內 `/config`）
- 此目錄不納入版控，備份時請一併處理

## compose 設定重點

`ha_macvlan` 是在 Compose 外部手動建立的網路，因此在 compose 檔案底部必須宣告為 `external: true`，否則啟動時會報錯：

```yaml
networks:
  t3_proxy:
    external: true
  ha_macvlan:
    external: true
```

`t3_proxy` 不需要指定固定 IP（`ipv4_address`），讓 Docker 自動分配即可，Traefik 透過 labels 代理不依賴固定 IP。

## 客廳電視：tv-vibehack 桌面

### 設備與目前狀態

2026-10-19 透過主機 ADB 安裝並測試 [tv-vibehack](https://github.com/Gathin23/tv-vibehack)，不是 HA 外掛，也沒有更動 HA 設定或自動化。

| 項目 | 實測資訊 |
|---|---|
| 電視 | Philips／TPV，2020/2021 UHD Android TV |
| 裝置代號 | `PH0M_EA_T32` |
| 系統 | Android 10／API 29，安全性更新 2022-09-05 |
| ADB 位址 | `192.168.0.64:5555`，IP 變動時需重新確認 |
| 新桌面 | `com.gathin.tvhome/.MainActivity` |
| 原廠桌面 | `com.google.android.tvlauncher/.MainActivity` |
| 目前預設 | **tv-vibehack**，實測從系統設定頁按 Home 會進入新桌面 |
| HA 遙控 | `remote.ke_ting_dian_shi`、`media_player.ke_ting_dian_shi_2` |
| HA Cast | `media_player.ke_ting_dian_shi`，與遙控整合的狀態可能不同 |

經使用者確認後，**僅停用 user 0 的原廠桌面 `com.google.android.tvlauncher`，未刪除它**。與安裝前清單比對，沒有其他套件新增停用或恢復啟用。未授予新桌面定位權限、未啟用選用的無障礙服務，螢幕保護程式仍為 `com.google.android.backdrop/.Backdrop`。因此 Wi-Fi 按鈕不顯示 SSID。

### 建置來源與常用列

使用上游 `v2.1.0`，commit `38b65eb660a92bb08fa51557eb805344da288a72`。該標籤內 APK 的 `versionName` 是 `2.0`，與 release 標籤不同。自行建置 release APK，未執行會停用原廠桌面的 `build-and-install.sh`。

常用列依原廠「喜愛的應用程式」列設定，不是由使用次數推算：

| 順序 | App | 套件 |
|---|---|---|
| 1 | YouTube | `com.google.android.youtube.tv` |
| 2 | Netflix | `com.netflix.ninja` |
| 3 | Jellyfin | `org.jellyfin.androidtv` |
| 4 | Play 商店 | `com.android.vending` |
| 5 | Moonlight | `com.limelight` |

本次修改僅限建置副本的兩個檔案：

- `launcher/app/src/main/res/values/config.xml`：`dock_apps` 改成上表順序，`columns` 設為 `5`（其他 App 的網格也變成五欄）。
- `launcher/app/src/main/res/layout/item_app.xml`：此標籤的圖示寬度固定，直接設五欄會重疊。將 `card` 改為寬 `140dp`、高 `79dp`，`name` 改為寬 `140dp`、`layout_marginTop="86dp"`。

建置需 JDK 17、Android SDK platform 34／build-tools 34.0.0。從 `launcher/` 執行 `./gradlew --no-daemon --max-workers=2 assembleRelease`，再使用 `adb install -r app/build/outputs/apk/release/app-release.apk` 更新。

本次原始碼、SDK、APK、截圖與設定比對暫存於主機 `/tmp/tv-vibehack-test.XumW0Q/`，**不是持久備份**，系統清理後可能消失。客製 APK 位於 `source/launcher/app/build/outputs/apk/release/app-release.apk`，SHA-256 為 `35eaa2dc4f6f4eac32c594484833efa51809ab0e00a79be6930bd4fee732f55b`。未將 APK 或 ADB／簽章私鑰加入版控。上游 release 使用本機 debug key 簽署，日後更新須沿用相同簽章，否則無法直接覆蓋安裝。

### 日常開啟與 Home 鍵驗證

電視已開啟 USB 偵錯並允許這台伺服器。先確認裝置顯示 `device`，`unauthorized` 表示仍需在電視上接受授權：

```bash
adb connect 192.168.0.64:5555
adb devices -l

# 手動開啟新桌面，不變更預設
adb -s 192.168.0.64:5555 shell am start -W -n com.gathin.tvhome/.MainActivity
```

已驗證新桌面啟動、常用列五個圖示、方向鍵移動及最右側 Moonlight 的焦點。影片播放、HDMI 切換、重新開機後的行為尚未測試。

嘗試只更改預設桌面：

```bash
adb -s 192.168.0.64:5555 shell cmd package set-home-activity --user 0 com.gathin.tvhome/.MainActivity

# 查詢實際 HOME 解析結果
adb -s 192.168.0.64:5555 shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME

# 按 Home，再檢查實際前景
adb -s 192.168.0.64:5555 shell input keyevent KEYCODE_HOME
adb -s 192.168.0.64:5555 shell 'dumpsys activity activities | grep mResumedActivity'
```

**此機型回傳 `Success` 仍不代表切換成功。** 實測 role holder 與偏好記錄已指向新桌面，但 HOME resolver 及實際 Home 鍵仍選擇原廠 `com.google.android.tvlauncher/.MainActivity`。候選中原廠優先序為 `2`，新桌面為 `0`。

另外，`android.settings.HOME_SETTINGS` 雖可解析到系統頁面，開啟後 `com.google.android.permissioncontroller` 會因 `ActionBar` 為 null 而崩潰，不適合靠該頁面切換。

上述嘗試失敗後，先恢復原廠預設偏好，再取得使用者同意，才進一步只停用原廠桌面。**最終接管成功**，操作順序如下，不需套用上游 debloat 清單或停用 `setupwraith`：

```bash
# 先確認新桌面能正常開啟，再停用原廠桌面
adb -s 192.168.0.64:5555 shell am start -W -n com.gathin.tvhome/.MainActivity
adb -s 192.168.0.64:5555 shell pm disable-user --user 0 com.google.android.tvlauncher
adb -s 192.168.0.64:5555 shell cmd package set-home-activity --user 0 com.gathin.tvhome/.MainActivity
```

再次查詢 HOME resolver，結果為 `com.gathin.tvhome/.MainActivity`。另外開啟系統設定 `android.settings.SETTINGS`，確認前景為 `com.android.tv.settings/.MainSettings`，再送出 `KEYCODE_HOME`，前景確實切換到 `com.gathin.tvhome/.MainActivity`。ADB 仍可連線。這項驗證不包含重新開機或實體遙控器特殊按鍵。

若接管後 HOME resolver 或實際 Home 鍵結果不符，立即依下一節重新啟用原廠桌面並恢復預設。

### 恢復原廠桌面

**目前原廠桌面已停用，還原時必須先啟用套件**，再設定預設並開啟：

```bash
adb -s 192.168.0.64:5555 shell pm enable --user 0 com.google.android.tvlauncher
adb -s 192.168.0.64:5555 shell cmd package set-home-activity --user 0 com.google.android.tvlauncher/.MainActivity
adb -s 192.168.0.64:5555 shell am start -W -n com.google.android.tvlauncher/.MainActivity
```

恢復後應再次查 HOME resolver 並實際按 Home 驗證。新桌面不需持續開著 ADB，操作結束後可在電視關閉 USB／網路偵錯。不要將 ADB 連接埠轉發至網際網路。
