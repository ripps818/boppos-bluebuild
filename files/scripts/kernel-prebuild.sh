#!/bin/bash
set -ouex pipefail

# Mask hooks
mkdir -p /boot/grub2
mkdir -p /etc/kernel/install.d
ln -s /dev/null /etc/kernel/install.d/05-rpmostree.install
ln -s /dev/null /etc/kernel/install.d/20-grub.install
ln -s /dev/null /etc/kernel/install.d/50-dracut.install
ln -s /dev/null /etc/kernel/install.d/90-loaderentry.install
