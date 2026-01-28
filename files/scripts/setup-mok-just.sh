#!/bin/bash
set -ouex pipefail

# We modify 00-default.just to prevent a name collision.
# We change "enroll-secure-boot-key" to "enroll-secure-boot-key-legacy"
# We also update the comment so it looks distinct in the menu.
DEFAULT_JUST="/usr/share/ublue-os/just/00-default.just"

echo "✏️  Renaming upstream Secure Boot command in $DEFAULT_JUST..."
sed -i 's/^enroll-secure-boot-key:/enroll-secure-boot-key-legacy:/' "$DEFAULT_JUST"
sed -i 's/^# Enroll Nvidia driver/# (Legacy) Enroll Nvidia driver/' "$DEFAULT_JUST"

# We append the import line to the main config so 'ujust' sees it.
MAIN_JUSTFILE="/usr/share/ublue-os/justfile"
IMPORT_LINE='import "just/60-boppos.just"'

if ! grep -q "$IMPORT_LINE" "$MAIN_JUSTFILE"; then
    echo "🔗 Registering 60-boppos.just in main justfile..."
    echo "$IMPORT_LINE" >> "$MAIN_JUSTFILE"
else
    echo "✅ 60-boppos.just is already registered."
fi