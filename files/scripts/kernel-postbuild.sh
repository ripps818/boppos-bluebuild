#!/bin/bash

set -ouex pipefail

# --- Robustly get the Kernel Version ---
# Handles multiple lines/newlines from rpm -qa
KERNEL_VERSION=$(rpm -qa kernel-cachyos --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -n 1)

echo "--- Post-Build Kernel Cleanup (Target: ${KERNEL_VERSION}) ---"

if [[ -z "$KERNEL_VERSION" ]]; then
    echo "ERROR: Could not detect kernel-cachyos version. Exiting."
    exit 1
fi

# --- Cleanup /usr/lib/modules (The Drivers) ---
cd /usr/lib/modules
if [[ ! -d "$KERNEL_VERSION" ]]; then
    # Fallback: Find a directory containing "cachyos" if exact match fails
    KERNEL_DIR=$(find . -maxdepth 1 -type d -name "*cachyos*" | head -n 1 | sed 's|./||')
else
    KERNEL_DIR="$KERNEL_VERSION"
fi

echo "Keeping drivers for: $KERNEL_DIR"
# Delete everything that is NOT the keeper directory
find . -maxdepth 1 -mindepth 1 -type d ! -name "$KERNEL_DIR" -print -exec rm -rf {} +


# --- Cleanup /usr/src/kernels (The Headers) ---
# Removes old Fedora headers to save ~150MB+
if [[ -d "/usr/src/kernels" ]]; then
    cd /usr/src/kernels
    echo "Cleaning up old kernel headers in /usr/src/kernels..."
    
    # Use the same version string to match the headers folder
    find . -maxdepth 1 -mindepth 1 -type d ! -name "$KERNEL_VERSION" -print -exec rm -rf {} +
else
    echo "/usr/src/kernels not found. Skipping header cleanup."
fi


# --- Boot & Initramfs Generation ---
TARGET_KERNEL="/usr/lib/modules/${KERNEL_DIR}/vmlinuz"
INITRAMFS="/usr/lib/modules/${KERNEL_DIR}/initramfs.img"

# Ensure vmlinuz is in the module directory (OSTree standard)
if [[ ! -f "$TARGET_KERNEL" ]]; then
    cp -a /boot/vmlinuz-"${KERNEL_VERSION}" "$TARGET_KERNEL" || echo "Failed to move vmlinuz"
fi

chmod 755 "$TARGET_KERNEL"

# Clean /boot entirely (Should be empty in the image layer)
rm -rf /boot/*

echo "Generating Initramfs for ${KERNEL_DIR}..."
depmod -a "$KERNEL_DIR"
dracut --no-hostonly --kver "$KERNEL_DIR" --reproducible -v --add ostree -f "$INITRAMFS"
chmod 0600 "$INITRAMFS"

# --- Final DNF Cleanup ---
rm -rf /var/lib/dnf
rm -f /var/tmp/*
dnf5 clean all

echo "--- Kernel Post-Build Complete ---"