# 客廳 Android TV：ADB、桌面與韌體

涉及電視 ADB、桌面切換、截圖或韌體時先讀本頁。這是操作摘要，完整安裝、客製建置與驗證紀錄見 [HA 文件](../../../../docs/app/home-assistant.md)的「客廳電視：tv-vibehack 桌面」章節。

## 設備快照與重新查驗

以下為 **2026-10-19 查驗結果**，不是永久狀態。連線前重新確認 IP 與裝置身分，版本及桌面狀態以當次讀取為準，不輸出序號或私鑰。

| 項目 | 已知資訊 |
|---|---|
| 品牌／製造商 | Philips／TPV |
| 系統顯示型號 | `2020/2021 UHD Android TV`，不是完整商品型號 |
| 裝置／平台代號 | `PH0M_EA_T32`／`TPM215E_R` |
| 完整商品型號與地區碼 | **尚未確認**，須由背面標籤或產品資訊頁取得，請使用者遮住序號 |
| 系統與安全性更新 | Android 10／API 29；`2022-09-05` |
| Build | `QTG3.201102.001`，incremental `120437`；建置日期 2022-09-22 |
| CPU ABI | `armeabi-v7a`、`armeabi`，未提供 arm64 ABI |
| ADB 最近位址 | `192.168.0.64:5555`，曾授權此伺服器 |

確認目標後再連線。若為 `unauthorized`，請使用者在電視確認授權，不要繞過：

```bash
adb connect 192.168.0.64:5555
adb devices -l
adb -s 192.168.0.64:5555 shell getprop ro.product.device
adb -s 192.168.0.64:5555 shell getprop ro.build.version.release
adb -s 192.168.0.64:5555 shell getprop ro.build.version.security_patch
adb -s 192.168.0.64:5555 shell getprop ro.build.version.incremental
adb -s 192.168.0.64:5555 shell getprop ro.product.cpu.abilist
```

## 控制路徑不可混用

| 路徑 | 用途與限制 |
|---|---|
| ADB | 查套件、前景、桌面與截圖。可安裝 App，但不是關閉官方 YouTube 廣告或補齊安全更新的工具 |
| Android TV Remote | `remote.ke_ting_dian_shi`／`media_player.ke_ting_dian_shi_2`：電源及按鍵 |
| Cast | `media_player.ke_ting_dian_shi`：YouTube 播放使用既有 `script.tv_cast_youtube` |

兩組 HA entity 狀態可能不同，名稱也可能變動，使用前查 HA。YouTube 播放、首次投放重試與深層連結卡帳號頁的限制，見 [youtube-cast.md](youtube-cast.md)。安裝其他播放器不代表能自動接管既有 Cast。

## 桌面狀態、驗證與還原

快照：目前 HOME 為 `com.gathin.tvhome/.MainActivity`（tv-vibehack）。**原廠 `com.google.android.tvlauncher` 僅在 user 0 停用，未刪除**，未新增停用其他套件。未授予新桌面定位、未啟用無障礙服務，screensaver 保留 `com.google.android.backdrop/.Backdrop`。

先做唯讀查詢，不要為了查狀態重新執行接管流程：

```bash
adb -s 192.168.0.64:5555 shell pm list packages -d --user 0
adb -s 192.168.0.64:5555 shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME
adb -s 192.168.0.64:5555 shell 'dumpsys activity activities | grep mResumedActivity'
```

已知限制：

- `set-home-activity` 回傳 `Success` 不足以證明切換成功。原廠桌面啟用時，曾因 HOME 優先序較高仍被選中。切換後需查 resolver，並在使用者同意操作畫面後按 Home、再查實際前景。
- 不使用 `android.settings.HOME_SETTINGS`：此機曾觸發 `com.google.android.permissioncontroller` 的 null ActionBar 崩潰。一般系統設定 `android.settings.SETTINGS` 曾可正常開啟。
- 已驗證從系統設定按 Home 進入新桌面、五格常用列與方向鍵焦點。尚未驗證重新開機、實體遙控特殊鍵、HDMI 切換或影片播放。
- 客製 APK 更新須沿用原簽章。建置副本及 APK 曾在 `/tmp/tv-vibehack-test.XumW0Q/`，**不是持久備份**，不能假設仍存在。來源、版號、雜湊及常用列配置見上方 HA 文件。

僅在使用者要求還原，或本次已授權桌面操作需要回復時執行。先啟用原廠套件，再設定 HOME：

```bash
adb -s 192.168.0.64:5555 shell pm enable --user 0 com.google.android.tvlauncher
adb -s 192.168.0.64:5555 shell cmd package set-home-activity --user 0 com.google.android.tvlauncher/.MainActivity
adb -s 192.168.0.64:5555 shell am start -W -n com.google.android.tvlauncher/.MainActivity
```

還原後查 HOME resolver，再按 Home 並核對實際前景，不能只看指令回覆。

## 截圖格式注意

此機 `adb exec-out screencap -p` 曾在 PNG 前輸出診斷文字。若圖片無法開啟，以二進位搜尋 PNG signature `b'\x89PNG\r\n\x1a\n'`，移除它之前的內容後再寫檔。不要固定跳過某個位元組數，也不要對 PNG 做文字解碼。找不到 signature 則視為截圖失敗。

## 韌體與操作邊界

- 安全更新通常由原廠韌體提供，ADB 或 Play 商店 App 更新不能補齊系統與驅動漏洞。**尚未確認此台是否有可用官方更新，也未證實已停止支援**。先取得完整商品型號及地區碼，再核對官方 OTA／USB 韌體與更新說明，不能只按平台代號或相近型號選檔。
- 過往同意停用原廠桌面，只涵蓋當次操作，不是未來安裝 App、刷機、重開機、恢復原廠設定、停用其他套件或新增權限的授權。研究更新不等於允許安裝。
- 不執行上游自動安裝／debloat 腳本，不任意授權定位、無障礙服務，不要求關閉 Play Protect。不要把 ADB 連接埠開放至網際網路。
- 截至上述查驗日 **SmartTube 尚未安裝**。若要試裝，重新核對官方安全公告、來源與簽章並取得授權，不把先前安全調查當作現行版本的保證，不擅自登入 Google 或修改 HA Cast。
