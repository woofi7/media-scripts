#!/bin/bash

DUMP_DIR="/mnt/user/appdata/database/dumps"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="$DUMP_DIR/$DATE"
KEEP_DAYS=7

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting database dump"

# Pull credentials from running containers
MYSQL_ROOT_PASSWORD=$(docker exec mariadb printenv MYSQL_ROOT_PASSWORD 2>/dev/null)
POSTGRES_USER=$(docker exec postgres printenv POSTGRES_USER 2>/dev/null)
POSTGRES_PASSWORD=$(docker exec postgres printenv POSTGRES_PASSWORD 2>/dev/null)

# MariaDB
if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
    echo "Dumping MariaDB..."
    docker exec mariadb mysqldump \
        -u root -p"$MYSQL_ROOT_PASSWORD" \
        --all-databases \
        --single-transaction \
        --routines \
        --triggers \
    | gzip > "$BACKUP_DIR/mariadb_all.sql.gz"
    PIPE_STATUS=("${PIPESTATUS[@]}")
    [ "${PIPE_STATUS[0]}" -eq 0 ] && [ "${PIPE_STATUS[1]}" -eq 0 ] && echo "MariaDB: OK" || echo "MariaDB: FAILED (dump=${PIPE_STATUS[0]} gzip=${PIPE_STATUS[1]})"
else
    echo "MariaDB: SKIPPED (container not running)"
fi

# PostgreSQL
if [ -n "$POSTGRES_USER" ]; then
    echo "Dumping PostgreSQL..."
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres \
        pg_dumpall -U "$POSTGRES_USER" \
    | gzip > "$BACKUP_DIR/postgres_all.sql.gz"
    PIPE_STATUS=("${PIPESTATUS[@]}")
    [ "${PIPE_STATUS[0]}" -eq 0 ] && [ "${PIPE_STATUS[1]}" -eq 0 ] && echo "PostgreSQL: OK" || echo "PostgreSQL: FAILED (dump=${PIPE_STATUS[0]} gzip=${PIPE_STATUS[1]})"
else
    echo "PostgreSQL: SKIPPED (container not running)"
fi

# Redis — flush to disk then copy RDB (AOF copied if it exists)
echo "Dumping Redis..."
docker exec redis redis-cli BGSAVE
sleep 3
docker cp redis:/data/dump.rdb "$BACKUP_DIR/redis_dump.rdb" 2>/dev/null
RDB_OK=$?
docker cp redis:/data/appendonly.aof "$BACKUP_DIR/redis_appendonly.aof" 2>/dev/null
[ "$RDB_OK" -eq 0 ] && echo "Redis: OK" || echo "Redis: FAILED"

# Cleanup old dumps
find "$DUMP_DIR" -maxdepth 1 -mindepth 1 -type d -mtime +$KEEP_DAYS -exec rm -rf {} +

echo "[$(date)] Dump complete: $BACKUP_DIR"
