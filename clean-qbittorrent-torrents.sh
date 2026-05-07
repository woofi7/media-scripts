#!/bin/bash

# qBittorrent Non-Private Torrent Removal Script
#
# For each completed, non-private torrent:
# - Must be in a completed/seeding state (not still downloading)
# - Must be imported by Sonarr/Radarr (hardlink to media dir confirmed via inode)
# - If hardlinked (link count > 1): Tdarr hasn't transcoded yet — remove from qBit, keep files
# - If link count = 1: hardlink broken by Tdarr — remove from qBit + delete files

API_URL="http://10.0.1.2:8080/api/v2"
MEDIA_DIR="/mnt/user/data/media"
DRY_RUN=false

COMPLETED_STATES="uploading stalledUP pausedUP completed queuedUP forcedUP"

if [[ "$1" == "--dry-run" || "$1" == "-n" ]]; then
    DRY_RUN=true
    echo "[DRY RUN] No changes will be made."
fi

# Translate container path /data/ to host path /mnt/user/data/
host_path() {
    echo "${1/#\/data\//\/mnt\/user\/data\/}"
}

is_completed_state() {
    local state="$1"
    for s in $COMPLETED_STATES; do
        [[ "$state" == "$s" ]] && return 0
    done
    return 1
}

# Returns 0 if any torrent file is hardlinked into the media dir
is_imported() {
    local hash="$1"
    local save_path="$2"

    local files
    files=$(curl -s "$API_URL/torrents/files?hash=$hash" | jq -r '.[].name' 2>/dev/null)
    [ -z "$files" ] && return 1

    while IFS= read -r f; do
        local full_path="$save_path/$f"
        [ ! -f "$full_path" ] && continue
        local inode
        inode=$(stat -c "%i" "$full_path" 2>/dev/null)
        [ -z "$inode" ] && continue
        find "$MEDIA_DIR" -inum "$inode" -maxdepth 6 2>/dev/null | grep -q . && return 0
    done <<< "$files"

    return 1
}

# Returns count of torrent files still hardlinked (not yet transcoded by Tdarr)
hardlinked_count() {
    local hash="$1"
    local save_path="$2"
    local count=0

    local files
    files=$(curl -s "$API_URL/torrents/files?hash=$hash" | jq -r '.[].name' 2>/dev/null)
    [ -z "$files" ] && echo 0 && return

    while IFS= read -r f; do
        local full_path="$save_path/$f"
        [ ! -f "$full_path" ] && continue
        local links
        links=$(stat -c "%h" "$full_path" 2>/dev/null)
        [ "${links:-1}" -gt 1 ] && count=$((count + 1))
    done <<< "$files"

    echo "$count"
}

echo "Checking for non-private torrents..."

NON_PRIVATE=$(curl -s "$API_URL/torrents/info?filter=all" | \
    jq -r '.[] | select(.private == false) | "\(.name)|\(.hash)|\(.save_path)|\(.state)"')

if [ -z "$NON_PRIVATE" ]; then
    echo "No non-private torrents found."
    exit 0
fi

echo "$NON_PRIVATE" | while IFS='|' read -r name hash save_path state; do
    save_path=$(host_path "$save_path")
    echo "Processing: $name (state: $state)"

    if ! is_completed_state "$state"; then
        echo "  [SKIP] Still downloading."
        continue
    fi

    if ! is_imported "$hash" "$save_path"; then
        echo "  [SKIP] Not yet imported by Sonarr/Radarr."
        continue
    fi

    hl=$(hardlinked_count "$hash" "$save_path")

    if [ "$hl" -gt 0 ]; then
        echo "  [REMOVE FROM QBIT] Hardlink exists, Tdarr hasn't transcoded yet — keeping files: $name"
        if [ "$DRY_RUN" = false ]; then
            curl -s -X POST -d "hashes=$hash" -d "deleteFiles=false" \
                "$API_URL/torrents/delete" > /dev/null 2>&1
        fi
    else
        echo "  [REMOVE + DELETE FILES] Tdarr transcoded, hardlink gone — removing from qBit and disk: $name"
        if [ "$DRY_RUN" = false ]; then
            curl -s -X POST -d "hashes=$hash" -d "deleteFiles=true" \
                "$API_URL/torrents/delete" > /dev/null 2>&1
        fi
    fi
done

echo "Done."
