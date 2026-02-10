# Home Assistant

Home Assistant 以單一容器部署，經 Traefik 以內網 HTTPS 子網域提供服務。

## 存取

- **網址**：`https://ha.${DOMAINNAME_1}`（子網域可由 `.env` 的 `HOMEASSISTANT_SUBDOMAIN` 覆寫，預設 `ha`）
- **認證**：使用 Home Assistant 內建登入；Traefik 僅套用 `chain-no-auth@file`（限流 + 安全標頭）

## 反向代理（Traefik）必設

經 Traefik 存取時，Home Assistant 必須信任代理並使用轉發標頭，否則會回 **400 Bad Request**。

在 `${DATADIR}/homeassistant/configuration.yaml` 中加入（若已有 `http:` 區塊則合併）：

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 192.168.90.0/24   # t3_proxy 網段（Traefik 所在）
```

儲存後重啟容器使設定生效：`docker compose -f docker-compose-app.yml restart home-assistant`。

## 資料目錄

- 設定與運行時資料：`${DATADIR}/homeassistant`（對應容器內 `/config`）
- 此目錄不納入版控，備份時請一併處理

## 網路模式

### 預設：bridge

目前使用 **bridge** 網路（`t3_proxy`），與其他 App 一致，由 Traefik 轉發至容器埠 8123。

- **優點**：隔離較好、設定單純
- **限制**：mDNS / Zeroconf 裝置發現可能無法使用

### 進階：改用 host 網路

若需要裝置自動發現（mDNS）、藍牙或其它需與 host 網路直接通訊的整合，可改為 `network_mode: host`：

1. 在 `compose/apps/home-assistant.yml` 中：
   - 為 `home-assistant` 服務加上 `network_mode: host`
   - 移除該服務的 `networks` 區塊
   - 移除所有 Traefik labels（host 模式下容器不接 `t3_proxy`，無法由 Traefik 以 Docker provider 發現）

2. 若仍要經 Traefik 以子網域存取，需在 Traefik 的 **File Provider** 或靜態設定中，手動定義一組 Router + Service，Service 的位址指向 `http://host.docker.internal:8123`（或主機實際 IP），並綁定相同 Host 規則與 middleware。

3. 重啟服務：`docker compose -f docker-compose-app.yml up -d home-assistant`

改回 bridge 時還原上述變更即可。
