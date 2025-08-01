#!/bin/bash

# Unraid Appdata Permissions Reset Script
# This script resets permissions for the appdata folder
# Run this script as root on your Unraid server

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to show usage
show_usage() {
    echo "Usage: $0 <path>"
    echo "Example: $0 /mnt/user/appdata"
    echo "Example: $0 /mnt/cache/appdata"
    exit 1
}

# Check if path argument is provided
if [[ $# -eq 0 ]]; then
    print_error "No path specified"
    show_usage
fi

APPDATA_PATH="$1"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

# Validate that the provided path is absolute
if [[ ! "$APPDATA_PATH" == /* ]]; then
    print_error "Please provide an absolute path (starting with /)"
    show_usage
fi

# Check if appdata path exists
if [[ ! -d "$APPDATA_PATH" ]]; then
    print_error "Appdata path $APPDATA_PATH does not exist"
    print_warning "Please verify your appdata path and modify the script if needed"
    exit 1
fi

print_status "Starting appdata permissions reset..."
print_status "Target path: $APPDATA_PATH"

# Confirm before proceeding
read -p "Do you want to proceed with resetting permissions? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Operation cancelled by user"
    exit 0
fi

# Reset ownership to nobody:users (standard Unraid practice)
print_status "Setting ownership to nobody:users..."
chown -R nobody:users "$APPDATA_PATH"

if [[ $? -eq 0 ]]; then
    print_success "Ownership reset completed"
else
    print_error "Failed to reset ownership"
fi

# Set directory permissions to 755
print_status "Setting directory permissions to 775..."
find "$APPDATA_PATH" -type d -exec chmod 775 {} \;

if [[ $? -eq 0 ]]; then
    print_success "Directory permissions set"
else
    print_error "Failed to set directory permissions"
fi

# Set file permissions to 644
print_status "Setting file permissions to 664..."
find "$APPDATA_PATH" -type f -exec chmod 664 {} \;

if [[ $? -eq 0 ]]; then
    print_success "File permissions set"
else
    print_error "Failed to set file permissions"
fi

# Make executable files executable (common executables)
print_status "Setting executable permissions for scripts and binaries..."
find "$APPDATA_PATH" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.pl" -o -name "*.exe" \) -exec chmod 775 {} \;

print_success "Appdata permissions reset completed!"
print_status "Summary of changes:"
echo "  - Owner: nobody:users"
echo "  - Directories: 775 (rwxrwxr-x)"
echo "  - Files: 664 (rw-rw-r--)"
echo "  - Scripts/Executables: 775 (rwxrwxr-x)"

print_warning "Note: You may need to restart your Docker containers if they were affected"
print_status "You can restart containers from the Unraid web interface"
