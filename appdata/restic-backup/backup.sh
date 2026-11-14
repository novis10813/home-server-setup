#!/bin/sh
# Immich 備份：照片原始檔 + Immich 每日資料庫備份 → restic（加密、快照）→ Google Drive
# 排程由 cron 容器在 Immich 02:00 資料庫備份之後觸發（見 appdata/cron/crontab）
set -eu

echo "[$(date -Iseconds)] backup start"

# 倉庫不存在或密碼錯誤時在此失敗，不會自動建立新倉庫
restic cat config >/dev/null

restic backup --host homeserver --tag immich --exclude-caches \
  /source/library/upload /source/library/backups /source/library/profile

# 保留策略：7 份每日、4 份每週、6 份每月
restic forget --host homeserver --tag immich \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 6

# 每週日清理已過期資料並抽樣驗證 2%
if [ "$(date +%u)" = "7" ]; then
  restic prune
  restic check --read-data-subset=2%
fi

echo "[$(date -Iseconds)] backup done"
