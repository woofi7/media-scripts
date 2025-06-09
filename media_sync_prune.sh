#!/bin/bash

# Folder Comparison Script (Size-Based) - Parent Folder Deletion
# Compares video files between source and media folders using file sizes
# Shows matched files and extra files in torrents that aren't in media
# DELETES ENTIRE PARENT FOLDERS of unmatched files ONLY if NO files in folder are matched

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Required paths (no defaults)
TORRENTS_DIR=""
MEDIA_DIR=""

# Size tolerance in MB (default: 1MB to account for slight differences)
SIZE_TOLERANCE_MB=${SIZE_TOLERANCE_MB:-1}

# Show usage information if help requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo
    echo -e "${BLUE}Usage:${NC}"
    echo "  $0 --source-path PATH --media-path PATH [OPTIONS]"
    echo
    echo -e "${BLUE}Required Options:${NC}"
    echo "  --source-path PATH         Source directory path (required)"
    echo "  --media-path PATH          Media directory path (required)"
    echo
    echo -e "${BLUE}Optional Options:${NC}"
    echo "  --verbose, -v              Show detailed scanning and matching output"
    echo "  --delete                   Generate deletion script for unmatched folders"
    echo "  --tolerance SIZE           Size tolerance in MB (default: $SIZE_TOLERANCE_MB MB)"
    echo "  --help, -h                 Show this help message"
    echo
    echo -e "${BLUE}Examples:${NC}"
    echo "  $0 --source-path /data/downloads --media-path /media/library"
    echo "  $0 --source-path /torrents --media-path /media --verbose"
    echo "  $0 --source-path /downloads --media-path /library --tolerance 5"
    echo "  $0 --source-path /downloads --media-path /library --tolerance 2 --delete --verbose"
    exit 0
fi

# Parse command line arguments
VERBOSE=false
DELETE_FLAG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --delete)
            DELETE_FLAG=true
            shift
            ;;
        --source-path)
            TORRENTS_DIR="$2"
            shift 2
            ;;
        --media-path)
            MEDIA_DIR="$2"
            shift 2
            ;;
        --tolerance)
            SIZE_TOLERANCE_MB="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check required parameters
if [[ -z "$TORRENTS_DIR" ]]; then
    echo -e "${RED}Error: --source-path is required${NC}"
    echo "Use --help for usage information"
    exit 1
fi

if [[ -z "$MEDIA_DIR" ]]; then
    echo -e "${RED}Error: --media-path is required${NC}"
    echo "Use --help for usage information"
    exit 1
fi

# Convert MB to bytes for internal use
SIZE_TOLERANCE=$((SIZE_TOLERANCE_MB * 1048576))

echo -e "${BLUE}=== Movie Folder Size-Based Comparison Tool (Parent Folder Deletion) - FIXED ===${NC}"
echo -e "Comparing: ${TORRENTS_DIR} vs ${MEDIA_DIR}"
echo -e "Size tolerance: ${SIZE_TOLERANCE_MB}MB ($(numfmt --to=iec $SIZE_TOLERANCE))"
echo -e "${RED}WARNING: This version will delete ENTIRE PARENT FOLDERS of unmatched files!${NC}"
echo -e "${YELLOW}FIXED: Folders with ANY matched files will NOT be deleted${NC}"
echo

# Check if directories exist
if [[ ! -d "$TORRENTS_DIR" ]]; then
    echo -e "${RED}Error: $TORRENTS_DIR directory not found${NC}"
    exit 1
fi

if [[ ! -d "$MEDIA_DIR" ]]; then
    echo -e "${RED}Error: $MEDIA_DIR directory not found${NC}"
    exit 1
fi

# Function to get human-readable file size
get_human_size() {
    local size="$1"
    numfmt --to=iec "$size"
}

# Function to check if two file sizes are within tolerance
sizes_match() {
    local size1="$1"
    local size2="$2"
    local diff=$((size1 > size2 ? size1 - size2 : size2 - size1))
    [[ $diff -le $SIZE_TOLERANCE ]]
}

# Function to get parent folder of a file (relative to torrents directory)
get_parent_folder() {
    local filepath="$1"
    local relative_path="${filepath#$TORRENTS_DIR/}"
    local parent_dir=$(dirname "$relative_path")
    
    if [[ "$parent_dir" == "." ]]; then
        # File is directly in torrents directory - return empty to skip
        echo ""
    else
        # Get the top-level folder
        local top_folder=$(echo "$parent_dir" | cut -d'/' -f1)
        echo "$TORRENTS_DIR/$top_folder"
    fi
}

# Function to calculate directory size
get_dir_size() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        du -sb "$dir" 2>/dev/null | cut -d$'\t' -f1 || echo "0"
    else
        echo "0"
    fi
}

# Get video files from both directories with their sizes
echo -e "${YELLOW}Scanning for video files and calculating sizes...${NC}"

# Create temporary files to store file info
torrent_files_temp=$(mktemp)
media_files_temp=$(mktemp)

# Cleanup temp files on exit
trap 'rm -f "$torrent_files_temp" "$media_files_temp"' EXIT

# Find all video files in torrents directory with sizes (Linux format)
find "$TORRENTS_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.m4v" \) -exec stat -c "%s|%n" {} \; | sort -n > "$torrent_files_temp"

# Find all video files in media directory with sizes (Linux format)
find "$MEDIA_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.m4v" \) -exec stat -c "%s|%n" {} \; | sort -n > "$media_files_temp"

# Read files into arrays
declare -a torrent_files_info media_files_info
mapfile -t torrent_files_info < "$torrent_files_temp"
mapfile -t media_files_info < "$media_files_temp"

echo -e "Found ${#torrent_files_info[@]} video files in torrents"
echo -e "Found ${#media_files_info[@]} video files in media"
echo

# Create associative arrays for matching and tracking
declare -A media_sizes=()
declare -A matched_torrents=()
declare -A matched_folders=()
declare -a unmatched_torrents=()
declare -a unmatched_standalone_files=()
declare -A folders_to_delete=()

# Process media files and create size lookup
echo -e "${YELLOW}Processing media files...${NC}"
for media_info in "${media_files_info[@]}"; do
    if [[ -n "$media_info" ]]; then
        size=$(echo "$media_info" | cut -d'|' -f1)
        filepath=$(echo "$media_info" | cut -d'|' -f2-)
        media_sizes["$size"]="$filepath"
        if [[ "$VERBOSE" == true ]]; then
            echo "Media: $(get_human_size "$size") - $(basename "$filepath")"
        fi
    fi
done

echo -e "${YELLOW}Processing torrent files and finding matches...${NC}"

# Process torrent files and find matches
for torrent_info in "${torrent_files_info[@]}"; do
    if [[ -n "$torrent_info" ]]; then
        torrent_size=$(echo "$torrent_info" | cut -d'|' -f1)
        torrent_path=$(echo "$torrent_info" | cut -d'|' -f2-)
        parent_folder=$(get_parent_folder "$torrent_path")
        
        # Look for matching size in media files
        match_found=false
        for media_size in "${!media_sizes[@]}"; do
            if sizes_match "$torrent_size" "$media_size"; then
                matched_torrents["$torrent_path"]=1
                
                # Only mark folder as matched if file is in a folder (not standalone)
                if [[ -n "$parent_folder" ]]; then
                    matched_folders["$parent_folder"]=1
                fi
                
                if [[ "$VERBOSE" == true ]]; then
                    if [[ -z "$parent_folder" ]]; then
                        echo -e "${GREEN}MATCH (standalone):${NC} Size: $(get_human_size "$torrent_size")"
                    else
                        echo -e "${GREEN}MATCH:${NC} Size: $(get_human_size "$torrent_size")"
                    fi
                    echo -e "  Torrent: $(basename "$torrent_path")"
                    echo -e "  Media:   $(basename "${media_sizes[$media_size]}")"
                    echo -e "  Torrent Path: $torrent_path"
                    echo -e "  Media Path:   ${media_sizes[$media_size]}"
                    
                    # Show size difference if any
                    if [[ "$torrent_size" != "$media_size" ]]; then
                        diff=$((torrent_size > media_size ? torrent_size - media_size : media_size - torrent_size))
                        echo -e "  Size difference: $(get_human_size "$diff")"
                    fi
                    echo
                fi
                match_found=true
                break
            fi
        done
        
        if [[ "$match_found" == false ]]; then
            # Separate standalone files from folder files
            if [[ -z "$parent_folder" ]]; then
                unmatched_standalone_files+=("$torrent_path|$torrent_size")
                if [[ "$VERBOSE" == true ]]; then
                    echo -e "${YELLOW}UNMATCHED (standalone):${NC} File directly in source directory: $(basename "$torrent_path")"
                fi
            else
                unmatched_torrents+=("$torrent_path|$torrent_size")
            fi
        fi
    fi
done

# Determine which folders should be deleted (only those with NO matched files)
echo -e "${YELLOW}Determining folders for deletion...${NC}"
for unmatched_info in "${unmatched_torrents[@]}"; do
    unmatched_path=$(echo "$unmatched_info" | cut -d'|' -f1)
    parent_folder=$(get_parent_folder "$unmatched_path")
    
    # Only mark for deletion if this folder has NO matched files
    if [[ -z "${matched_folders[$parent_folder]:-}" ]]; then
        folders_to_delete["$parent_folder"]=1
        if [[ "$VERBOSE" == true ]]; then
            echo -e "  ${RED}Folder marked for deletion: $parent_folder${NC} (no matched files)"
        fi
    else
        if [[ "$VERBOSE" == true ]]; then
            echo -e "  ${GREEN}Folder preserved: $parent_folder${NC} (has matched files)"
        fi
    fi
done

# Display results
echo
echo -e "${BLUE}=== SUMMARY ===${NC}"
echo

# Count matches
matched_count=${#matched_torrents[@]}
echo -e "${GREEN}Matched files: $matched_count${NC}"

# Show extra/unmatched files
echo
echo -e "${RED}=== EXTRA TORRENT FILES (no size match in media) ===${NC}"
for unmatched_info in "${unmatched_torrents[@]}"; do
    unmatched_path=$(echo "$unmatched_info" | cut -d'|' -f1)
    unmatched_size=$(echo "$unmatched_info" | cut -d'|' -f2)
    parent_folder=$(get_parent_folder "$unmatched_path")
    
    echo -e "${YELLOW}Size: $(get_human_size "$unmatched_size")${NC}"
    echo "  File: $(basename "$unmatched_path")"
    echo "  Path: $unmatched_path"
    
    # Show deletion status for files in folders
    if [[ -n "${folders_to_delete[$parent_folder]:-}" ]]; then
        echo -e "  ${RED}Parent folder WILL BE DELETED: $parent_folder${NC}"
    else
        echo -e "  ${GREEN}Parent folder PRESERVED (has matched files): $parent_folder${NC}"
    fi
    echo
done

# Show standalone files separately
if [[ ${#unmatched_standalone_files[@]} -gt 0 ]]; then
    echo
    echo -e "${RED}=== STANDALONE FILES (no size match in media) ===${NC}"
    for standalone_info in "${unmatched_standalone_files[@]}"; do
        standalone_path=$(echo "$standalone_info" | cut -d'|' -f1)
        standalone_size=$(echo "$standalone_info" | cut -d'|' -f2)
        
        echo -e "${YELLOW}Size: $(get_human_size "$standalone_size")${NC}"
        echo "  File: $(basename "$standalone_path")"
        echo "  Path: $standalone_path"
        echo -e "  ${RED}Standalone file WILL BE DELETED${NC}"
        echo
    done
fi

echo
echo -e "${RED}=== FOLDERS TO BE DELETED ===${NC}"
total_folder_size=0

# First, filter out folders that don't exist and count actual folders
existing_folders_to_delete=()
for folder in "${!folders_to_delete[@]}"; do
    if [[ -d "$folder" ]]; then
        existing_folders_to_delete+=("$folder")
    fi
done

if [[ ${#existing_folders_to_delete[@]} -eq 0 ]]; then
    echo -e "${GREEN}No folders will be deleted! All folders contain at least one matched file.${NC}"
else
    delete_index=1
    for folder in "${existing_folders_to_delete[@]}"; do
        folder_size=$(get_dir_size "$folder")
        total_folder_size=$((total_folder_size + folder_size))
        echo -e "${RED}[$delete_index] Folder: $folder${NC}"
        echo "  Size: $(get_human_size "$folder_size")"
        echo "  Contents:"
        ls -la "$folder" 2>/dev/null | head -10 | sed 's/^/    /'
        
        # Show which files in this folder are unmatched
        echo "  Unmatched video files in this folder:"
        for unmatched_info in "${unmatched_torrents[@]}"; do
            unmatched_path=$(echo "$unmatched_info" | cut -d'|' -f1)
            unmatched_parent=$(get_parent_folder "$unmatched_path")
            if [[ "$unmatched_parent" == "$folder" ]]; then
                echo "    - $(basename "$unmatched_path")"
            fi
        done
        echo
        ((delete_index++))
    done
fi

# Show standalone files to be deleted
if [[ ${#unmatched_standalone_files[@]} -gt 0 ]]; then
    echo
    echo -e "${RED}=== STANDALONE FILES TO BE DELETED ===${NC}"
    total_standalone_size=0
    standalone_index=1
    for standalone_info in "${unmatched_standalone_files[@]}"; do
        standalone_path=$(echo "$standalone_info" | cut -d'|' -f1)
        standalone_size=$(echo "$standalone_info" | cut -d'|' -f2)
        total_standalone_size=$((total_standalone_size + standalone_size))
        echo -e "${RED}[$standalone_index] File: $(basename "$standalone_path")${NC}"
        echo "  Size: $(get_human_size "$standalone_size")"
        echo "  Path: $standalone_path"
        echo "  Reason: No size match found in media library"
        echo
        ((standalone_index++))
    done
fi

echo
echo -e "${BLUE}=== FINAL SUMMARY ===${NC}"
echo -e "Total torrent video files: ${#torrent_files_info[@]}"
echo -e "Total media video files: ${#media_files_info[@]}"
echo -e "${GREEN}Matched torrents: $matched_count${NC}"
echo -e "${RED}Extra torrent files in folders: ${#unmatched_torrents[@]}${NC}"
echo -e "${RED}Extra standalone files: ${#unmatched_standalone_files[@]}${NC}"
echo -e "${GREEN}Folders with matched files (preserved): ${#matched_folders[@]}${NC}"
echo -e "${RED}Folders to delete: ${#existing_folders_to_delete[@]}${NC}"
echo -e "${RED}Standalone files to delete: ${#unmatched_standalone_files[@]}${NC}"

total_files_to_delete=$((${#unmatched_torrents[@]} + ${#unmatched_standalone_files[@]}))

if [[ ${#existing_folders_to_delete[@]} -gt 0 || ${#unmatched_standalone_files[@]} -gt 0 ]]; then
    echo
    echo -e "${YELLOW}Potential space savings:${NC}"
    if [[ ${#existing_folders_to_delete[@]} -gt 0 ]]; then
        echo -e "  Folder deletions: $(get_human_size "$total_folder_size") (${#existing_folders_to_delete[@]} folders)"
    fi
    if [[ ${#unmatched_standalone_files[@]} -gt 0 ]]; then
        echo -e "  Standalone file deletions: $(get_human_size "$total_standalone_size") (${#unmatched_standalone_files[@]} files)"
    fi
    total_savings=$((total_folder_size + total_standalone_size))
    echo -e "  ${YELLOW}Total potential savings: $(get_human_size "$total_savings")${NC}"
    echo
    echo -e "${RED}WARNING: This will delete ENTIRE FOLDERS and standalone files!${NC}"
    echo -e "${YELLOW}Use the script with --delete flag to generate removal commands.${NC}"
else
    echo
    echo -e "${GREEN}Great! No folders or files need to be deleted.${NC}"
    echo -e "${GREEN}All torrent content matches your media library.${NC}"
fi

# Optional: Generate deletion script (only if there are folders to delete)
if [[ "$DELETE_FLAG" == true && (${#existing_folders_to_delete[@]} -gt 0 || ${#unmatched_standalone_files[@]} -gt 0) ]]; then
    echo
    echo -e "${YELLOW}Generating deletion commands...${NC}"
    removal_script="./generated/remove_torrent_content.sh"
    
    mkdir -p ./generated
    
    cat > "$removal_script" << 'EOF'
#!/bin/bash
# Auto-generated script to remove torrent content based on size comparison
# WARNING: This will delete ENTIRE FOLDERS and standalone files!
# Only folders with NO matched files and standalone files with no matches will be deleted
# Review this script carefully before running!

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}WARNING: This will permanently delete ENTIRE FOLDERS and standalone files!${NC}"
echo -e "${RED}This includes all files: videos, subtitles, NFOs, samples, etc.${NC}"
echo -e "${GREEN}Only folders with NO matched files and standalone files with no matches will be deleted.${NC}"
echo -e "${YELLOW}Are you absolutely sure you want to continue? (y/N)${NC}"
read -r confirmation
if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

echo -e "${RED}Type 'DELETE' to confirm deletion:${NC}"
read -r final_confirmation
if [[ "$final_confirmation" != "DELETE" ]]; then
    echo "Aborted."
    exit 0
fi

echo -e "${RED}Removing content...${NC}"
total_size=0
folder_count=0
file_count=0

# Function to get folder size
get_folder_size() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        du -sb "$dir" 2>/dev/null | cut -d$'\t' -f1 || echo "0"
    else
        echo "0"
    fi
}

# Function to get file size
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -c "%s" "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

EOF
    
    # Add folders to removal script
    if [[ ${#existing_folders_to_delete[@]} -gt 0 ]]; then
        cat >> "$removal_script" << 'EOF'
echo -e "${YELLOW}Removing folders...${NC}"
EOF
        for folder in "${!existing_folders_to_delete[@]}"; do
            cat >> "$removal_script" << EOF
if [[ -d "$folder" ]]; then
    folder_size=\$(get_folder_size "$folder")
    echo "Removing folder: \$(basename "$folder") (\$(numfmt --to=iec \$folder_size))"
    echo "  Full path: $folder"
    echo "  Reason: No matched files in this folder"
    rm -rf "$folder"
    total_size=\$((total_size + folder_size))
    folder_count=\$((folder_count + 1))
    echo "  ✓ Deleted"
else
    echo "Folder not found (already deleted?): $folder"
fi
echo

EOF
        done
    fi
    
    # Add standalone files to removal script
    if [[ ${#unmatched_standalone_files[@]} -gt 0 ]]; then
        cat >> "$removal_script" << 'EOF'
echo -e "${YELLOW}Removing standalone files...${NC}"
EOF
        for standalone_info in "${unmatched_standalone_files[@]}"; do
            standalone_path=$(echo "$standalone_info" | cut -d'|' -f1)
            cat >> "$removal_script" << EOF
if [[ -f "$standalone_path" ]]; then
    file_size=\$(get_file_size "$standalone_path")
    echo "Removing file: \$(basename "$standalone_path") (\$(numfmt --to=iec \$file_size))"
    echo "  Full path: $standalone_path"
    echo "  Reason: No size match found in media library"
    rm -f "$standalone_path"
    total_size=\$((total_size + file_size))
    file_count=\$((file_count + 1))
    echo "  ✓ Deleted"
else
    echo "File not found (already deleted?): $standalone_path"
fi
echo

EOF
        done
    fi
    
    cat >> "$removal_script" << 'EOF'

echo -e "${GREEN}Completed!${NC}"
if [[ $folder_count -gt 0 ]]; then
    echo "Removed $folder_count folders"
fi
if [[ $file_count -gt 0 ]]; then
    echo "Removed $file_count standalone files"
fi
echo "Total space freed: $(numfmt --to=iec $total_size)"
EOF
    
    chmod +x "$removal_script"
    echo -e "${GREEN}Created $removal_script${NC}"
    echo -e "${RED}CRITICAL WARNING: This will delete ENTIRE FOLDERS and standalone files!${NC}"
    echo -e "${RED}Make sure you have backups and review the script carefully!${NC}"
    echo -e "${YELLOW}The script requires double confirmation (y/N + typing 'DELETE') to proceed.${NC}"
elif [[ "$DELETE_FLAG" == true ]]; then
    echo
    echo -e "${GREEN}No deletion script needed - no folders or files to delete!${NC}"
fi