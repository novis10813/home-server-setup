# 本 instance 基礎設施（網路 / 權限 / log / ban）

## 網路拓撲

| 網路 | IP | 用途 / 限制 |
|------|-----|------------|
| `t3_proxy` | **動態**（compose 重建會變） | host 存取 HA 唯一可靠的網路。取目前值：`docker inspect home-assistant --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}}{{"\n"}}{{end}}'`（取 `t3_proxy` 行；注意要用 `$k, $v` 形式，`{{.NetworkName}}` 會報錯） |
| `ha_macvlan` | `192.168.0.250`（固定） | 給 mDNS 用的真實 LAN IP。**host 連不到**（macvlan kernel 限制：host 與 macvlan 容器互不通）——偵錯時別怪「HA 掛了」，是連錯 IP |
| Traefik | `ha.${DOMAINNAME_1}`（443） | 區網/外網入口；token 失效或 IP 變了時的備援路徑 |

HA 重新部署 compose 後 t3_proxy IP 可能變 → MCP（`.pi/mcp.json`）與所有硬編 IP 失效。
症狀：MCP `not listening; disconnected` 或 curl 連不上 → 重新 `docker inspect` 取 IP 更新。

## 檔案權限

- HA 設定目錄：`/mnt/raid1/homeassistant`（bind mount → 容器 `/config`）
- 所有檔案 **root-owned**（`-rw-r--r-- root root`），本機 user（novis, uid 1000）**無法直接寫**（sudo 要密碼）
- 寫法：
  ```bash
  # 1. 先備份
  cp /mnt/raid1/homeassistant/configuration.yaml /tmp/ha_config.bak.yaml
  # 2. 寫暫存檔 → docker cp（本機在 docker group，免 sudo；容器內 root 寫 bind mount）
  docker cp /tmp/new.yaml home-assistant:/config/configuration.yaml
  # 3. 驗證（啟動 log 才有真話，見 api-quirks.md §8）
  ```
- 檔案經 docker cp 後 owner 會是 1000:1000 或 root——HA 都吃，不用管

## 主要檔案

| 檔 | 內容 |
|----|------|
| `/mnt/raid1/homeassistant/configuration.yaml` | 核心設定 + YAML 整合（`rest:` 在此） |
| `/mnt/raid1/homeassistant/automations.yaml` | UI 建立與手寫的 automations（id 為 `id` 欄位） |
| `/mnt/raid1/homeassistant/scripts.yaml` / `scenes.yaml` | scripts / scenes |
| `/mnt/raid1/homeassistant/custom_components/` | 自訂/HACS 整合（`tapo`、`hacs`、`yamaha_soundbar`） |
| `/mnt/raid1/homeassistant/home-assistant.log` | 主 log（**只有 WARNING+**，無 INFO——「沒看到 log」不代表沒執行） |

## log 讀法

```bash
# 啟動錯誤（最常用）
docker exec home-assistant sh -c "grep -a 'Invalid config\|Setup failed' /config/home-assistant.log | tail"
# 最近事件
docker exec home-assistant sh -c "tail -30 /config/home-assistant.log"
```
- `docker logs home-assistant` 與檔案基本同步，但檔案較可靠
- 重啟會截斷/輪轉 log——**重啟後再查**，重啟前的錯誤要找 `.log.1` 或直接看 docker logs 歷史

## http.ban（會自己 ban 自己）

HA 的 `http.ban` 元件對**未認證打 `/api/*`** 或 **token 錯**的請求記帳：
- 每個請求記一條 `WARNING [homeassistant.components.http.ban] Login attempt or request with invalid authentication from <ip> (curl/...)`
- 10 分鐘內 100 次 invalid auth 或 50 次 login failure → **該 IP 被 ban 10 分鐘**
- 本 instance 上 host（192.168.90.1）的 curl 與 HA 同網段，**ban 了自己 = 自己鎖自己**

守則：
1. 所有 `/api/*` 一律帶 `Authorization: Bearer <token>`
2. 等 HA 重啟完成時**輪詢 UI `GET /`**（200 = 好），不要輪詢 `/api/`
3. 看到 dashboard log 一堆 ban 警告 → 先想是不是自己的 script 在輪詢，查 `curl` UA 與來源 IP

## 重啟

```bash
docker restart home-assistant        # 約 15–30 秒
# 等 UI 起來（別用 /api/）：
for i in $(seq 1 24); do sleep 5
  [ "$(curl -s -o /dev/null -w '%{http_code}' -m 3 http://<ip>:8123/)" = "200" ] && break; done
```
AGENTS.md 的 `docker compose -f docker-compose-app.yml restart home-assistant` 也可以，結果一樣。
