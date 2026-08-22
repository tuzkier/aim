#!/usr/bin/env bash
set -euo pipefail
DIR=/opt/aim/backups
mkdir -p "$DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
docker exec aim-postgres-1 pg_dump -U aim -d aim | gzip > "$DIR/aim-$STAMP.sql.gz"
find "$DIR" -name 'aim-*.sql.gz' -mtime +7 -delete
echo "backup done: $DIR/aim-$STAMP.sql.gz"
