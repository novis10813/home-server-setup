# AI stack 遷移與維運 Runbook

本 runbook 描述把 Hermes 與 SearXNG 從既有 App Compose project 遷移到獨立 AI Compose project 的安全流程。本文只記錄可重複執行的操作；不會停止、重建或刪除目前運行中的服務。

> **目前狀態**：本分支尚未有 `docker-compose-ai.yml`。以下 AI project 命令是整合該檔案後才可執行的 recipe；不要在檔案不存在時以猜測的 Compose 檔案取代它。整合後，先執行本文所有 `config --quiet` 檢查，再進行遷移。

## 不可違反的原則

- `hermes` 與 `searxng` 使用固定 `container_name`，因此一次只能由一個 Compose project 管理。
- 舊 App Compose 還包含服務定義時，**先用舊 project 執行 `stop`**；不要先刪除 include、修改名稱或直接讓兩個 project 同時 `up`。
- 遷移不需要 `down -v`、`docker volume prune`、`docker system prune` 或任何 prune。這些命令可能刪除無關資料。
- `stop` 不會刪除容器或 `${DATADIR}/hermes`、SearXNG 設定；清理容器時只使用針對服務的 `rm -f`，且不加 `-v`。
- `t3_proxy` 必須是兩個服務共同加入的既有 external network；不要以同名的新 bridge network 取代它。

## 0. 變更前檢查

在 repository 根目錄執行。這些命令不會啟動服務，也不會讀取或輸出 secrets：

```bash
docker compose -f docker-compose-infrastructure.yml config --quiet
docker compose -f docker-compose-app.yml config --quiet
# 整合後、且檔案已存在時才執行：
docker compose -f docker-compose-ai.yml config --quiet

docker network inspect t3_proxy >/dev/null
docker compose -f docker-compose-app.yml ps hermes searxng
docker inspect hermes --format '{{.Name}} {{.Config.Labels}}' 2>/dev/null || true
docker inspect searxng --format '{{.Name}} {{.Config.Labels}}' 2>/dev/null || true
```

`config --quiet` 失敗時先修正 Compose 或環境設定，不要進行遷移。不要把 `.env`、provider credentials、API key 或 command output 中的 secret 貼到 issue、PR 或文件。

## 1. 固定 container name 的安全遷移

以下順序假設 AI Compose 已經加入 `hermes`、`searxng`，且保留相同的固定 container name、資料掛載與 `t3_proxy` 網路。合併後 App Compose 已不再包含這兩個 service，因此先從既有容器 labels 驗證舊 project，再以 `-p` 明確指定它；不要用 `docker stop` 猜測 ownership：

```bash
# A. 驗證兩個既有容器都屬於預期的舊 project。
old_project="$(docker inspect hermes --format '{{index .Config.Labels "com.docker.compose.project"}}')"
test -n "${old_project}"
test "$(docker inspect searxng --format '{{index .Config.Labels "com.docker.compose.project"}}')" = "${old_project}"

# B. 使用 AI service 定義，但覆寫 project name 以鎖定舊容器；先停止，不要 down。
docker compose -p "${old_project}" -f docker-compose-ai.yml stop hermes searxng
docker inspect hermes searxng --format '{{.Name}} {{.State.Status}}'

# C. 兩個容器都為 Exited 後，只移除容器物件；不要加 -v。
docker compose -p "${old_project}" -f docker-compose-ai.yml rm -f hermes searxng

# D. 由頂層 name: ai 的新 project 建立服務。
docker compose -f docker-compose-ai.yml up -d hermes searxng
```

若 labels 不一致、project name 為空或容器狀態不是預期值，立即停止遷移。若 `up` 報告固定名稱仍被使用，先重新檢查 ownership 與狀態；不要用全域 `docker rm`、`prune` 或刪除資料目錄。

遷移後確認 project ownership 與持久化路徑：

```bash
docker compose -f docker-compose-ai.yml ps hermes searxng
docker inspect hermes --format '{{json .Mounts}}'
docker inspect searxng --format '{{json .Mounts}}'
docker inspect hermes --format '{{json .NetworkSettings.Networks}}'
docker inspect searxng --format '{{json .NetworkSettings.Networks}}'
```

應看到兩個容器都加入 `t3_proxy`，Hermes 的 `/opt/data` 仍指向 `${DATADIR}/hermes`，SearXNG 的設定仍指向 `${DOCKERDIR}/appdata/searxng`。不要以 `docker inspect` 輸出取代 secret redaction 後的紀錄。

## 2. Rollback

若 AI project `up`、smoke test 或 network 檢查失敗，保留資料並按反向順序回復。先停止 AI project，再移除 AI project 建立的容器；接著讓舊 App Compose 重新建立服務：

```bash
docker compose -f docker-compose-ai.yml stop hermes searxng
docker compose -f docker-compose-ai.yml rm -f hermes searxng
docker compose -f docker-compose-app.yml up -d hermes searxng
docker compose -f docker-compose-app.yml ps hermes searxng
```

Rollback 不使用 `down -v` 或 prune，也不刪除 `${DATADIR}/hermes`、SearXNG `appdata` 或任何 Docker volume。若 rollback 仍失敗，保留容器與 logs 供調查，記錄 `docker compose ... config --quiet`、`ps`、network membership 與 image digest；不要反覆 `up` 造成未驗證的重建。

## 3. 日常維運命令

針對 AI project 使用完整檔案路徑，避免 Compose project 名稱或目前目錄造成誤操作：

```bash
# 語法與合併設定檢查（只在檔案存在時）
docker compose -f docker-compose-ai.yml config --quiet

# 狀態、設定、logs
docker compose -f docker-compose-ai.yml ps
docker compose -f docker-compose-ai.yml config
docker compose -f docker-compose-ai.yml logs --tail=200 hermes searxng

# 更新：先拉取，再只重建 AI services
docker compose -f docker-compose-ai.yml pull hermes searxng
docker compose -f docker-compose-ai.yml up -d hermes searxng
```

`config` 可能展開環境設定，因此不要把完整輸出上傳；若輸出含 credential，立即停止分享並旋轉該 credential。更新前應備份 `${DATADIR}/hermes/` 與 SearXNG `appdata`，並固定已驗證的 image tag，而不是無審查地依賴 `latest`。

## 4. 整合後完整 runtime E2E recipe

以下步驟是遷移完成後由維運者在受控時段執行的驗證清單。這裡只給命令語法；本 work unit 不會在 worktree 連線到 live host 執行它們。

### 4.1 Compose、停止舊 App、啟動 AI

```bash
docker compose -f docker-compose-infrastructure.yml config --quiet
docker compose -f docker-compose-app.yml config --quiet
docker compose -f docker-compose-ai.yml config --quiet

# Persist the sandbox data-plane network; the gateway resolved config overrides
# a same-named terminal environment variable in the current Hermes release.
docker exec hermes hermes config set \
  terminal.docker_extra_args '["--network=ai_services"]'

# If proxy.enabled is true, configure/start iron-proxy before execute_code.
docker exec hermes hermes egress status
# First setup only: docker exec hermes hermes egress setup --no-restart
docker exec hermes hermes egress start

# Follow section 1 to stop/remove the verified old project, then:
docker compose -f docker-compose-ai.yml up -d hermes searxng
```

### 4.2 Network membership 與容器安全屬性

```bash
docker network inspect t3_proxy
docker inspect hermes --format 'networks={{json .NetworkSettings.Networks}} privileged={{.HostConfig.Privileged}} binds={{json .HostConfig.Binds}}'
docker inspect searxng --format 'networks={{json .NetworkSettings.Networks}} privileged={{.HostConfig.Privileged}} binds={{json .HostConfig.Binds}}'
```

檢查結果必須確認：Hermes 和 SearXNG 都在 `t3_proxy`；`Privileged` 為 `false`；沒有未審查的 host bind；Hermes workspace/output bind 只落在預期的專用路徑。若 AI Compose 使用 sandbox network，另外檢查 sandbox container 的 network、`Privileged=false`、bind 清單與 output mount，不要只看主服務的 network。

### 4.3 SearXNG internal HTTP

Hermes 到 SearXNG 必須走 Docker DNS 與 internal HTTP，不走 public Traefik hostname：

```bash
docker exec hermes sh -lc \
  'curl --fail-with-body --silent --show-error \
   "http://searxng:8080/search?q=docker&format=json" >/tmp/searxng.json \
   && test -s /tmp/searxng.json'
```

若 image 沒有 `curl`，在同一個 `t3_proxy` network 的一次性診斷容器中執行等價的 HTTP request；不要為了測試而 publish SearXNG port 到 host。`searxng:8080` 是容器內部位址，Traefik 的 `https://search.<DOMAINNAME_1>` 是另一條入口。

### 4.4 Hermes Docker backend 與 execute_code smoke test

AI Compose 的 Hermes backend 必須明確設定預期的 `DOCKER_HOST`（例如指向專用 socket proxy；不要猜測或直接掛 host socket）。在 Hermes 容器內檢查 Docker client 能看到 daemon 版本：

```bash
docker exec hermes sh -lc \
  'test -n "$DOCKER_HOST" && printf "DOCKER_HOST=%s\\n" "$DOCKER_HOST" && docker version'
```

接著用 Hermes CLI 的 `-z` 強制走 `execute_code`，並只寫入專用的 host-visible output 目錄：

```bash
docker exec hermes sh -lc \
  'mkdir -p /opt/data/smoke-output && \
   hermes -z "import pathlib; p=pathlib.Path(\"/opt/data/smoke-output/execute_code.txt\"); p.write_text(\"execute_code-ok\\n\"); print(p)"'

test "$(docker exec hermes sh -lc 'cat /opt/data/smoke-output/execute_code.txt')" = 'execute_code-ok'
test -f "${DATADIR}/hermes/smoke-output/execute_code.txt"
grep -Fx 'execute_code-ok' "${DATADIR}/hermes/smoke-output/execute_code.txt"
```

`-z` 的 smoke test 必須在整合環境使用實際安裝版本的 Hermes CLI；若該版本要求不同的 command quoting，保留 `-z` 與 `execute_code` 的強制路徑，依該版本 CLI help 調整引號。驗證的是結果檔案在 host 可見的預期路徑，不是任意 host path 寫入能力。

同時記錄 sandbox 的可觀測屬性（不貼出 secret）：

```bash
docker ps --format '{{.Names}}' | grep -E 'hermes|sandbox'
docker inspect <sandbox-container> --format 'privileged={{.HostConfig.Privileged}} network={{json .NetworkSettings.Networks}} binds={{json .HostConfig.Binds}}'
```

### 4.5 Traefik 入口

在能解析 internal entrypoint 的管理端執行，使用 placeholder，不要把真實 key 寫進 shell history、文件或 CI log：

```bash
curl --fail-with-body --silent --show-error \
  -H 'Authorization: Bearer <API_SERVER_KEY>' \
  "https://hermes-api.<DOMAINNAME_1>/v1/models"

curl --fail-with-body --silent --show-error \
  "https://search.<DOMAINNAME_1>/search?q=docker&format=json"
```

API response 只需確認 HTTP 成功與 schema，不要把 response 中可能包含的 provider metadata、token 或 query history 原樣貼出。Dashboard 入口另受 Traefik OAuth 與 Hermes authentication 保護。

## 5. 事件處理與證據保存

故障時保存下列不含 secrets 的資料：`config --quiet` 結果、`ps`、最近一段 logs、network membership、容器 image digest、`Privileged` 與 bind 檢查結果。不要保存完整 `.env`、Hermes runtime `.env`、API key、provider credential、session 或 prompt。完成變更後刪除 smoke output，或依備份政策保留並標記為測試資料：

```bash
rm -f "${DATADIR}/hermes/smoke-output/execute_code.txt"
```
