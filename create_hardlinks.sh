#!/bin/bash

# Hardlink creation script
# Creates hardlinks from torrents/transcodes to media/transcodes
# Usage: ./create_hardlinks.sh [--dry-run] [--verbose]

SOURCE_DIR="/mnt/user/data/torrents/transcodes"
DEST_DIR="/mnt/user/data/media/transcodes"

# Default options
DRY_RUN=true
VERBOSE=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --execute)
            DRY_RUN=false
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--execute] [--verbose]"
            echo "  --execute    Actually create hardlinks (default is dry-run)"
            echo "  --verbose    Show detailed output"
            echo "  --help       Show this help message"
            echo ""
            echo "By default, this script runs in dry-run mode to show what would be done."
            echo "Use --execute to actually create the hardlinks."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to print messages
print_message() {
    local message="$1"
    local color="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ -n "$color" ]]; then
        echo -e "${color}[$timestamp] $message${NC}"
    else
        echo "[$timestamp] $message"
    fi
}

# Function to check if file is a video
is_video_file() {
    local file="$1"
    local extension="${file##*.}"
    extension=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
    
    case "$extension" in
        mp4|mkv|avi|mov|wmv|flv|webm|m4v|3gp|mpg|mpeg|ts|m2ts|vob|ogv|rm|rmvb|asf|divx|xvid)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to create hardlink with error handling
create_hardlink() {
    local source="$1"
    local dest="$2"
    
    # Check if it's a video file
    if ! is_video_file "$source"; then
        [[ "$VERBOSE" == true ]] && print_message "Skipping non-video file: $source" "$GRAY"
        return 0
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}[DRY RUN] Would create hardlink: $source -> $dest${NC}"
        return 0
    fi
    
    # Create destination directory if it doesn't exist
    local dest_parent=$(dirname "$dest")
    if [[ ! -d "$dest_parent" ]]; then
        mkdir -p "$dest_parent"
        if [[ $? -eq 0 ]]; then
            [[ "$VERBOSE" == true ]] && print_message "Created directory: $dest_parent" "$BLUE"
        else
            print_message "ERROR: Failed to create directory: $dest_parent" "$RED"
            return 1
        fi
    fi
    
    # Check if source and destination are already hardlinked
    if [[ -f "$source" && -f "$dest" ]]; then
        local source_inode=$(stat -c %i "$source" 2>/dev/null)
        local dest_inode=$(stat -c %i "$dest" 2>/dev/null)
        if [[ "$source_inode" == "$dest_inode" && "$source_inode" != "" ]]; then
            [[ "$VERBOSE" == true ]] && print_message "Already hardlinked: $dest" "$YELLOW"
            return 0
        fi
    fi
    
    # Check if destination exists but is not a hardlink
    if [[ -e "$dest" ]]; then
        print_message "WARNING: Destination exists but is not a hardlink: $dest" "$YELLOW"
        return 1
    fi
    
    # Create the hardlink
    if ln "$source" "$dest" 2>/dev/null; then
        print_message "Created hardlink: $source -> $dest" "$GREEN"
        return 0
    else
        print_message "ERROR: Failed to create hardlink: $source -> $dest" "$RED"
        return 1
    fi
}

# Function to process files and directories recursively
process_directory() {
    local current_source="$1"
    local current_dest="$2"
    
    [[ "$VERBOSE" == true ]] && print_message "Processing directory: $current_source" "$BLUE"
    
    # Process all items in the current directory
    while IFS= read -r -d '' item; do
        # Get relative path from source directory
        local rel_path="${item#$SOURCE_DIR/}"
        local dest_path="$DEST_DIR/$rel_path"
        
        if [[ -f "$item" ]]; then
            # It's a file - create hardlink
            create_hardlink "$item" "$dest_path"
        elif [[ -d "$item" ]]; then
            # It's a directory - create directory structure
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "${CYAN}[DRY RUN] Would create directory: $dest_path${NC}"
            else
                if [[ ! -d "$dest_path" ]]; then
                    mkdir -p "$dest_path"
                    if [[ $? -eq 0 ]]; then
                        [[ "$VERBOSE" == true ]] && print_message "Created directory: $dest_path" "$BLUE"
                    else
                        print_message "ERROR: Failed to create directory: $dest_path" "$RED"
                    fi
                fi
            fi
        fi
    done < <(find "$current_source" -mindepth 1 -print0)
}

# Main execution
main() {
    if [[ "$DRY_RUN" == true ]]; then
        print_message "Starting hardlink creation script in DRY-RUN mode" "$YELLOW"
        print_message "No changes will be made. Use --execute to actually create hardlinks." "$YELLOW"
    else
        print_message "Starting hardlink creation script in EXECUTE mode" "$CYAN"
    fi
    
    # Check if source directory exists
    if [[ ! -d "$SOURCE_DIR" ]]; then
        print_message "ERROR: Source directory does not exist: $SOURCE_DIR" "$RED"
        exit 1
    fi
    
    # Create destination directory if it doesn't exist
    if [[ ! -d "$DEST_DIR" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "${CYAN}[DRY RUN] Would create destination directory: $DEST_DIR${NC}"
        else
            mkdir -p "$DEST_DIR"
            if [[ $? -eq 0 ]]; then
                print_message "Created destination directory: $DEST_DIR" "$BLUE"
            else
                print_message "ERROR: Failed to create destination directory: $DEST_DIR" "$RED"
                exit 1
            fi
        fi
    fi
    
    # Process all files and directories
    local file_count=0
    local success_count=0
    local error_count=0
    local already_linked_count=0
    
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            if is_video_file "$file"; then
                ((file_count++))
                local rel_path="${file#$SOURCE_DIR/}"
                local dest_path="$DEST_DIR/$rel_path"
                
                # Check if already hardlinked before attempting to create
                if [[ -f "$dest_path" ]]; then
                    local source_inode=$(stat -c %i "$file" 2>/dev/null)
                    local dest_inode=$(stat -c %i "$dest_path" 2>/dev/null)
                    if [[ "$source_inode" == "$dest_inode" && "$source_inode" != "" ]]; then
                        ((already_linked_count++))
                        [[ "$VERBOSE" == true ]] && print_message "Already hardlinked: $dest_path" "$YELLOW"
                        continue
                    fi
                fi
                
                if create_hardlink "$file" "$dest_path"; then
                    ((success_count++))
                else
                    ((error_count++))
                fi
            fi
        fi
    done < <(find "$SOURCE_DIR" -type f -print0)
    
    # Summary
    echo ""
    if [[ "$DRY_RUN" == true ]]; then
        print_message "Dry-run completed - no changes were made" "$YELLOW"
        print_message "Use --execute flag to actually create the hardlinks" "$YELLOW"
    else
        print_message "Hardlink creation completed" "$CYAN"
    fi
    print_message "Video files processed: $file_count" "$BLUE"
    print_message "Already hardlinked: $already_linked_count" "$YELLOW"
    if [[ "$DRY_RUN" == true ]]; then
        print_message "Would create hardlinks: $success_count" "$CYAN"
    else
        print_message "New hardlinks created: $success_count" "$GREEN"
    fi
    if [[ "$error_count" -gt 0 ]]; then
        print_message "Errors: $error_count" "$RED"
    else
        print_message "Errors: $error_count" "$GREEN"
    fi
    
    if [[ "$error_count" -gt 0 ]]; then
        exit 1
    fi
}

# Run main function
main "$@"