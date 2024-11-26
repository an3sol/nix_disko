#!/usr/bin/env bash

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "\n${GREEN}==>${NC} $1"
}

# Error handling function
error() {
    echo -e "\n${YELLOW}ERROR:${NC} $1" >&2
    exit 1
}

# Disk selection
select_disk() {
    log "Available Disks:"
    readarray -t DISKS < <(ls /dev/disk/by-id/ | grep -E 'nvme|ata|scsi')
    
    for i in "${!DISKS[@]}"; do
        echo "$((i+1))) ${DISKS[i]}"
    done

    read -p "Select disk number: " disk_choice
    
    # Validate input
    if [[ ! "$disk_choice" =~ ^[0-9]+$ ]] || 
       [[ "$disk_choice" -lt 1 ]] || 
       [[ "$disk_choice" -gt "${#DISKS[@]}" ]]; then
        error "Invalid disk selection"
    fi

    DISK="/dev/disk/by-id/${DISKS[$((disk_choice-1))]}"
    DISK_NAME="${DISKS[$((disk_choice-1))]}"
    
    log "Selected Disk: $DISK_NAME"
}

# Confirm disk wipe
confirm_wipe() {
    read -p "WARNING: This will ERASE ALL DATA on $DISK_NAME. Are you sure? (y/N): " confirm
    [[ "${confirm,,}" =~ ^y(es)?$ ]] || error "Installation cancelled"
}

# Partition disk
partition_disk() {
    log "Clearing existing partition table"
    wipefs -af "$DISK"
    sgdisk -Zo "$DISK"

    log "Creating EFI partition (512MB)"
    sgdisk -n1:1M:+512M -t1:EF00 "$DISK"
    EFI_PART="${DISK}-part1"

    log "Creating ZFS partition (remaining space)"
    sgdisk -n2:0:0 -t2:bf01 "$DISK"
    ZFS_PART="${DISK}-part2"

    # Inform kernel of partition changes
    partprobe "$DISK"
    sleep 2
}

# Format EFI partition
format_efi() {
    log "Formatting EFI partition"
    mkfs.vfat -F 32 "$EFI_PART"
}

# Create ZFS pool
create_zpool() {
    log "Creating ZFS pool with optimized settings"
    zpool create -f \
        -O acltype=posixacl \
        -O xattr=sa \
        -o ashift=12 \
        -o autoexpand=on \
        -o autotrim=on \
        -R /mnt \
        -O atime=off \
        -O sync=standard \
        -O compression=zstd-3 \
        -O mountpoint=none \
        zroot "$ZFS_PART"

    # Remove unsupported feature flags
    #zpool set feature@large_dnode=enabled zroot
}

# Create ZFS datasets
create_datasets() {
    log "Creating ZFS datasets"

    # Root dataset
    zfs create \
        -o atime=off \
        -o sync=standard \
        -o compression=zstd-3 \
        -o mountpoint=legacy \
        zroot/root

    # Var dataset
    zfs create \
        -o atime=off \
        -o sync=standard \
        -o compression=zstd-3 \
        -o mountpoint=legacy \
        zroot/var

    # Optional: Encrypted private dataset
    zfs create \
        -o encryption=aes-256-gcm \
        -o keyformat=passphrase \
        -o keylocation=prompt \
        -o atime=off \
        -o sync=standard \
        -o compression=zstd-3 \
        -o mountpoint=/mnt/private \
        zroot/private
}

# Mount filesystems
mount_filesystems() {
    log "Mounting filesystems"
    
    # Mount root
    mount -t zfs zroot/root /mnt
    
    # Create and mount boot
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot
    
    # Create and mount var
    mkdir -p /mnt/var
    mount -t zfs zroot/var /mnt/var
}

# Main installation script
main() {
    # Ensure script is run as root
    [[ "$(id -u)" -eq 0 ]] || error "Must be run as root"

    # Check for required tools
    for cmd in zpool zfs sgdisk wipefs mkfs.vfat; do
        command -v "$cmd" >/dev/null 2>&1 || error "Missing $cmd command"
    done

    select_disk
    confirm_wipe
    partition_disk
    format_efi
    create_zpool
    create_datasets
    mount_filesystems

    echo -e "\n${GREEN}ZFS Installation Complete!${NC}"
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Generate hardware configuration: nixos-generate-config --root /mnt"
    echo "2. Edit /mnt/etc/nixos/configuration.nix"
    echo "3. Install NixOS: nixos-install"
}

# Run the script
main
