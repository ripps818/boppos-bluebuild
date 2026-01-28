#!/bin/bash

set -ouex pipefail

# robustly find the kernel version (grab the latest if multiple exist)
KERNEL_VERSION=$(rpm -qa kernel-cachyos --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -n 1)

# Define paths
KERNEL_DIR="/usr/src/kernels/${KERNEL_VERSION}"
INSTALL_MOD_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra"
SIGN_TOOL="${KERNEL_DIR}/scripts/sign-file"
TARGET_KERNEL="/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"

PRIVATE_KEY="/usr/share/boppos/keys/boppos.priv"
PUBLIC_KEY="/usr/share/boppos/keys/boppos.pem"

# Trap to ensure key deletion on ANY exit (success or failure)
trap 'rm -f "$PRIVATE_KEY"; echo "⚠️ Secure Boot key wiped from image."' EXIT

# Validation: Ensure the signing tool exists
if [ ! -f "$SIGN_TOOL" ]; then
    echo "ERROR: sign-file not found at $SIGN_TOOL"
    echo "Did you forget to install 'kernel-cachyos-devel'?"
    ls -R /usr/src/kernels/ || true
    exit 1
fi

echo "Signing kernel binary: ${TARGET_KERNEL}"
# Check if vmlinuz has a suffix or not
if [ ! -f "$TARGET_KERNEL" ]; then
    # Fallback search for vmlinuz-*
    TARGET_KERNEL=$(find "/usr/lib/modules/${KERNEL_VERSION}/" -name "vmlinuz*" -print -quit)
fi

# Sign the kernel
sbsign --key "$PRIVATE_KEY" --cert "$PUBLIC_KEY" --output "$TARGET_KERNEL" "$TARGET_KERNEL"

echo "Signing kernel modules in ${INSTALL_MOD_DIR}..."
# Sign external modules (akmods/extra)
if [ -d "$INSTALL_MOD_DIR" ]; then
    find "${INSTALL_MOD_DIR}" -type f -name "*.ko" -exec "${SIGN_TOOL}" \
        sha256 "$PRIVATE_KEY" "$PUBLIC_KEY" {} \;
else
    echo "No 'extra' modules directory found. Skipping module signing."
fi

if id "akmods" &>/dev/null; then
    userdel -r akmods || true
fi