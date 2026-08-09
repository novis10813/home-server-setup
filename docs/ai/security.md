# AI stack 安全模型與升級路線

Hermes 能執行工具與 `execute_code`，因此 AI stack 的威脅模型不是「一般 Web app 加一個 API」。任何能影響 agent prompt、tool call、skills、provider response 或 workspace input 的人，都可能誘導它執行高影響操作。這份文件定義目前 Docker Socket Proxy 方案的真實邊界，以及何時必須升級到獨立 rootless daemon 或 VM。

## 目前邊界：Socket Proxy 是 route-level gate

LinuxServer `socket-proxy` 對 Docker API endpoint 做路由級別的允許/拒絕。環境變數例如 `POST=1`、`CONTAINERS=1`、`EXEC=0` 控制某些 API route 是否被轉發；它不是 policy engine，也不會理解「這個 container 是否安全」、「這個 image 是否可信」或「這次 exec 是否符合 workspace policy」。

目前 infrastructure proxy 的設定只為既有用途服務，不能直接當成 Hermes sandbox 的安全授權。整合 AI project 時，應使用專用 proxy、專用 daemon 或更嚴格的 network policy，並逐項驗證 proxy 的實際允許 route。

## `:ro` socket 不等於 Docker API read-only

Compose 中常見的：

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
```

只限制容器內對 **Unix socket inode 的 mount 操作**；Docker API 透過 socket 收到的 HTTP methods 仍由 daemon 權限決定。它不會把 `POST /containers/create`、`POST /containers/{id}/start` 或 `POST /exec/{id}/start` 變成 read-only。甚至對 socket mount 標註 `:ro`，也不能消除 Docker daemon 對 client 的高權限信任。

同理，proxy 容器的 filesystem `read_only: true` 與 host socket volume 的 `:ro` 是不同層次的控制；兩者都不能單獨宣稱「Docker API 只讀」。

## 為何 POST + CONTAINERS + EXEC 仍是高權限

只要 proxy 允許建構與啟動容器的必要 routes，且 Docker API client 能設定 container 欄位，攻擊者可能建立高權限容器。例如：

- `POST` 是建立或改變 Docker state 的方法閘門，不是只讀查詢。
- `CONTAINERS` 允許列舉、建立、啟動、停止或移除相關 container routes（實際範圍取決於 proxy 版本與環境變數）。
- `EXEC` 允許在既有 container 內建立/啟動 process；它不是安全的「只執行一個 harmless command」保證。
- 若 API route 能傳遞 `Privileged`、host bind、host network、額外 capabilities、device 或 `/var/run/docker.sock` mount 等設定，建立出的 container 可能取得等同 root 的 host 影響力。
- 即使 `Privileged` 被上游 policy 阻擋，任意 host bind、敏感 `/proc` 或可寫的 Docker socket 仍可能造成資料外洩、持久化或 daemon takeover。

因此，看到 `POST=1`、`CONTAINERS=1` 或 `EXEC=1` 時，必須把 client 視為擁有高影響 Docker 控制權。不要把 route allowlist 寫成「agent sandbox」或「不可信 code 隔離」。

## 目前方案不是不可信 code 的強 sandbox

以下控制有助於減少誤操作，但不提供對 hostile code 的強隔離：

- Hermes 不直接掛 host Docker socket。
- `no-new-privileges:true`、`cap_drop`、非 privileged container。
- 沒有 host port publish，服務只經由預期的 Docker network 或 Traefik internal entrypoint。
- 專用 workspace 與 host-visible output 目錄。
- Socket Proxy 的 route-level allow/deny。
- 容器 resource limits、logs 與 network membership 檢查。

這些措施無法證明 kernel、Docker daemon、共享 network、DNS、image supply chain、side channel 或被允許的 API route 都安全。特別是，若 Hermes 可控制一個仍連著 host daemon 的 Docker API，該 daemon 本身就是高價值 trust boundary。未經審查的 plugin、skill、prompt injection、provider output 或 repository input 都不可視為可信；不要把這套設定用來執行惡意樣本、任意第三方 repository 或含 production credentials 的 code。

## Docker backend 最小化檢查清單

整合前，安全審查者應取得 compose config 與 runtime inspect 結果（刪除 secrets 後）並確認：

1. Hermes 的 `DOCKER_HOST` 指向專用、可審計的 endpoint，而非未說明的 host socket。
2. proxy 只暴露明確需要的 routes；不以 `POST` 或 `CONTAINERS` 的存在宣稱 sandbox 完成。
3. Docker API client 無法設定 `Privileged=true`、host network、任意 bind、devices、額外 capabilities 或 daemon socket；若無法證明，就按高權限處理並禁止不可信輸入。
4. sandbox container 的 `Privileged=false`、network membership、binds、output path 與 resource limits 都透過 `docker inspect` 驗證。
5. workspace 不含 production `.env`、Docker credentials、SSH keys、provider credentials、API keys 或其他 secrets；以 placeholder 表示文件範例，例如 `<API_SERVER_KEY>`。
6. SearXNG 只以 `http://searxng:8080/search?...&format=json` 走內部 network 測試，不為 agent 需要而公開 host port。
7. image 使用固定且經驗證的 tag/digest，更新有 rollback 路徑；不要把 `latest` 當成供應鏈驗證。
8. output 目錄是明確 allowlist 路徑；host 端檢查檔案內容與實際 owner/permission，不把任意 bind mount 當成 output API。

## 獨立 rootless daemon：第一級升級

若必須讓 Hermes 執行較不可信的 code，先把 Docker API 從 production daemon 移走：

1. 為 AI stack 建立獨立的 rootless Docker daemon（不同 socket、不同 data-root、不同 systemd service/user）。
2. AI daemon 不加入 production containers、Traefik、host network 或 production volumes；只建立短命 sandbox network。
3. Hermes 只可連到該 rootless daemon 的 endpoint，且 proxy 與 daemon 都以獨立 Unix user 運行。禁止把 production `/var/run/docker.sock` 同時暴露給 agent。
4. 以 policy wrapper 或固定 runner 產生容器設定，拒絕 privileged、devices、host network、任意 host bind、Docker socket、host PID/IPC 及未審查 capability。
5. 每次執行使用一次性 workspace、有限 resource、egress allowlist、時間上限與清理；結果經過驗證後才複製到 host-visible output。
6. 仍須把 rootless daemon 視為可影響該 AI VM/user 的控制面，不要因此宣稱可執行任意 hostile code。

Rootless 降低 daemon/container 對 host root 的直接影響，但不會自動修復 image 漏洞、kernel escape、網路資料洩漏、供應鏈攻擊或 credentials 外洩。它是隔離層，不是完整 sandbox policy。

## VM / microVM：較強的隔離升級

對真正不可信的 repository、惡意測試、含 exploit 的樣本或必須容忍 agent prompt injection 的工作，使用獨立 VM 或 microVM，比共用 production host daemon 更合適：

- AI workload 在專用 VM 的 rootless daemon 內運作，VM 不掛 production socket、credentials、Traefik cert、host filesystem 或 production network。
- 以唯讀基底 image、短命 snapshot、每次任務重建、明確 egress proxy 與最小輸出交換區隔離任務。
- host 只接收經過 schema/size/type 驗證的 artifacts；不要把 VM output 直接 bind 到 production data tree。
- 對 VM、kernel、container runtime、base images、agent dependencies 與 proxy policy 建立 patch、audit log、incident response 和 rollback 流程。

若需求是「讓 agent 任意執行 code 且仍保護 production host」，目前 App Compose + stock Socket Proxy 不符合需求；應在上線前完成 rootless daemon 或 VM/microVM 方案及其攻擊面測試。

## 事件與撤銷

一旦發現錯誤 route、未知 container、非預期 bind、unexpected privileged flag、credential 出現在 workspace，或 agent 觸及 production endpoint：

1. 立即停止 Hermes 與 AI sandbox project；不要先 `prune` 或刪除證據。
2. 從 network 移除受影響的 sandbox，撤銷並旋轉可能暴露的 key；文件與命令只使用 `<API_SERVER_KEY>` 等 placeholder。
3. 保存不含 secret 的 container inspect、daemon/proxy logs、image digest、network membership 與時間線。
4. 檢查 host、Docker daemon、Traefik、production volumes 與 credentials 是否受影響。
5. 只有完成 review、修正 proxy/daemon policy 並驗證 rollback 後，才恢復服務。

任何 `docker compose down -v`、volume prune、system prune 或刪除 runtime data 的操作都不是一般復原步驟，必須另有明確的資料銷毀批准。
