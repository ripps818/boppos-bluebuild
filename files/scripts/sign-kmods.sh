#!/bin/bash

set -ouex pipefail

KERNEL_VERSION=$(rpm -qa kernel-cachyos --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')
KERNEL_DIR="/usr/src/kernels/${KERNEL_VERSION}"
INSTALL_MOD_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra"

# Ensure private key is removed on exit to prevent leakage
trap 'rm -f /etc/pki/akmods/private/private_key.priv' EXIT

# Install signing tools
rpm-ostree install akmods openssl sbsigntools

# Check if key was injected via build process (e.g. GitHub Secret)
if [ -f /tmp/files/private_key.priv ]; then
    echo "Found injected private key, moving to location..."
    mkdir -p /etc/pki/akmods/private
    mv /tmp/files/private_key.priv /etc/pki/akmods/private/private_key.priv
fi

# Generate ephemeral signing keys if a persistent key was not provided
if [ ! -f /etc/pki/akmods/private/private_key.priv ]; then
    echo "Generating ephemeral signing keys..."
    /usr/sbin/kmodgenca -a
fi

echo "Signing modules in ${INSTALL_MOD_DIR}..."
find "${INSTALL_MOD_DIR}" -type f -name "*.ko" -exec "${KERNEL_DIR}/scripts/sign-file" \
    sha256 /etc/pki/akmods/private/private_key.priv /etc/pki/akmods/certs/public_key.der {} \;

# Sign the kernel image (vmlinuz) for Secure Boot
echo "Signing kernel image..."
# sbsign requires PEM format certificate
openssl x509 -in /etc/pki/akmods/certs/public_key.der -inform DER -out /etc/pki/akmods/certs/public_key.pem
sbsign --key /etc/pki/akmods/private/private_key.priv --cert /etc/pki/akmods/certs/public_key.pem \
    --output "/usr/lib/modules/${KERNEL_VERSION}/vmlinuz" "/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"

# Copy public key for enrollment (ujust enroll-secure-boot-key)
if [ -f /etc/pki/akmods/certs/akmods-ublue.der ]; then
    mv /etc/pki/akmods/certs/akmods-ublue.der /etc/pki/akmods/certs/akmods-ublue.der.bak
fi
cp /etc/pki/akmods/certs/public_key.der /etc/pki/akmods/certs/akmods-ublue.der

# Cleanup signing tools
rpm-ostree uninstall akmods sbsigntools

# Remove the akmods user
if id "akmods" &>/dev/null; then
    userdel -r akmods || true
fi