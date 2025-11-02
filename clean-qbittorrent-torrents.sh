#!/bin/bash

# Copied to UserScripts to be executed weekly

# qBittorrent Non-Private Torrent Removal Script
# This script removes non-private torrents from qBittorrent client
# Files on disk are preserved (deleteFiles=false)

API_URL="http://10.0.1.2:8080/api/v2"

echo "Checking for non-private torrents..."

# Get list of non-private torrents
NON_PRIVATE=$(curl -s "$API_URL/torrents/info?filter=all" | \
jq -r '.[] | select(.private == false) | "\(.name)|\(.hash)"')

if [ -z "$NON_PRIVATE" ]; then
    echo "No non-private torrents found."
    exit 0
fi

echo "Found $(echo "$NON_PRIVATE" | wc -l) non-private torrents to remove:"

echo "$NON_PRIVATE" | while IFS='|' read -r name hash; do
    echo "Removing: $name"
    curl -s -X POST \
        -d "hashes=$hash" \
        -d "deleteFiles=false" \
        "$API_URL/torrents/delete" > /dev/null 2>&1
done

echo "Done! $(echo "$NON_PRIVATE" | wc -l) torrents removed from client, files preserved on disk."
