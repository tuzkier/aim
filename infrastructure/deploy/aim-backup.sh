#!/usr/bin/env bash
set -euo pipefail
DIR=/opt/aim/backups
mkdir -p "$DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
docker exec aim-postgres-1 pg_dump -U aim -d aim | gzip > "$DIR/aim-$STAMP.sql.gz"
find "$DIR" -name 'aim-*.sql.gz' -mtime +7 -delete
# 用户在 AIM 里发的图片在数据卷里，不在数据库里，单独打包。
docker run --rm -v aim_attachments:/data:ro -v "$DIR":/backup alpine \
  tar -czf "/backup/aim-attachments-$STAMP.tar.gz" -C /data .
find "$DIR" -name 'aim-attachments-*.tar.gz' -mtime +7 -delete
echo "backup done: $DIR/aim-$STAMP.sql.gz $DIR/aim-attachments-$STAMP.tar.gz"
