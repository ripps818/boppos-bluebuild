#!/bin/bash

set -ouex pipefail

BRANCH="rework-profiles"
VERSION_FILE="/etc/tuned/cachyos-tuned-version"
TUNED_DIR="/usr/lib/tuned"
BACKUP_DIR="/usr/lib/tuned.bak"

# --- Uninstall/Restore ---
if [[ "$1" == "uninstall" ]]; then
    echo "--- Uninstalling CachyOS Tuned Profiles ---"
    if [[ -d "${BACKUP_DIR}" ]]; then
        echo "Restoring default profiles..."
        rm -rf "${TUNED_DIR}"
        mv "${BACKUP_DIR}" "${TUNED_DIR}"
    fi
    rm -f "${VERSION_FILE}"
    echo "--- Uninstallation Complete ---"
    exit 0
fi

# --- Installation ---

# Check if the correct version is already installed
if [[ -f "${VERSION_FILE}" ]] && [[ "$(cat "${VERSION_FILE}")" == "${BRANCH}" ]]; then
    echo "CachyOS Tuned profiles are already up to date."
    exit 0
fi

echo "--- Installing CachyOS Tuned Profiles (${BRANCH}) ---"

# 1. Backup default profiles
if [[ ! -d "${BACKUP_DIR}" ]]; then
    echo "Backing up default profiles to ${BACKUP_DIR}..."
    cp -r "${TUNED_DIR}" "${BACKUP_DIR}"
fi

# 2. Remove conflicting Bazzite profiles
echo "Removing conflicting Bazzite profiles..."
rm -rf ${TUNED_DIR}/*-bazzite

# 3. Download and install CachyOS profiles
TEMP_DIR=$(mktemp -d)
CACHYOS_TUNED_URL="https://github.com/CachyOS/tuned/archive/refs/heads/${BRANCH}.tar.gz"

echo "Downloading profiles from ${CACHYOS_TUNED_URL}..."
curl -L "${CACHYOS_TUNED_URL}" | tar -xz -C "${TEMP_DIR}"

SRC_DIR="${TEMP_DIR}/tuned-${BRANCH}"

echo "Installing profiles to ${TUNED_DIR}/..."
# Overwrite existing profiles and add new ones
cp -r ${SRC_DIR}/profiles/* "${TUNED_DIR}/"

if [[ -d "${SRC_DIR}/tuned/ppd" ]]; then
    echo "Installing global tuned configurations..."
    cp -r "${SRC_DIR}/tuned/ppd/ppd.conf" "/etc/tuned/"
fi

# 4. Create version file
echo "Creating version file..."
echo "${BRANCH}" > "${VERSION_FILE}"

# Cleanup
rm -rf "${TEMP_DIR}"
echo "--- CachyOS Tuned Profiles Installed ---"
