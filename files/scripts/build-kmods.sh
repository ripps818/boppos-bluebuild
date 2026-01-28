#!/bin/bash

set -ouex pipefail

# --- Setup Variables ---
KERNEL_VERSION=$(rpm -qa kernel-cachyos --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -n 1)
KERNEL_DIR="/usr/src/kernels/${KERNEL_VERSION}"
INSTALL_MOD_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra"
RPMBUILD_DIR="/var/tmp/rpmbuild"
AKMOD_DL_DIR="/var/tmp/akmod_downloads"

# --- Prep Build Environment ---
mkdir -p "$AKMOD_DL_DIR" "$INSTALL_MOD_DIR"
mkdir -p "${RPMBUILD_DIR}"/{SPECS,SOURCES,BUILD,RPMS,SRPMS}

# Install Repos & Build Deps
curl -fsSL https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo -o /etc/yum.repos.d/terra.repo
dnf5 -y copr enable hikariknight/looking-glass-kvmfr

dnf5 install -y --allowerasing \
    git make gcc gcc-c++ rpm-build \
    dnf-plugins-core elfutils-libelf-devel

echo "--- Preparing to build for Kernel: ${KERNEL_VERSION} ---"

# --- Download Sources ---
# Download but DO NOT extract yet
dnf5 download -y --destdir="$AKMOD_DL_DIR" --resolve \
    --arch x86_64 --arch noarch \
    akmod-xone akmod-xpad-noone akmod-kvmfr \
    xone xone-firmware kvmfr

# Install source RPMs to /usr/src/akmods (Repo storage)
rpm -Uvh --force --nopost "$AKMOD_DL_DIR"/*.rpm

# --- Build Function ---
build_akmod() {
    local MODULE_NAME=$1
    local BUILD_SUBDIR="${2:-}"
    echo "--- Building ${MODULE_NAME} ---"

    # [FIX] Extract ONLY the current module's source inside the loop
    local SRC_RPM=$(find /usr/src/akmods -name "*${MODULE_NAME}*.src.rpm" | head -n 1)
    if [[ -z "$SRC_RPM" ]]; then
        echo "ERROR: Could not find src.rpm for ${MODULE_NAME}"
        exit 1
    fi
    rpm -ivh --define "_topdir ${RPMBUILD_DIR}" "$SRC_RPM"

    # Find SPEC
    local SPEC_FILE=$(find "${RPMBUILD_DIR}/SPECS" -name "*${MODULE_NAME}*.spec" | head -n 1)
    
    # Prep Source
    rpmbuild -bp --define "_topdir ${RPMBUILD_DIR}" "${SPEC_FILE}" --nodeps

    # Build Directory Logic
    cd "${RPMBUILD_DIR}/BUILD"
    local WRAPPER_DIR=$(find . -maxdepth 1 -type d -name "*${MODULE_NAME}*" | head -n 1)
    cd "${WRAPPER_DIR}"

    local SRC_DIR=$(find . -maxdepth 1 -mindepth 1 -type d -not -name "SPECPARTS" | head -n 1)
    if [[ -n "${SRC_DIR}" ]]; then cd "${SRC_DIR}"; fi
    if [[ -n "${BUILD_SUBDIR}" ]]; then cd "${BUILD_SUBDIR}"; fi

    # Compile
    make -C "${KERNEL_DIR}" M="$PWD" modules
    
    # Install & Strip
    find . -type f -name "*.ko" -exec strip --strip-debug {} \;
    find . -type f -name "*.ko" -exec install -Dm644 {} "${INSTALL_MOD_DIR}/" \;
    
    # Clean the build dir so it's fresh for the NEXT module
    rm -rf "${RPMBUILD_DIR}"/{BUILD,SPECS,SOURCES,RPMS,SRPMS}/*
}

# --- Execute Builds ---
build_akmod xone
build_akmod xpad-noone
build_akmod kvmfr "LookingGlass-master/module"

# --- Cleanup ---
echo "Cleaning up build environment..."
rm -rf "$RPMBUILD_DIR" /usr/src/akmods

# Uninstall temporary RPMs
rpm -e --nopost \
    akmod-xone akmod-xpad-noone akmod-kvmfr \
    xone xone-firmware xpad-noone kvmfr \
    akmods kmodtool fakeroot fakeroot-libs rpmdevtools grubby

# Reinstall userspace packages cleanly
echo "Reinstalling userspace packages..."
rpm -Uvh --force --nodeps \
    "$AKMOD_DL_DIR"/xone-*.rpm \
    "$AKMOD_DL_DIR"/xone-firmware-*.rpm \
    "$AKMOD_DL_DIR"/kvmfr-*.rpm

rm -rf "$AKMOD_DL_DIR"

# Ensure depmod runs
depmod -a -b / "${KERNEL_VERSION}"