# Minecraft Java Edition 伺服器

採 **Velocity Proxy + Fabric Backend** 雙容器架構：

- 玩家連線（TCP 25565）由 Velocity 代理做正版驗證後，再以 Velocity Modern Forwarding 轉送至後端 Fabric 伺服器。
- Fabric 後端為 `online-mode=false`，透過 [FabricProxy-Lite](https://modrinth.com/mod/fabricproxy-lite) 驗證來自 Velocity 的 forwarding secret，未攜帶正確 secret 的直連會被拒絕。
- Simple Voice Chat（UDP 24454）不經 Velocity，直接由 Traefik 轉到後端容器。

## 架構

```
玩家 (正版) ─TCP 25565─▶ Traefik ─▶ minecraft-velocity (online-mode=true, modern fwd)
                                       │
                                       ▼ (network: minecraft_internal, internal=true)
                                     minecraft (online-mode=false, FabricProxy-Lite)
                                       ▲
語音 ─UDP 24454─▶ Traefik ──────────────┘ (Simple Voice Chat 直接到後端)
```

| 容器 | 角色 | 對外埠 | 加入網路 |
|------|------|--------|----------|
| `minecraft-velocity` | 玩家入口、正版驗證 | TCP 25565（經 Traefik） | `t3_proxy`、`minecraft_internal` |
| `minecraft` | Fabric 後端、語音 | UDP 24454（經 Traefik） | `t3_proxy`（語音）、`minecraft_internal`（與 Velocity 通訊） |

`minecraft_internal` 設為 `internal: true`，後端 TCP 25565 不會經由 Docker bridge 對外暴露。

## 環境變數（.env）

### 後端 Fabric

| 變數 | 說明 | 預設 |
|------|------|------|
| `MINECRAFT_VERSION` | Minecraft 版本（同時用於 Velocity Modrinth plugin 篩選） | `1.21.11` |
| `MINECRAFT_TYPE` | 伺服器類型 | `FABRIC` |
| `MINECRAFT_MEMORY` | JVM 記憶體 | `2G` |
| `MINECRAFT_MODRINTH_MODS` | Fabric 模組清單（逗號分隔；**務必包含 `fabricproxy-lite`**） | 見 compose 預設 |
| `MINECRAFT_IMAGE_TAG` | itzg/minecraft-server 映像標籤 | `latest` |

> 後端的 `online-mode` / `enforce-secure-profile` 由 compose 強制設為 `FALSE`，每次啟動會覆寫 `server.properties`，請勿手動改回 `true`。

### Velocity Proxy

| 變數 | 說明 | 預設 |
|------|------|------|
| `VELOCITY_VERSION` | Velocity 版本（itzg/mc-proxy 拉取） | `latest` |
| `VELOCITY_MEMORY` | JVM 記憶體 | `512M` |
| `VELOCITY_MEMORY_LIMIT` | compose `deploy.resources.limits.memory` | `768m` |
| `VELOCITY_CPU_LIMIT` | compose `deploy.resources.limits.cpus` | `1.0` |
| `VELOCITY_IMAGE_TAG` | itzg/mc-proxy 映像標籤 | `latest` |
| `VELOCITY_MODRINTH_PLUGINS` | Velocity 端 Modrinth plugin 清單 | `minimotd` |

## Forwarding secret（必要前置）

Velocity 與 FabricProxy-Lite 共用同一個 secret，**未產生此檔的情況下伺服器無法啟動**：

```bash
openssl rand -hex 24 | tr -d '\n' > /opt/docker/secrets/velocity_forwarding_secret
chmod 600 /opt/docker/secrets/velocity_forwarding_secret
```

> **注意**：必須用 `tr -d '\n'` 去掉 trailing newline，否則 FabricProxy-Lite.toml 內的字串會與 Velocity 讀到的檔案內容不一致，導致 `Mismatched secret` 拒連。

`secrets/velocity_forwarding_secret` 已被 `.gitignore` 涵蓋，不會被提交。

第一次啟動完成後，需把同一個 secret 寫入後端 FabricProxy-Lite 的設定（mod 第一次啟動會產生空模板）：

```bash
SECRET=$(tr -d '\n' < /opt/docker/secrets/velocity_forwarding_secret)
sed -i "s|^secret = \"\"|secret = \"$SECRET\"|" /mnt/raid1/minecraft/config/FabricProxy-Lite.toml
```

或一次性手動建立：

```bash
SECRET=$(tr -d '\n' < /opt/docker/secrets/velocity_forwarding_secret)
cat > /mnt/raid1/minecraft/config/FabricProxy-Lite.toml <<EOF
hackOnlineMode = false
hackEarlySend = true
hackMessageChain = false
disconnectMessage = "This server requires you to connect with Velocity."
secret = "$SECRET"
EOF
```

> **`hackEarlySend = true` 是必要的**。預設 `false` 會讓 LuckPerms-Fabric 在 pre-login 階段拿到離線 hash UUID，使新玩家被踢：
> `Permissions data for your user was not loaded during the pre-login stage`。
> 開啟後 FabricProxy-Lite 會在更早的階段注入 Velocity 轉發來的真實 Mojang UUID，LuckPerms 才能正確預載資料。

## 設定檔位置

| 設定檔 | 路徑 | 是否版控 |
|--------|------|----------|
| Velocity 主設定 | `appdata/velocity/velocity.toml` | ✅（hand-written） |
| Velocity forwarding secret | `secrets/velocity_forwarding_secret` | ❌（git-ignored） |
| FabricProxy-Lite 設定 | `${DATADIR}/minecraft/config/FabricProxy-Lite.toml` | ❌（含 secret，禁止版控） |
| MiniMOTD 設定 | `${DATADIR}/velocity/plugins/minimotd-velocity/main.conf` + `icons/` | ❌（runtime data） |
| 後端世界與 server.properties | `${DATADIR}/minecraft/` | ❌ |

## MOTD / 圖示

由 [MiniMOTD-Velocity](https://modrinth.com/plugin/minimotd) 在 Proxy 端處理（不是後端）：

- 設定：`${DATADIR}/velocity/plugins/minimotd-velocity/main.conf`
- icon：`${DATADIR}/velocity/plugins/minimotd-velocity/icons/<name>.png`，於 `main.conf` 以 `icon=<name>` 引用

把 MiniMOTD 放在 Proxy 端的好處：玩家在伺服器列表 ping 時不會打到後端，可以保留 itzg `pause-when-empty-seconds` 的省資源效果。

`velocity.toml` 內的 `motd` 欄位會被 MiniMOTD 取代，僅作為插件未載入時的 fallback。注意 Velocity 3 的 MOTD 使用 [MiniMessage](https://docs.papermc.io/adventure/) 格式（`<bold><green>...</green></bold>`），不再支援 `§` legacy 顏色碼。

## 第一次部署

```bash
# 1. 建立 forwarding secret（見上節）
openssl rand -hex 24 | tr -d '\n' > /opt/docker/secrets/velocity_forwarding_secret
chmod 600 /opt/docker/secrets/velocity_forwarding_secret

# 2. 建立 Velocity runtime 目錄
mkdir -p /mnt/raid1/velocity

# 3. 第一次只起後端，等 fabricproxy-lite 模組下載完
docker compose -f docker-compose-app.yml up -d minecraft
docker compose -f docker-compose-app.yml logs -f minecraft   # 等 "Done"
docker compose -f docker-compose-app.yml stop minecraft

# 4. 把 secret 寫入 FabricProxy-Lite.toml（見上節）

# 5. 啟動完整 stack
docker compose -f docker-compose-app.yml up -d minecraft minecraft-velocity
```

## 常用指令

```bash
# 啟動 / 停止
docker compose -f docker-compose-app.yml up -d minecraft minecraft-velocity
docker compose -f docker-compose-app.yml stop minecraft minecraft-velocity

# 看後端 log（含遊戲輸出）
docker compose -f docker-compose-app.yml logs -f minecraft

# 看 Velocity log
docker compose -f docker-compose-app.yml logs -f minecraft-velocity

# 後端 RCON 控制台
docker exec -it minecraft rcon-cli
# 或單行指令
docker exec minecraft mc-send-to-console "op <玩家ID>"

# Velocity 控制台
docker attach minecraft-velocity   # Ctrl+P, Ctrl+Q 離開但不關閉
```

## 備份

世界與後端設定：

```bash
docker compose -f docker-compose-app.yml stop minecraft
tar -czvf minecraft-backup-$(date +%Y%m%d-%H%M%S).tar.gz -C "${DATADIR}" minecraft
docker compose -f docker-compose-app.yml up -d minecraft
```

Velocity 端通常不需要備份（plugin 設定可在 git 與 `appdata/velocity/` 內維護），但若 MiniMOTD config 有變動可一併備：

```bash
tar -czvf velocity-plugins-$(date +%Y%m%d-%H%M%S).tar.gz \
  -C "${DATADIR}/velocity" plugins
```

## Mineflayer / Bot 接入

後端為 offline-mode、且 FabricProxy-Lite 強制 forwarding secret 驗證，bot 不能直接連 `minecraft:25565` 而省略 secret。建議方式：

1. **把 bot 容器加入 `minecraft_internal` 網路**（`networks: [minecraft_internal]`），透過容器名 `minecraft` 連線。
2. Bot 端必須帶 forwarding payload —— 即實作 Velocity Modern Forwarding 的 LoginPluginRequest/Response。Mineflayer 目前沒有原生支援，需自行用插件處理或改用 `mineflayer-velocity` 之類的 wrapper。
3. 簡單路線：暫時把 FabricProxy-Lite 的 `secret` 留空（停用驗證）並改用 IP 白名單模組（[IP Whitelist Fabric](https://modrinth.com/mod/ip-whitelist) 之類）只允許 `minecraft_internal` 網段的 IP，bot 可直接以 `auth='offline'` 連入。**不建議在公開伺服器使用**，僅適合私服。

## 疑難排解

| 症狀 | 可能原因 | 處理 |
|------|----------|------|
| 玩家被踢 `Permissions data for your user was not loaded during the pre-login stage` | FabricProxy-Lite `hackEarlySend=false` | 改 `true` 並重啟後端 |
| 玩家被踢 `This server requires you to connect with Velocity.` | secret 不一致 / 直連到後端 | 確認 `velocity_forwarding_secret` 與 `FabricProxy-Lite.toml` 的 `secret` 內容一致；檢查 secret 檔末尾沒有 `\n` |
| Velocity 啟動失敗 `Can't parse your MOTD ... Legacy formatting codes` | `velocity.toml` 內仍是 `§` 顏色碼 | 改成 MiniMessage 格式 |
| Velocity 啟動失敗 `chown: changing ownership of '/server/forwarding.secret': Read-only file system` | 用 docker secret 而非 bind mount | 維持 compose 內 bind mount 寫法 |
| MOTD 顯示成 `server.properties` 那行而不是 MiniMOTD 隨機文案 | MiniMOTD 還沒搬到 Proxy / Velocity 沒套 plugin | 確認 `${DATADIR}/velocity/plugins/minimotd-velocity/` 存在、`MODRINTH_PROJECTS` 含 `minimotd` |
| LP 警告 `UUID is NOT Mojang-assigned (type 3)` | 後端把 forwarding 失效，玩家被當離線 | 確認 backend log 有 `fabricproxy-lite` 載入；FabricProxy-Lite secret 正確 |

## 升級 / 換版本

- **Minecraft 版本**：在 `.env` 改 `MINECRAFT_VERSION`，重啟 `minecraft` 容器（mod 會自動依新版本下載）。Velocity 端的 `MINECRAFT_VERSION` 也會跟著變，僅用於 Modrinth plugin 篩選。
- **單獨升 Velocity**：在 `.env` 設 `VELOCITY_VERSION` 為特定版本（如 `3.4.0`），重啟 `minecraft-velocity`。
- **單獨升 plugin**：直接放 jar 到 `${DATADIR}/velocity/plugins/` 並刪舊版，重啟 `minecraft-velocity`。

## 參考

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server)
- [itzg/docker-mc-proxy](https://github.com/itzg/docker-mc-proxy)
- [Velocity 設定說明](https://docs.papermc.io/velocity/configuration)
- [FabricProxy-Lite](https://modrinth.com/mod/fabricproxy-lite)
- [MiniMOTD](https://modrinth.com/plugin/minimotd)
- [Simple Voice Chat](https://modrinth.com/plugin/simple-voice-chat)
