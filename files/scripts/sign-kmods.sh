#!/bin/bash

set -ouex pipefail

KERNEL_VERSION=$(rpm -qa kernel-cachyos --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')
KERNEL_DIR="/usr/src/kernels/${KERNEL_VERSION}"
INSTALL_MOD_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra"

PRIVATE_KEY="/tmp/files/certs/private_key.priv"
PUBLIC_KEY="/tmp/files/certs/public_key.pem"

if [[ -f "$PRIVATE_KEY" ]] && [[ -f "$PUBLIC_KEY" ]]; then
    echo "Importing keys into sbctl database..."
    # This moves the keys into /etc/sbctl/keys (or /usr/share/secureboot), baking them into the image
    sbctl import-keys --force --db-key "$PRIVATE_KEY" --db-cert "$PUBLIC_KEY"

    # Copy keys to /etc/sbctl to ensure persistence in OSTree images
    mkdir -p /etc/sbctl
    cp -r /var/lib/sbctl/* /etc/sbctl/ 2>/dev/null || true

    echo "Signing kernel image with sbsign..."
    # Sign the vmlinuz binary
    sbsign --key "$PRIVATE_KEY" --cert "$PUBLIC_KEY" --output "/usr/lib/modules/${KERNEL_VERSION}/vmlinuz" "/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"

    echo "Signing kernel modules in ${INSTALL_MOD_DIR}..."
    # sbctl doesn't sign .ko files, so we use the kernel's sign-file tool
    # We use the keys we just imported (or the temp ones, they are the same)
    find "${INSTALL_MOD_DIR}" -type f -name "*.ko" -exec "${KERNEL_DIR}/scripts/sign-file" \
        sha256 "$PRIVATE_KEY" "$PUBLIC_KEY" {} \;

    # Cleanup the injected secrets from /tmp/files so they don't persist in that specific location
    # (Note: They ARE persisted in /etc/sbctl/keys now, which is intentional for this approach)
    rm -f "$PRIVATE_KEY" "$PUBLIC_KEY"
else
    echo "WARNING: Secure Boot keys not found in /tmp/files/certs."
    echo "Skipping signing. If this is a local build, this is expected."
fi

# Remove the akmods user if it exists (cleanup)
if id "akmods" &>/dev/null; then
    userdel -r akmods || true
fi