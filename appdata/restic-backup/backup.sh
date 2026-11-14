#!/bin/sh
# restic 備份 → Google Drive（加密、快照）
#   immich：照片原始檔 + Immich 每日資料庫備份   → rclone:gdrive:restic/immich
#   config：各服務設定與 .env / secrets          → rclone:gdrive:restic/config
# 用法：backup.sh [immich|config|all]（預設 all）。任一項失敗，整體以非 0 結束，但不會跳過另一項。
# 排程由 cron 容器在 Immich 02:00 資料庫備份之後觸發（見 appdata/cron/crontab）
set -u

MODE="${1:-all}"
log() { echo "[$(date -Iseconds)] $*"; }
is_sunday() { [ "$(date +%u)" = "7" ]; }

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

fail=0
case "$MODE" in
  immich) backup_immich || fail=1 ;;
  config) backup_config || fail=1 ;;
  all)    backup_immich || fail=1; backup_config || fail=1 ;;
  *) echo "unknown mode: $MODE" >&2; exit 2 ;;
esac
[ "$fail" = "0" ] && log "all done" || log "FAILED (see messages above)"
exit "$fail"
