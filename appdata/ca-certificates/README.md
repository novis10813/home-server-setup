# 暫時性 CA 信任庫（CVE-2026-111943）

2026-10 eMudhra 的 emSign 中繼 CA 私鑰外洩。受影響的信任路徑有兩條：`emSign ECC Root CA - G3`（交叉簽署 `emSign Root TLS CA - G3`）與 Sectigo 的 `AAA Certificate Services`。上游映像尚未全部更新 ca-certificates，因此以這裡的乾淨信任庫掛載覆蓋容器內建的版本。

## 內容

- `certs/`：取自 `alpine:latest`（ca-certificates 20261020-r0），已不含上述兩個 root。整個目錄掛到容器的 `/etc/ssl/certs`，`ca-certificates.crt` 另以單檔掛到 Python certifi 等內建 bundle 的路徑。
- `java/cacerts`：QuestDB 內建 JDK 的 cacerts，已刪除上述兩個 root。
- `build.sh`：重建以上兩者。重建後要重建掛載它的容器。

Node.js 容器（jellyseerr、code-server）另設 `NODE_OPTIONS=--use-openssl-ca` 與 `SSL_CERT_FILE`，讓 Node 改用系統信任庫而非內建 root。Home Assistant 另設 `UV_NATIVE_TLS=true`，讓 uv 改用系統信任庫。

## 移除方式

Compose 中相關設定都標有 `CVE-2026-111943`：

```bash
grep -rn CVE-2026-111943 compose/
```

某個映像的上游版本修好後（`docker pull` 後映像內的信任庫不再信任上述 root），刪除該服務標記的 volumes / environment，再 `docker compose ... up -d <service>`。全部移除後可刪除本目錄。

測試站：<https://emudhra.we-have-a-problem.com/>。`dv-g3b-emudhra` 與 `dv-g3b-aaa-emudhra` 兩個子網域都應出現憑證錯誤。
