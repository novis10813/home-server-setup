#!/bin/sh
# restic 備份 → Google Drive（加密、快照）
#   immich：照片原始檔 + Immich 每日資料庫備份   → rclone:gdrive:restic/immich
#   config：各服務設定與 .env / secrets          → rclone:gdrive:restic/config
#   market-data：MinIO market-data（Parquet）   → rclone:gdrive:restic/market-data
#     先用 rclone 從 MinIO 增量複製到 /staging（只增不刪），再用 restic 打包上傳。
#     直接逐檔上傳 Google Drive 每秒不到 1 個檔案，15 萬個小檔要數天；restic 打包後只需數小時。
# 用法：backup.sh [immich|config|market-data|all]（預設 all）。任一項失敗，整體以非 0 結束，但不會跳過另一項。
# 排程由 cron 容器在 Immich 02:00 資料庫備份之後觸發（見 appdata/cron/crontab）
set -u

MODE="${1:-all}"
METRICS_DIR="/metrics"
log() { echo "[$(date -Iseconds)] $*"; }
is_sunday() { [ "$(date +%u)" = "7" ]; }

write_job_metrics() {
  job="$1"
  status="$2"
  duration="$3"
  now="$(date +%s)"
  [ -d "$METRICS_DIR" ] || return 0

  state_file="$METRICS_DIR/.state_${job}"
  prev_success=0
  if [ -f "$state_file" ]; then
    prev_success="$(awk -F= '$1=="last_success"{print $2}' "$state_file")"
    [ -n "$prev_success" ] || prev_success=0
  fi
  if [ "$status" = "1" ]; then
    last_success="$now"
  else
    last_success="$prev_success"
  fi

  cat > "${state_file}.tmp" <<EOF
status=${status}
last_run=${now}
last_success=${last_success}
duration=${duration}
EOF
  mv "${state_file}.tmp" "$state_file"

  prom_tmp="$METRICS_DIR/restic_backup.prom.$$"
  {
    echo "# HELP restic_backup_last_status Status of last restic backup run (1=success, 0=failure)."
    echo "# TYPE restic_backup_last_status gauge"
    for f in "$METRICS_DIR"/.state_*; do
      [ -f "$f" ] || continue
      j="${f##*/.state_}"
      v="$(awk -F= '$1=="status"{print $2}' "$f")"
      echo "restic_backup_last_status{job=\"$j\"} $v"
    done

    echo "# HELP restic_backup_last_run_timestamp_seconds Unix timestamp of last restic backup attempt."
    echo "# TYPE restic_backup_last_run_timestamp_seconds gauge"
    for f in "$METRICS_DIR"/.state_*; do
      [ -f "$f" ] || continue
      j="${f##*/.state_}"
      v="$(awk -F= '$1=="last_run"{print $2}' "$f")"
      echo "restic_backup_last_run_timestamp_seconds{job=\"$j\"} $v"
    done

    echo "# HELP restic_backup_last_success_timestamp_seconds Unix timestamp of last successful restic backup."
    echo "# TYPE restic_backup_last_success_timestamp_seconds gauge"
    for f in "$METRICS_DIR"/.state_*; do
      [ -f "$f" ] || continue
      j="${f##*/.state_}"
      v="$(awk -F= '$1=="last_success"{print $2}' "$f")"
      echo "restic_backup_last_success_timestamp_seconds{job=\"$j\"} $v"
    done

    echo "# HELP restic_backup_duration_seconds Duration of last restic backup run in seconds."
    echo "# TYPE restic_backup_duration_seconds gauge"
    for f in "$METRICS_DIR"/.state_*; do
      [ -f "$f" ] || continue
      j="${f##*/.state_}"
      v="$(awk -F= '$1=="duration"{print $2}' "$f")"
      echo "restic_backup_duration_seconds{job=\"$j\"} $v"
    done
  } > "$prom_tmp"
  chmod 644 "$prom_tmp"
  mv "$prom_tmp" "$METRICS_DIR/restic_backup.prom"
}

run_job() {
  job="$1"
  fn="$2"
  start_ts="$(date +%s)"
  if "$fn"; then
    end_ts="$(date +%s)"
    write_job_metrics "$job" 1 "$((end_ts - start_ts))"
    return 0
  else
    end_ts="$(date +%s)"
    write_job_metrics "$job" 0 "$((end_ts - start_ts))"
    return 1
  fi
}

backup_immich() {
  export RESTIC_REPOSITORY=rclone:gdrive:restic/immich
  log "immich: start"
  # 倉庫不存在或密碼錯誤時在此失敗，不會自動建立新倉庫
  restic cat config >/dev/null || return 1
  restic backup --host homeserver --tag immich --exclude-caches \
    /source/library/upload /source/library/backups /source/library/profile || return 1
  # 保留策略：7 份每日、4 份每週、6 份每月
  restic forget --host homeserver --tag immich \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || return 1
  if is_sunday; then
    restic prune || return 1
    restic check --read-data-subset=2% || return 1
  fi
  log "immich: done"
}

backup_config() {
  export RESTIC_REPOSITORY=rclone:gdrive:restic/config
  log "config: start"
  restic cat config >/dev/null || return 1
  # secrets 內排除 restic 倉庫密碼與 rclone 設定：它們不能存放在用它們加密/存取的倉庫裡
  # Home Assistant 排除歷史資料庫（運行中的 SQLite，且非設定）、日誌與快取
  # Pi-hole 只取設定與黑名單（不含 400 MB 的查詢紀錄）
  restic backup --host homeserver --tag config --exclude-caches \
    --exclude /source/docker/secrets/restic_password \
    --exclude /source/docker/secrets/rclone \
    --exclude '/source/data/homeassistant/home-assistant_v2.db*' \
    --exclude '/source/data/homeassistant/home-assistant.log*' \
    --exclude /source/data/homeassistant/.cache \
    --exclude /source/data/homeassistant/deps \
    --exclude /source/data/homeassistant/tts \
    --exclude /source/data/homeassistant/.ha_run.lock \
    --exclude '/source/data/*/logs' \
    --exclude '/source/data/*/logs.db*' \
    --exclude '/source/data/*/MediaCover' \
    /source/docker/.env \
    /source/docker/secrets \
    /source/docker/appdata/traefik/acme/acme.json \
    /source/docker/appdata/couchdb/local.ini \
    /source/data/homeassistant \
    /source/data/pihole/pihole.toml \
    /source/data/pihole/adlists.list \
    /source/data/pihole/gravity.db \
    /source/data/grafana \
    /source/data/sonarr \
    /source/data/radarr \
    /source/data/prowlarr \
    /source/data/jellyseerr || return 1
  restic forget --host homeserver --tag config \
    --keep-daily 14 --keep-weekly 8 --keep-monthly 12 || return 1
  if is_sunday; then
    restic prune || return 1
    restic check --read-data-subset=2% || return 1
  fi
  log "config: done"
}

backup_market_data() {
  export RESTIC_REPOSITORY=rclone:gdrive:restic/market-data
  log "market-data: start"
  restic cat config >/dev/null || return 1
  RCLONE_CONFIG_MINIO_ACCESS_KEY_ID="$MARKET_DATA_BACKUP_ACCESS_KEY" \
  RCLONE_CONFIG_MINIO_SECRET_ACCESS_KEY="$MARKET_DATA_BACKUP_SECRET_KEY" \
    rclone copy minio:market-data /staging --transfers 8 --checkers 16 \
      --stats 5m --stats-one-line -v || return 1
  restic backup --host homeserver --tag market-data /staging || return 1
  restic forget --host homeserver --tag market-data \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || return 1
  if is_sunday; then
    restic prune || return 1
    restic check --read-data-subset=2% || return 1
  fi
  log "market-data: done"
}

fail=0
case "$MODE" in
  immich) run_job immich backup_immich || fail=1 ;;
  config) run_job config backup_config || fail=1 ;;
  market-data) run_job market-data backup_market_data || fail=1 ;;
  all)
    run_job immich backup_immich || fail=1
    run_job config backup_config || fail=1
    run_job market-data backup_market_data || fail=1
    ;;
  *) echo "unknown mode: $MODE" >&2; exit 2 ;;
esac
[ "$fail" = "0" ] && log "all done" || log "FAILED (see messages above)"
exit "$fail"
