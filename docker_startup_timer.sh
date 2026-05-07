#!/bin/bash

# Docker Container Startup Timer Script
# This script starts each container individually and measures startup time

echo "==================================================================="
echo "Docker Container Startup Timer"
echo "Started at: $(date)"
echo "==================================================================="
echo ""

# Get list of all containers (stopped and running)
containers=$(docker ps -a --format "{{.Names}}" | sort)

# Create results file
results_file="/tmp/docker_startup_times_$(date +%Y%m%d_%H%M%S).txt"
echo "Container Startup Times - $(date)" > "$results_file"
echo "=================================================================" >> "$results_file"

# Stop all containers first
echo "Stopping all containers..."
docker stop $(docker ps -q) 2>/dev/null
sleep 5
echo "All containers stopped."
echo ""

# Array to store times
declare -A startup_times

# Start each container and measure time
for container in $containers; do
    echo "-------------------------------------------------------------------"
    echo "Starting: $container"
    echo -n "  Started at: $(date +%H:%M:%S) ... "
    
    # Record start time
    start_time=$(date +%s.%N)
    
    # Start the container
    docker start "$container" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        # Wait for container to be running
        timeout=30
        elapsed=0
        while [ $elapsed -lt $timeout ]; do
            status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
            if [ "$status" = "running" ]; then
                break
            fi
            sleep 0.5
            elapsed=$((elapsed + 1))
        done
        
        # Record end time
        end_time=$(date +%s.%N)
        
        # Calculate duration
        duration=$(echo "$end_time - $start_time" | bc)
        
        # Check if container has health check
        health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null)
        
        if [ "$health" != "" ] && [ "$health" != "<no value>" ]; then
            echo -n "Waiting for healthy status ... "
            # Wait up to 60 seconds for healthy status
            health_timeout=60
            health_elapsed=0
            while [ $health_elapsed -lt $health_timeout ]; do
                health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null)
                if [ "$health" = "healthy" ]; then
                    break
                fi
                sleep 1
                health_elapsed=$((health_elapsed + 1))
            done
            end_time=$(date +%s.%N)
            duration=$(echo "$end_time - $start_time" | bc)
        fi
        
        startup_times[$container]=$duration
        
        printf "Done! (%.2f seconds)\n" "$duration"
        printf "%-30s %.2f seconds\n" "$container" "$duration" >> "$results_file"
    else
        echo "FAILED to start"
        echo "$container - FAILED TO START" >> "$results_file"
    fi
    
    # Small delay between container starts
    sleep 2
done

echo ""
echo "==================================================================="
echo "Startup Complete!"
echo "==================================================================="
echo ""

# Sort and display results
echo "STARTUP TIME SUMMARY (sorted by time):"
echo "-------------------------------------------------------------------"

# Write summary to results file
echo "" >> "$results_file"
echo "SUMMARY (sorted by startup time):" >> "$results_file"
echo "=================================================================" >> "$results_file"

# Sort by startup time and display
for container in $(for c in "${!startup_times[@]}"; do
    echo "${startup_times[$c]} $c"
done | sort -rn | awk '{print $2}'); do
    time=${startup_times[$container]}
    printf "%-30s %.2f seconds\n" "$container" "$time"
    printf "%-30s %.2f seconds\n" "$container" "$time" >> "$results_file"
done

echo ""
echo "Results saved to: $results_file"
echo ""

# Calculate total time
total_start=$(docker ps -a --format "{{.Names}}" | head -1)
total_duration=0
for time in "${startup_times[@]}"; do
    total_duration=$(echo "$total_duration + $time" | bc)
done

printf "Total startup time: %.2f seconds (%.2f minutes)\n" "$total_duration" "$(echo "$total_duration / 60" | bc -l)"
echo ""
echo "Finished at: $(date)"