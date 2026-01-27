#!/bin/bash
set -ouex pipefail

KERNEL_VERSION=$(rpm -qa kernel-cachyos --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')

# Unmask hooks
rm -f /etc/kernel/install.d/05-rpmostree.install
rm -f /etc/kernel/install.d/20-grub.install
rm -f /etc/kernel/install.d/50-dracut.install
rm -f /etc/kernel/install.d/90-loaderentry.install

# 1. Clean up old/stock kernel artifacts
#    We remove any module directory that does NOT contain 'cachyos' in the name.
echo "Cleaning up old kernel modules..."
find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d -not -name "*cachyos*" -exec rm -rf {} +

# 2. Generate Initramfs for the NEW kernel
if [[ -n "$KERNEL_VERSION" ]]; then
    TARGET_KERNEL="/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"
    
    # SAFETY CHECK: Only delete /boot if the kernel exists in the target
    if [[ -f "$TARGET_KERNEL" ]]; then
        echo "Kernel found at $TARGET_KERNEL. Cleaning redundant files in /boot..."
        rm -rf /boot/*
    else
        echo "WARNING: Kernel missing from $TARGET_KERNEL! Moving from /boot..."
        # Fallback: If it wasn't there, rescue it from /boot
        cp -a /boot/vmlinuz-"${KERNEL_VERSION}" "$TARGET_KERNEL"
        chmod 755 "$TARGET_KERNEL"
        rm -rf /boot/*
    fi

    # Generate Initramfs (Required for Boot)
    echo "Generating Initramfs..."
    depmod -a "$KERNEL_VERSION"
    dracut --no-hostonly --kver "$KERNEL_VERSION" --reproducible -v --add ostree -f "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"
    chmod 0600 "/usr/lib/modules/$KERNEL_VERSION/initramfs.img"
fi

# Cleanup
rm -rf /var/lib/dnf
rm -f /var/tmp/*

dnf5 clean all