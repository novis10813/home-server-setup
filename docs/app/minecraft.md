# Minecraft Java Edition 伺服器

Minecraft 以單一容器部署，**不經 Traefik**，玩家直連主機埠 25565（TCP）。

## 存取

- **連線**：`<主機 IP 或網域>:25565`
- **認證**：無；依需求可於遊戲內或透過插件/模組設定白名單/權限

## 版本與伺服器類型

### 環境變數（.env）

| 變數 | 說明 | 預設 |
|------|------|------|
| `MINECRAFT_VERSION` | Minecraft 版本 | `1.21.11` |
| `MINECRAFT_TYPE` | 伺服器類型（見下表） | `FABRIC` |
| `MINECRAFT_PORT` | 主機對外埠 | `25565` |
| `MINECRAFT_MEMORY` | JVM 記憶體 | `2G` |
| `MINECRAFT_MODRINTH_MODS` | Modrinth 模組清單（逗號分隔；僅 TYPE=FABRIC 時使用） | 見下方「Fabric 效能模組」 |

### TYPE 選擇

| TYPE | 說明 | 玩家端 | 適用情境 |
|------|------|--------|----------|
| **FABRIC** | 模組載入器 | 原版即可（僅伺服器端模組時） | **目前預設**：原味生存 + 伺服器端效能模組 |
| **VANILLA** | 原版 | 原版 | 僅要原版、不裝模組 |
| **PAPER** | Bukkit 系、效能佳、插件多 | 原版即可 | 要插件、不想強制玩家裝模組 |
| **PURPUR** | Paper 分支、更多可調選項 | 原版即可 | 進階調校 |

- **Fabric**：模組由 `MODRINTH_PROJECTS` 在啟動時自動從 Modrinth 下載；本專案預設安裝僅伺服器端效能模組，**玩家用原版客戶端即可連線**。
- **Paper / Purpur**：世界與 Vanilla 相容；可到 [SpigotMC](https://www.spigotmc.org/resources/) 或 [Modrinth](https://modrinth.com/plugins) 找插件。

### Fabric 效能模組（原味生存用）

當 `MINECRAFT_TYPE=FABRIC` 時，預設透過 `MINECRAFT_MODRINTH_MODS` 安裝下列**僅伺服器端**效能模組（皆為 Modrinth 專案代號，可於 .env 覆寫）：

| 模組 | Modrinth 代號 | 說明 |
|------|----------------|------|
| **Fabric API** | `fabric-api` | 多數 Fabric 模組依賴，必裝。 |
| **Lithium** | `lithium` | 遊戲邏輯優化（生物 AI、方塊 tick、碰撞等），顯著降低 tick 時間。 |
| **FerriteCore** | `ferrite-core` | 降低記憶體使用與 GC 停頓。 |
| **Krypton** | `krypton` | 網路層優化，多人時減輕 CPU 負擔。 |
| **C2ME** | `c2me-fabric` | 區塊載入/生成多執行緒化，加快地形生成。 |
| **ModernFix** | `modernfix` | 綜合效能與記憶體優化、修復部分 bug。 |
| **LazyDFU** | `lazydfu` | 延遲 DataFixerUpper 初始化，加快啟動。 |
| **Alternate Current** | `alternate-current` | 紅石粉邏輯優化，紅石機械多時可減少卡頓。 |

若要增減模組，在 `.env` 設定 `MINECRAFT_MODRINTH_MODS` 為逗號分隔的清單（需包含 `fabric-api` 與上述欲保留的模組）。

## 資料與備份

- **世界與設定**：`${DATADIR}/minecraft`（對應容器內 `/data`）
- **備份建議**：升級版本或大改設定前，先停止容器再壓縮備份該目錄，例如：

  ```bash
  docker compose -f docker-compose-app.yml stop minecraft
  tar -czvf minecraft-backup-$(date +%Y%m%d-%H%M%S).tar.gz -C "${DATADIR}" minecraft
  docker compose -f docker-compose-app.yml up -d minecraft
  ```

Fabric 無內建備份，可依排程用主機端腳本對 `${DATADIR}/minecraft` 做壓縮備份，或之後改回 Paper 使用備份插件。

## appdata/minecraft（版控）

- 目前使用 **Fabric**，不依賴 `appdata/minecraft` 內的 Paper patch 或 plugin 設定。
- Paper 專用設定（如活塞複製 patch）已移除；若之後改回 Paper，可參考 `appdata/minecraft/README.md` 恢復 patch 或插件設定。

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

## 若改用 Paper

- 在 `.env` 設 `MINECRAFT_TYPE=PAPER`，並移除或留空 `MINECRAFT_MODRINTH_MODS`（Paper 使用插件而非 Fabric 模組）。
- **活塞複製（TNT／地毯／鐵軌）**：Paper 預設關閉。若要開啟，可在 `${DATADIR}/minecraft/config/paper-global.yml` 的 `unsupported-settings:` 設 `allow-piston-duplication: true`，或於 `appdata/minecraft/patches/` 新增對應 patch 並掛載給容器（見 [Paper 說明](https://docs.papermc.io/paper/reference/global-configuration#unsupported-settings)）。
- **備份**：可透過 Modrinth 安裝插件（如 `backup-on-event`、`simple-backup`），並在 compose 或環境變數中設定對應的 Modrinth 專案與掛載。

## 參考

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server)
- [Fabric](https://fabricmc.net/)
- [Modrinth（模組/插件）](https://modrinth.com/)
- [Paper 官網](https://papermc.io/)
