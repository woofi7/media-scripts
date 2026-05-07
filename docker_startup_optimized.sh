#!/bin/bash

echo "==================================================================="
echo "Optimized Docker Startup Script"
echo "Started at: $(date)"
echo "==================================================================="

# Stop all containers
echo "Stopping all containers..."
docker stop $(docker ps -q) 2>/dev/null
sleep 3

start_time=$(date +%s)

# PHASE 1: Core Infrastructure (parallel) - these don't depend on each other
echo ""
echo "Phase 1: Starting core infrastructure..."
docker start redis memcached mariadb mosquitto &
wait
sleep 3

# PHASE 2: VPN and critical services (parallel)
echo "Phase 2: Starting VPN and core services..."
docker start qbittorrentvpn plex homeassistant seafile siyuan &
wait
sleep 5  # Give VPN time to establish

# PHASE 3: Download management (parallel) - depend on VPN
echo "Phase 3: Starting download stack..."
docker start prowlarr flood &
wait
sleep 3

# PHASE 4: Media management (parallel) - depend on prowlarr
echo "Phase 4: Starting media management..."
docker start sonarr sonarr-anime radarr bazarr overseerr &
wait

# PHASE 5: Support services (parallel)
echo "Phase 5: Starting support services..."
docker start tdarr-server tdarr-node-qsv notifiarr flaresolverr phpmyadmin duplicati portainer_edge_agent-update &
wait

# PHASE 6: Monitoring and tunnels (parallel)
echo "Phase 6: Starting monitoring..."
docker start ssh-tunnel-homepage ssh-tunnel-overseerr &
wait
sleep 2

# PHASE 7: Homepage and Watchtower LAST (these are the slowest)
echo "Phase 7: Starting homepage and watchtower..."
docker start homepage &
docker start watchtower &
wait

end_time=$(date +%s)
duration=$((end_time - start_time))

echo ""
echo "==================================================================="
echo "Startup complete!"
echo "Total time: $duration seconds ($(echo "scale=2; $duration/60" | bc) minutes)"
echo "Finished at: $(date)"
echo "==================================================================="

# Show status
echo ""
echo "Container Status:"
docker ps --format "table {{.Names}}\t{{.Status}}" | head -15
echo "... (showing first 15)"