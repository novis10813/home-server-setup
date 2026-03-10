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