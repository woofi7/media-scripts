#!/bin/bash

# Unraid Space Usage Diagnostic Script

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  UNRAID SPACE USAGE ANALYSIS  ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
}

print_section() {
    echo -e "${CYAN}--- $1 ---${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Helper function to convert sizes to TB
to_tb() {
    echo "$1" | awk '{
        if (match($0, /([0-9.]+)([KMGT])/)) {
            val = substr($0, RSTART, RLENGTH-1)
            unit = substr($0, RSTART+RLENGTH-1, 1)
            if (unit == "K") val = val/1024/1024/1024
            else if (unit == "M") val = val/1024/1024
            else if (unit == "G") val = val/1024
            else if (unit == "T") val = val
            printf "%.2f TB\n", val
        }
    }'
}

print_header

# System Overview
print_section "SYSTEM OVERVIEW"
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo "Unraid Version: $(cat /etc/unraid-version 2>/dev/null || echo 'Unknown')"
echo

# Array Status
print_section "ARRAY STATUS"
if [[ -f /proc/mdstat ]]; then
    echo "Array status:"
    cat /proc/mdstat | grep -E "md[0-9]|bitmap"
    echo
else
    print_warning "Cannot read array status"
fi

# Physical Disk Analysis (Hard Link Aware)
print_section "PHYSICAL DISK USAGE (HARD LINK CORRECTED)"

total_used_gb=0
total_size_gb=0
total_actual_used_gb=0

echo "Individual disk usage:"
for disk in /mnt/disk*; do
    if [[ -d "$disk" && "$disk" != "/mnt/disks" ]]; then
        disk_name=$(basename "$disk")
        if df "$disk" >/dev/null 2>&1; then
            disk_info=$(df -h "$disk" | tail -1)
            size=$(echo "$disk_info" | awk '{print $2}')
            used=$(echo "$disk_info" | awk '{print $3}')
            avail=$(echo "$disk_info" | awk '{print $4}')
            use_pct=$(echo "$disk_info" | awk '{print $5}')
            
            echo "  $disk_name: $used used / $size total ($use_pct)"
            
            # Calculate actual space used accounting for hard links
            echo "    Analyzing hard links on $disk_name..."
            
            # Get unique inodes and their sizes (this gives us actual space)
            actual_bytes=$(find "$disk" -type f -exec stat -c "%i %s" {} \; 2>/dev/null | sort -u -k1,1 | awk '{sum+=$2} END {print sum}')
            actual_gb=$(echo "scale=2; $actual_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
            
            echo "    Actual space (hard link corrected): ${actual_gb} GB"
            
            # Convert sizes to GB for totaling - handle both TB and GB
            used_num=$(echo "$used" | sed 's/[KMGT]//')
            used_unit=$(echo "$used" | sed 's/[0-9.]*//g')
            if [[ "$used_unit" == "T" ]]; then
                used_gb=$(echo "scale=2; $used_num * 1024" | bc -l)
            elif [[ "$used_unit" == "G" ]]; then
                used_gb=$used_num
            elif [[ "$used_unit" == "M" ]]; then
                used_gb=$(echo "scale=2; $used_num / 1024" | bc -l)
            else
                used_gb=0
            fi
            
            size_num=$(echo "$size" | sed 's/[KMGT]//')
            size_unit=$(echo "$size" | sed 's/[0-9.]*//g')
            if [[ "$size_unit" == "T" ]]; then
                size_gb=$(echo "scale=2; $size_num * 1024" | bc -l)
            elif [[ "$size_unit" == "G" ]]; then
                size_gb=$size_num
            elif [[ "$size_unit" == "M" ]]; then
                size_gb=$(echo "scale=2; $size_num / 1024" | bc -l)
            else
                size_gb=0
            fi
            
            total_used_gb=$(echo "scale=2; $total_used_gb + $used_gb" | bc -l 2>/dev/null || echo "$total_used_gb")
            total_size_gb=$(echo "scale=2; $total_size_gb + $size_gb" | bc -l 2>/dev/null || echo "$total_size_gb")
            total_actual_used_gb=$(echo "scale=2; $total_actual_used_gb + $actual_gb" | bc -l 2>/dev/null || echo "$total_actual_used_gb")
        fi
    fi
done

echo
echo "Physical disks total:"
echo "  Reported used: $(echo "scale=2; $total_used_gb/1024" | bc -l 2>/dev/null || echo "Calculation error") TB"
echo "  Actual used (hard link corrected): $(echo "scale=2; $total_actual_used_gb/1024" | bc -l 2>/dev/null || echo "Calculation error") TB"
echo "  Total capacity: $(echo "scale=2; $total_size_gb/1024" | bc -l 2>/dev/null || echo "Calculation error") TB"

# Calculate potential overcount due to hard links
if command -v bc >/dev/null 2>&1 && [[ $(echo "$total_used_gb > 0" | bc -l) -eq 1 ]]; then
    overcount_gb=$(echo "scale=2; $total_used_gb - $total_actual_used_gb" | bc -l 2>/dev/null || echo "0")
    overcount_tb=$(echo "scale=2; $overcount_gb/1024" | bc -l 2>/dev/null || echo "0")
    echo "  Filesystem reported vs actual difference: ${overcount_tb} TB"
fi
echo

# Cache Drive Analysis
print_section "CACHE DRIVE USAGE"
if [[ -d /mnt/cache ]]; then
    echo "Cache drive usage:"
    df -h /mnt/cache
    echo
    
    echo "Cache contents:"
    du -sh /mnt/cache/* 2>/dev/null | sort -hr | head -10
else
    echo "No cache drive found"
fi
echo

# User Share Analysis (Hard Link Aware)
print_section "USER SHARE ANALYSIS (HARD LINK CORRECTED)"
echo "Analyzing user shares with hard link awareness..."

if [[ -d /mnt/user ]]; then
    echo "User share apparent usage (may include hard link overcounting):"
    du -sh /mnt/user/* 2>/dev/null | sort -hr | head -15
    echo
    
    total_user_share=$(du -sh /mnt/user 2>/dev/null | cut -f1)
    echo "Total apparent usage by user shares: $total_user_share"
    
    # Calculate actual usage accounting for hard links in user shares
    echo
    echo "Calculating actual user share usage (accounting for hard links)..."
    
    for share in /mnt/user/*/; do
        if [[ -d "$share" ]]; then
            share_name=$(basename "$share")
            echo "  Analyzing $share_name..."
            
            # Get apparent size
            apparent_size=$(du -sh "$share" 2>/dev/null | cut -f1)
            
            # Get actual size by counting unique inodes
            actual_bytes=$(find "$share" -type f -exec stat -c "%i %s" {} \; 2>/dev/null | sort -u -k1,1 | awk '{sum+=$2} END {print sum}')
            
            if [[ -n "$actual_bytes" && "$actual_bytes" != "0" ]]; then
                actual_size=$(echo "scale=1; $actual_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo 0)
                echo "    Apparent: $apparent_size, Actual: ${actual_size}G"
            else
                echo "    Apparent: $apparent_size, Actual: (calculation error)"
            fi
        fi
    done
else
    print_warning "User share not available"
fi
echo

# Parity Drive Check
print_section "PARITY DRIVE ANALYSIS"
echo "Checking for parity drives (these don't count toward usable space):"

parity_count=0
if [[ -f /boot/config/disk.cfg ]]; then
    while IFS= read -r line; do
        if [[ "$line" =~ diskP[0-9]*= ]]; then
            parity_count=$((parity_count + 1))
            echo "  Found: $line"
        fi
    done < /boot/config/disk.cfg
    
    echo "Total parity drives: $parity_count"
else
    print_warning "Cannot read disk configuration"
fi
echo

# Hard Link Analysis
print_section "HARD LINK ANALYSIS"
echo "Analyzing hard links to identify actual vs apparent space usage..."

# Find files with multiple hard links
hard_linked_files=$(find /mnt/disk* -type f -links +1 2>/dev/null | wc -l)
single_linked_files=$(find /mnt/disk* -type f -links 1 2>/dev/null | wc -l)
total_files=$((hard_linked_files + single_linked_files))

echo "File link analysis:"
echo "  Files with multiple hard links: $hard_linked_files"
echo "  Files with single links: $single_linked_files"
echo "  Total files found: $total_files"

if [[ $hard_linked_files -gt 0 ]]; then
    echo
    echo "Hard link space analysis (this may take a while)..."
    
    # Calculate actual space used by hard linked files
    # We only count each unique inode once
    temp_inodes="/tmp/inodes_$"
    temp_sizes="/tmp/sizes_$"
    
    # Get unique inodes and their sizes for hard linked files
    find /mnt/disk* -type f -links +1 -exec stat -c "%i %s" {} \; 2>/dev/null | sort -u > "$temp_inodes"
    
    if [[ -s "$temp_inodes" ]]; then
        total_hardlink_bytes=$(awk '{sum+=$2} END {print sum}' "$temp_inodes")
        total_hardlink_gb=$(echo "scale=2; $total_hardlink_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
        
        echo "  Actual space used by hard linked files: ${total_hardlink_gb} GB"
        
        # Show apparent vs actual size for hard linked files
        apparent_hardlink_bytes=$(find /mnt/disk* -type f -links +1 -exec stat -c "%s" {} \; 2>/dev/null | awk '{sum+=$1} END {print sum}')
        apparent_hardlink_gb=$(echo "scale=2; $apparent_hardlink_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
        
        echo "  Apparent space if counted multiple times: ${apparent_hardlink_gb} GB"
        
        savings_gb=$(echo "scale=2; $apparent_hardlink_gb - $total_hardlink_gb" | bc -l 2>/dev/null || echo "0")
        echo "  Space saved by hard linking: ${savings_gb} GB"
    fi
    
    rm -f "$temp_inodes" "$temp_sizes"
fi

echo

# Look for Hard Link Patterns
print_section "HARD LINK PATTERNS"
echo "Analyzing hard link distribution across disks..."

# Check if hard links span multiple disks (which shouldn't happen)
cross_disk_links=0
temp_hardlinks="/tmp/hardlinks_$"

# Find files with 2+ links and check their locations
find /mnt/disk* -type f -links +1 -exec stat -c "%i %n" {} \; 2>/dev/null | sort > "$temp_hardlinks"

if [[ -s "$temp_hardlinks" ]]; then
    echo "Checking for cross-disk hard links (these shouldn't exist)..."
    
    current_inode=""
    current_files=""
    while read inode filepath; do
        if [[ "$inode" == "$current_inode" ]]; then
            current_files="$current_files|$filepath"
        else
            if [[ -n "$current_inode" && -n "$current_files" ]]; then
                # Check if files are on different disks
                disk_count=$(echo "$current_files" | tr '|' '\n' | sed 's|/mnt/\([^/]*\)/.*|\1|' | sort -u | wc -l)
                if [[ $disk_count -gt 1 ]]; then
                    cross_disk_links=$((cross_disk_links + 1))
                    echo "  ❌ Cross-disk hard link detected (inode $current_inode):"
                    echo "$current_files" | tr '|' '\n' | sed 's/^/    /'
                fi
            fi
            current_inode="$inode"
            current_files="$filepath"
        fi
    done < "$temp_hardlinks"
    
    # Handle the last group
    if [[ -n "$current_inode" && -n "$current_files" ]]; then
        disk_count=$(echo "$current_files" | tr '|' '\n' | sed 's|/mnt/\([^/]*\)/.*|\1|' | sort -u | wc -l)
        if [[ $disk_count -gt 1 ]]; then
            cross_disk_links=$((cross_disk_links + 1))
            echo "  ❌ Cross-disk hard link detected (inode $current_inode):"
            echo "$current_files" | tr '|' '\n' | sed 's/^/    /'
        fi
    fi
    
    if [[ $cross_disk_links -eq 0 ]]; then
        echo "  ✅ No cross-disk hard links found (this is good)"
    else
        print_warning "Found $cross_disk_links cross-disk hard link groups (this may cause issues)"
    fi
fi

rm -f "$temp_hardlinks"
echo

# Filesystem Type Analysis
print_section "FILESYSTEM ANALYSIS"
echo "Filesystem types and features:"
for disk in /mnt/disk* /mnt/cache; do
    if [[ -d "$disk" ]]; then
        disk_name=$(basename "$disk")
        fs_type=$(mount | grep "$disk" | awk '{print $5}' | head -1)
        if [[ -n "$fs_type" ]]; then
            echo "  $disk_name: $fs_type"
            
            # Check for BTRFS snapshots
            if [[ "$fs_type" == "btrfs" ]]; then
                snapshot_count=$(btrfs subvolume list "$disk" 2>/dev/null | wc -l)
                if [[ $snapshot_count -gt 0 ]]; then
                    print_warning "$disk has $snapshot_count BTRFS subvolumes/snapshots"
                fi
            fi
        fi
    fi
done
echo

# Hidden Files and System Data
print_section "HIDDEN FILES AND SYSTEM DATA"
echo "Checking for hidden files and system data..."

for disk in /mnt/disk*; do
    if [[ -d "$disk" ]]; then
        disk_name=$(basename "$disk")
        
        # Check for hidden directories
        hidden_size=$(find "$disk"/.[^.]* -maxdepth 0 -type d -exec du -sh {} \; 2>/dev/null | awk '{sum+=$1} END {print sum}')
        if [[ -n "$hidden_size" && "$hidden_size" != "0" ]]; then
            echo "  $disk_name hidden directories: $hidden_size"
        fi
        
        # Check for system files
        system_files=$(find "$disk" -name "System*" -o -name "lost+found" -o -name "*.unraid*" 2>/dev/null | wc -l)
        if [[ $system_files -gt 0 ]]; then
            echo "  $disk_name system files: $system_files items"
        fi
    fi
done
echo

# Docker and VM Analysis
print_section "DOCKER AND VM ANALYSIS"
if [[ -d /var/lib/docker ]]; then
    docker_size=$(du -sh /var/lib/docker 2>/dev/null | cut -f1)
    echo "Docker usage: $docker_size"
fi

if [[ -d /mnt/user/domains ]]; then
    vm_size=$(du -sh /mnt/user/domains 2>/dev/null | cut -f1)
    echo "VM storage usage: $vm_size"
fi

if [[ -d /mnt/user/isos ]]; then
    iso_size=$(du -sh /mnt/user/isos 2>/dev/null | cut -f1)
    echo "ISO storage usage: $iso_size"
fi
echo

# Summary and Recommendations
print_section "SUMMARY AND RECOMMENDATIONS"

echo "Space Usage Summary (Hard Link Corrected):"
echo "  Physical disks report: $(echo "scale=1; $total_used_gb/1024" | bc -l 2>/dev/null || echo "Unknown") TB used"
echo "  Actual usage (hard link corrected): $(echo "scale=1; $total_actual_used_gb/1024" | bc -l 2>/dev/null || echo "Unknown") TB"
echo "  Total array capacity: $(echo "scale=1; $total_size_gb/1024" | bc -l 2>/dev/null || echo "Unknown") TB"
echo "  User shares report: $total_user_share"

# Calculate hard link savings more accurately
if command -v bc >/dev/null 2>&1 && [[ -n "$total_hardlink_gb" ]] && [[ -n "$apparent_hardlink_gb" ]]; then
    savings_tb=$(echo "scale=1; $savings_gb/1024" | bc -l 2>/dev/null || echo "Unknown")
    echo "  Hard link space savings: ${savings_tb} TB"
elif [[ $hard_linked_files -gt 0 ]]; then
    echo "  Hard link space savings: Significant (calculated above)"
else
    echo "  Hard link space savings: None detected"
fi
echo
