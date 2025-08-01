#!/bin/bash

# Direct Seafile Import Script
# Run this script to import files from folders to Seafile libraries

echo "Importing files to Seafile libraries..."

# Check if Seafile container is running
if ! docker ps --format "table {{.Names}}" | grep -q "^seafile$"; then
    echo "ERROR: Seafile container is not running"
    exit 1
fi

# Process each folder under /mnt/user/data/seafile/
for folder in /mnt/user/data/seafile/*/; do
    # Skip if no folders exist
    [ ! -d "$folder" ] && continue
    
    # Get folder name (library name)
    library_name=$(basename "$folder")
    
    # Skip folders already processed
    if [[ "$library_name" == *"_processed" ]]; then
        echo "Skipping $library_name (already processed)"
        continue
    fi
    
    # Check if folder has files or symlinks
    if [ -z "$(find "$folder" -type f -o -type l 2>/dev/null)" ]; then
        echo "Skipping $library_name (no files)"
        continue
    fi
    
    echo "Importing $library_name..."
    
    # Run import command and capture output
    import_output=$(docker exec seafile /opt/seafile/seafile-server-latest/seaf-import.sh \
        -p "/shared/seafile/data-share/$library_name" \
        -n "$library_name" \
        -u "n.signo@hotmail.com" 2>&1)
    
    # Check if import failed by looking for error messages
    if echo "$import_output" | grep -q "Failed to\|import failed\|Error"; then
        echo "✗ Failed to import $library_name"
        echo "Error details:"
        echo "$import_output"
        echo ""
        echo "Import stopped due to error."
        exit 1
    else
        echo "✓ $library_name imported successfully"
        
        # Rename folder to mark as processed
        mv "$folder" "${folder%/}_processed"
        echo "✓ Folder renamed to ${library_name}_processed"
    fi
    
    echo ""
done

echo "Import completed!"
