# Minecraft Java Edition 伺服器

採 **Velocity Proxy + Fabric Backend** 雙容器架構：

- 玩家連線（TCP 25565）由 Velocity 代理做正版驗證後，再以 Velocity Modern Forwarding 轉送至後端 Fabric 伺服器。
- Fabric 後端為 `online-mode=false`，透過 [FabricProxy-Lite](https://modrinth.com/mod/fabricproxy-lite) 驗證來自 Velocity 的 forwarding secret，未攜帶正確 secret 的直連會被拒絕。
- Simple Voice Chat（UDP 25577）由 Velocity proxy plugin 接收，再轉送到對應後端伺服器。

## 架構

```
玩家 (正版) ─TCP 25565─▶ Traefik ─▶ minecraft-velocity (online-mode=true, modern fwd)
                                       │
語音 ─UDP 25577─▶ Traefik ──────────────┤
                                       │
                                       ▼ (network: minecraft_internal, internal=true)
                                     minecraft (online-mode=false, FabricProxy-Lite)
                                       ▲
                                       └─ Simple Voice Chat 由 Velocity plugin 轉發
```

| 容器 | 角色 | 對外埠 | 加入網路 |
|------|------|--------|----------|
| `minecraft-velocity` | 玩家入口、正版驗證、語音代理 | TCP 25565、UDP 25577（皆經 Traefik） | `t3_proxy`、`minecraft_internal` |
| `minecraft` | Fabric 後端、語音終端 | 不對外暴露 | `default`（下載依賴）、`minecraft_internal`（與 Velocity 通訊） |

`minecraft_internal` 設為 `internal: true`，後端 TCP 25565 不會經由 Docker bridge 對外暴露。
後端也不再加入 `t3_proxy`，Simple Voice Chat 的 UDP 僅需對外開在 Velocity proxy。
另外 backend 仍保留 compose 預設 `default` bridge 網路，僅用於容器啟動時對外下載 Fabric loader / mods；因為沒有 `ports:` 映射，依然不會直接對外提供服務。

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
| `VELOCITY_MODRINTH_PLUGINS` | Velocity 端 Modrinth plugin 清單 | `minimotd,simple-voice-chat:alpha` |

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
| Global Whitelist 設定 | `${DATADIR}/velocity/plugins/global-whitelist/config.properties` | ❌（runtime data） |
| Global Whitelist 名單 | `${DATADIR}/velocity/plugins/global-whitelist/whitelist.json` | ❌（runtime data） |
| Simple Voice Chat proxy 設定 | `${DATADIR}/velocity/plugins/voicechat/voicechat-proxy.properties` | ❌（runtime data） |
| FabricProxy-Lite 設定 | `${DATADIR}/minecraft/config/FabricProxy-Lite.toml` | ❌（含 secret，禁止版控） |
| MiniMOTD 設定 | `${DATADIR}/velocity/plugins/minimotd-velocity/main.conf` + `icons/` | ❌（runtime data） |
| 後端世界與 server.properties | `${DATADIR}/minecraft/` | ❌ |

## 白名單（Global Whitelist）

白名單由 [Global Whitelist](https://modrinth.com/plugin/global-whitelist) 在 **Velocity 層**管理，而非後端 Minecraft server。

**設計原因**：後端允許機器人（bot）容器加入 `minecraft_internal` 網路直連，若白名單放在後端，機器人也需要加入白名單。改放在 Velocity 層後，機器人繞過 Velocity 直連後端不受白名單限制，真人玩家仍須通過 Velocity 驗證。

> 插件版本不在 Modrinth 的 `1.21.x` 相容性宣告內，因此不透過 `MODRINTH_PROJECTS` 安裝，而是手動放置 jar：
> `${DATADIR}/velocity/plugins/global-whitelist-1.0.jar`

後端的 `white-list` 保持 `false`（`server.properties`）。

### 管理玩家

透過 Velocity 控制台（`docker attach minecraft-velocity`，Ctrl+P Ctrl+Q 離開）：

```
globalwhitelist add <玩家名>
globalwhitelist remove <玩家名>
globalwhitelist list
globalwhitelist reload
```

或直接編輯 `whitelist.json` 後執行 `globalwhitelist reload`。`whitelist.json` 格式與原版相同：

```json
[{"uuid":"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx","name":"PlayerName"}]
```

新增玩家時需要 Mojang UUID（帶連字號格式）：

```bash
curl -s "https://api.mojang.com/users/profiles/minecraft/<玩家名>" | python3 -c "
import sys, json, uuid
d = json.load(sys.stdin)
print(str(uuid.UUID(d['id'])), d['name'])
"
```

## Simple Voice Chat Proxy

- Velocity 端需要安裝 `simple-voice-chat` plugin；backend 仍需安裝 `simple-voice-chat` mod，proxy 後面的每台 Minecraft server 都要有語音端。
- 目前 Modrinth 上的 Velocity 版 `simple-voice-chat` 僅提供 `alpha` 候選版，因此 compose 預設使用 `simple-voice-chat:alpha`，避免 itzg 映像只接受 `release` 版本時啟動失敗。
- 對外只需開一個 UDP 埠給 proxy。此部署改採官方常見做法，使用 `25577/udp`。
- plugin 第一次啟動後會產生 `${DATADIR}/velocity/plugins/voicechat/voicechat-proxy.properties`。
- 若保留預設 `port=-1`，plugin 會沿用 Velocity proxy 的遊戲埠 `25577`；若你想明確寫死，也可改成 `port=25577`。
- `voice_host` 通常不需要手動調整；只有在要強制公告不同主機名或埠號時才需修改。

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

首次啟動 `minecraft-velocity` 後，建議確認 voice chat proxy 設定已生成且埠號正確：

```bash
grep -E '^(port|voice_host)=' /mnt/raid1/velocity/plugins/voicechat/voicechat-proxy.properties
```

預期至少看到以下其中一種：

```properties
port=-1
```

或

```properties
port=25577
```

若你手動修改成其他值，記得同步調整 Traefik `voicechat` entrypoint、router port forward 與文件。

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
| 語音 client 連不上，但遊戲可正常登入 | Router / 防火牆仍只開 `24454/udp` 或 Traefik 未改成 `25577/udp` | 關閉 `24454/udp`，改放行並轉發 `25577/udp` 到 Traefik；確認 proxy config `port` 與 Traefik 一致 |
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
