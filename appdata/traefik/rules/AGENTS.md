# AGENTS.md - Traefik Rules (middlewares/chains) 規範

本文件用於規範本專案 `appdata/traefik/rules/` 下 **Traefik File Provider** 動態設定的撰寫方式，特別是 **middlewares** 與 **middleware chains** 的建立與維護。

> 注意：此目錄由 Traefik 以 `--providers.file.watch=true` 監聽；檔案存檔後通常會自動套用（不需重啟 Traefik）。

---

## 目錄與檔案命名

- **縮排**：一律 **2 spaces**，不要使用 tab。
- **檔名**：kebab-case。
- **Middleware 定義檔**：`middlewares-<topic>.yml`
  - 例：`middlewares-secure-headers.yml`、`middlewares-rate-limit.yml`
- **Chain 定義檔**：`chain-<name>.yml`
  - 例：`chain-oauth.yml`、`chain-no-auth.yml`、`chain-immich.yml`
- **TLS options**：集中於 `01-tls.yml`（供 `tls-opts@file` 引用）

---

## 命名慣例（物件名稱）

在 YAML 內的資源名稱請保持一致且可預期：

- **Middlewares**：`middlewares-<name>`
  - 例：`middlewares-secure-headers`、`middlewares-oauth`
- **Chains**：`chain-<name>`
  - 例：`chain-oauth`、`chain-basic-auth`

在 Docker labels 引用時，一律用 `@file`：

- `chain-oauth@file`
- `middlewares-secure-headers@file`

---

## 建議的 Chain 組合順序

為了讓所有服務行為一致、避免重複設定與漏掛安全策略，chain 的 middleware 組合順序建議如下：

1. **Rate limit**（先限流，減少後端負擔）
2. **Secure headers**（統一安全標頭策略）
3. **Auth**（依需求：OAuth / Basic Auth / 無認證）

對應到本專案慣例（示意）：

- `chain-oauth`：`middlewares-rate-limit` → `middlewares-secure-headers` → `middlewares-oauth`
- `chain-basic-auth`：`middlewares-rate-limit` → `middlewares-secure-headers` → `middlewares-basic-auth`
- `chain-no-auth`：`middlewares-rate-limit` → `middlewares-secure-headers`

若某服務需要客製（例如 Immich 使用內建認證），請建立獨立 chain（例如 `chain-immich`），但仍建議沿用「限流 → 安全標頭」的前段組合。

---

## Middleware 設計原則

- **可重用**：優先寫成通用 middlewares（例如 `secure-headers`、`rate-limit`），再由 chain 組合。
- **單一職責**：一個 middleware 檔案聚焦一類功能；避免把多種不相干設定混在一起。
- **避免重複**：不要在每個 router 都重複掛相同的一串 middlewares；應改用 chain。
- **變更最小化**：調整既有 middleware 時，確認會影響哪些 chain / 服務（避免意外擴散）。

---

## TLS 使用規範（避免 421 / 不一致）

- **TLS 在 Traefik entrypoint 統一處理**：
  - 由 `compose/infrastructure/traefik.yml` 的 `websecure-*` entrypoints 啟用 TLS，並指定：
    - `tls.options=tls-opts@file`
    - `tls.certresolver=dns-cloudflare`
    - `tls.domains[...]`
- **一般情況不在各服務 router labels 重複設定**：
  - 避免 `traefik.http.routers.<name>.tls=true`
  - 避免 `traefik.http.routers.<name>.tls.certresolver=...`

只有在「該服務必須使用不同憑證 / 不同 resolver / 不同 TLS options」時，才允許在該 router 另外指定 TLS 行為。

---

## 新增 middleware / chain 的流程（建議）

1. **確認要解的問題屬於 middleware 還是 router 層**
   - 可共用的策略（headers、auth、rate-limit、cors）→ middleware / chain
   - 單一服務的路由規則（Host/Path、entrypoints、service port）→ docker labels（compose）
2. **新增或更新 `middlewares-*.yml`**
   - 命名遵循 `middlewares-<topic>.yml`
   - 盡量保持通用、可重用
3. **將 middleware 組合進既有 chain，或新增 `chain-*.yml`**
4. **在對應服務的 labels 掛上 chain**
   - 優先用 `middlewares=chain-xxx@file`
5. **驗證**
   - Traefik 日誌確認動態設定 reload 成功（無 parse error）
   - Traefik Dashboard 檢查 router/middleware 綁定是否符合預期

---

## 禁止事項（安全與可維護性）

- **不要**把密碼、token、client secret 寫進 rules YAML（請用 `.env` / `secrets/`）。
- **不要**在 rules 內定義與服務耦合的敏感資訊（例如 OAuth client secret）。
- **不要**為了單一服務的小差異複製整套 middlewares；優先以「新增一個小 middleware」或「新增一個 chain」解決。

