#!/usr/bin/env bash
set -euo pipefail
DIR=/opt/aim/backups
mkdir -p "$DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
docker exec aim-postgres-1 pg_dump -U aim -d aim | gzip > "$DIR/aim-$STAMP.sql.gz"
find "$DIR" -name 'aim-*.sql.gz' -mtime +7 -delete
# 用户在 AIM 里发的图片在数据卷里，不在数据库里，单独打包。
# 直接打包主机上的卷目录：服务器连不上 Docker Hub，不能指望临时拉一个 alpine 来打包。
ATTACHMENTS="$(docker volume inspect -f '{{.Mountpoint}}' aim_attachments)"
tar -czf "$DIR/aim-attachments-$STAMP.tar.gz" -C "$ATTACHMENTS" .
find "$DIR" -name 'aim-attachments-*.tar.gz' -mtime +7 -delete
echo "backup done: $DIR/aim-$STAMP.sql.gz $DIR/aim-attachments-$STAMP.tar.gz"
