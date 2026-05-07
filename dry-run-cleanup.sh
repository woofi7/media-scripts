#!/bin/bash
# DRY RUN - qBittorrent Non-Private Torrent Removal Script
# This script SIMULATES removing non-private torrents from qBittorrent client
# NO ACTUAL CHANGES ARE MADE

API_URL="http://10.0.1.2:8080/api/v2"

echo "========================================="
echo "DRY RUN MODE - NO TORRENTS WILL BE DELETED"
echo "========================================="
echo ""
echo "Checking for non-private torrents..."

# Get list of non-private torrents
NON_PRIVATE=$(curl -s "$API_URL/torrents/info?filter=all" | \
jq -r '.[] | select(.private == false) | "\(.name)|\(.hash)|\(.size)|\(.progress)"')

if [ -z "$NON_PRIVATE" ]; then
    echo "No non-private torrents found."
    exit 0
fi

TORRENT_COUNT=$(echo "$NON_PRIVATE" | wc -l)
echo "Found $TORRENT_COUNT non-private torrents that WOULD be removed:"
echo ""
echo "----------------------------------------"

COUNTER=1
echo "$NON_PRIVATE" | while IFS='|' read -r name hash size progress; do
    # Convert size to human readable
    SIZE_GB=$(echo "scale=2; $size / 1073741824" | bc)
    PROGRESS_PCT=$(echo "scale=1; $progress * 100" | bc)
    
    echo "[$COUNTER/$TORRENT_COUNT] WOULD REMOVE:"
    echo "  Name: $name"
    echo "  Hash: $hash"
    echo "  Size: ${SIZE_GB} GB"
    echo "  Progress: ${PROGRESS_PCT}%"
    echo "  Files: WOULD BE PRESERVED (deleteFiles=false)"
    echo ""
    
    COUNTER=$((COUNTER + 1))
done

echo "----------------------------------------"
echo ""
echo "DRY RUN SUMMARY:"
echo "  - $TORRENT_COUNT torrents WOULD be removed from qBittorrent"
echo "  - Files WOULD be preserved on disk"
echo "  - NO ACTUAL CHANGES WERE MADE"
echo ""
echo "To execute for real, use the original script without dry-run mode."
