# Minecraft Java Edition 伺服器

Minecraft 以單一容器部署，**不經 Traefik**，玩家直連主機埠 25565（TCP）。

## 存取

- **連線**：`<主機 IP 或網域>:25565`
- **認證**：無；依需求可於遊戲內或透過插件設定白名單/權限

## 版本與伺服器類型

### 環境變數（.env）

| 變數 | 說明 | 預設 |
|------|------|------|
| `MINECRAFT_VERSION` | Minecraft 版本 | `1.21.11` |
| `MINECRAFT_TYPE` | 伺服器類型（見下表） | `PAPER` |
| `MINECRAFT_PORT` | 主機對外埠 | `25565` |
| `MINECRAFT_MEMORY` | JVM 記憶體 | `2G` |

### 效能與插件：TYPE 選擇

| TYPE | 說明 | 玩家端 | 適用情境 |
|------|------|--------|----------|
| **PAPER** | Bukkit 系、效能佳、插件多 | 原版即可 | **推薦**：要效能 + 插件、不想強制玩家裝模組 |
| **PURPUR** | Paper 分支、更多可調選項 | 原版即可 | 進階調校；可設 `USE_SIMD_FLAGS=true` 進一步優化 |
| **FABRIC** | 模組載入器 | 可選裝對應模組 | 要裝伺服器端效能模組（如 Lithium）時 |
| **VANILLA** | 原版 | 原版 | 僅要原版、不裝插件/模組 |

- **Paper / Purpur**：世界與 Vanilla 相容，升級後可直接沿用既有地圖；可到 [SpigotMC](https://www.spigotmc.org/resources/) 或 [Modrinth](https://modrinth.com/plugins) 找插件。
- **Fabric**：需在 compose 或環境變數中設定 `MODRINTH_PROJECTS`（例如 `fabric-api`、`lithium`）由映像自動下載；玩家端不強制裝模組即可連線，僅部分模組需客戶端同裝。

### Paper：允許 TNT／地毯／鐵軌複製（活塞複製）

Paper 預設會關閉「活塞複製」類的機制（TNT、地毯、鐵軌等）。本專案已用 **設定 patch** 在啟動時自動把 `allow-piston-duplication` 設為 `true`。

- **自動套用**：`appdata/minecraft/patches/paper-allow-tnt-dupe.json` 會在容器啟動時由 itzg 映像套用到 `config/paper-global.yml`。若為**首次**用 Paper 啟動，請先正常啟動一次讓 Paper 產生設定檔，再**重啟一次**容器，patch 才會生效。
- **手動修改**：若不想用 patch，可直接編輯 `${DATADIR}/minecraft/config/paper-global.yml`，在 `unsupported-settings:` 區塊中設 `allow-piston-duplication: true`，存檔後重啟伺服器。

（此選項屬 Paper 的 [unsupported-settings](https://docs.papermc.io/paper/reference/global-configuration#unsupported-settings)，未來版本可能更名或移除。）

## 資料與備份

- **世界與設定**：`${DATADIR}/minecraft`（對應容器內 `/data`）
- **備份建議**：升級版本或大改設定前，先停止容器再壓縮備份該目錄，例如：

  ```bash
  docker compose -f docker-compose-app.yml stop minecraft
  tar -czvf minecraft-backup-$(date +%Y%m%d-%H%M%S).tar.gz -C "${DATADIR}" minecraft
  docker compose -f docker-compose-app.yml up -d minecraft
  ```

### 自動備份插件（Paper）

Paper 本身沒有內建備份，可安裝插件做**定時或事件觸發**備份。常用選項（皆支援 Paper 1.21，可從 Modrinth 自動安裝）：

| 插件 | Modrinth 代號 | 說明 |
|------|----------------|------|
| **BackupOnEvent** | `backup-on-event` | 依排程（cron）、玩家進出、指令觸發備份；可壓縮、保留份數、排除目錄。 |
| **Plan** | `plan` | 伺服器數據分析 ＋ 內建備份／還原。 |
| **Simple Backup** | `simple-backup` | 輕量、定時備份世界。 |

**預設已啟用** BackupOnEvent，並透過 **`appdata/minecraft/plugin-configs/BackupOnEvent/config.yml`** 套用「每小時備份、只保留 5 份」。compose 會將 `plugin-configs` 目錄 sync 到容器的 `/data/plugins`，故無須在 `.env` 額外設定即可使用。

- 若要改備份間隔或保留數，請編輯 **`appdata/minecraft/plugin-configs/BackupOnEvent/config.yml`**，改完重啟容器。
- 若要停用備份插件或改裝其他插件，在 `.env` 設定 `MINECRAFT_MODRINTH_PLUGINS`（留空則仍為 `backup-on-event`；設為其他值則依該值下載）。
- 若希望備份寫到主機目錄，可在 compose 多掛載一個 volume 到容器內（例如 `/backups`），並在該 config 裡把備份路徑指到該目錄。

## 常用指令

```bash
# 啟動
docker compose -f docker-compose-app.yml up -d minecraft

# 停止
docker compose -f docker-compose-app.yml stop minecraft

# 查看日誌（含遊戲輸出）
docker compose -f docker-compose-app.yml logs -f minecraft

# 進入容器內執行指令（例如 OP）
docker exec -it minecraft rcon-cli
# 或直接
docker exec -it minecraft mc-send-to-console "op <玩家ID>"
```

## 參考

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server)
- [Paper 官網](https://papermc.io/)
- [Modrinth（插件/模組）](https://modrinth.com/)
