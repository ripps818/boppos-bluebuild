#!/bin/bash

set -ouex pipefail

# Install sbctl manually to resolve file conflict with cachyos-settings
# cachyos-settings provides /usr/bin/sbctl-batch-sign, which conflicts with sbctl package
dnf5 -y copr enable chenxiaolong/sbctl
mkdir -p /tmp/sbctl-pkg
dnf5 download -y --destdir=/tmp/sbctl-pkg --resolve sbctl
rpm -Uvh --replacefiles --nodeps /tmp/sbctl-pkg/*.rpm
rm -rf /tmp/sbctl-pkg

KERNEL_VERSION=$(rpm -qa kernel-cachyos --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')
KERNEL_DIR="/usr/src/kernels/${KERNEL_VERSION}"
INSTALL_MOD_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra"

RPMBUILD_DIR="/var/tmp/rpmbuild"
AKMOD_DL_DIR="/var/tmp/akmod_downloads"

# Install Repos
curl -fsSL https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo -o /etc/yum.repos.d/terra.repo
dnf5 -y copr enable hikariknight/looking-glass-kvmfr

dnf5 install -y --allowerasing \
    git make gcc gcc-c++ rpm-build \
    dnf-plugins-core elfutils-libelf-devel

# Setup Directory Structure
mkdir -p "$AKMOD_DL_DIR"
mkdir -p "${RPMBUILD_DIR}"/{SPECS,SOURCES,BUILD,RPMS,SRPMS}
mkdir -p "$INSTALL_MOD_DIR"

echo "--- Preparing to build for Kernel: ${KERNEL_VERSION} ---"

# Download Source RPMs (contained inside the akmod binaries)
dnf5 download -y --destdir="$AKMOD_DL_DIR" --resolve \
    --arch x86_64 --arch noarch \
    akmod-xone \
    akmod-xpad-noone \
    akmod-kvmfr \
    xone \
    xone-firmware \
    kvmfr

# Install them (skipping scripts) to place .src.rpm in /usr/src/akmods
rpm -Uvh --force --nopost "$AKMOD_DL_DIR"/*.rpm

# Extract Sources to our build temp
echo "--- Extracting Sources ---"
rpm -ivh --define "_topdir ${RPMBUILD_DIR}" /usr/src/akmods/*.src.rpm

build_akmod() {
    local MODULE_NAME=$1
    local BUILD_SUBDIR="${2:-}"
    echo "--- Building ${MODULE_NAME} ---"

    # 1. Install the akmod package to extract the src.rpm
    rpm -Uvh --force --nopost "${AKMOD_DL_DIR}/akmod-${MODULE_NAME}"*.rpm

    # 2. Find the src.rpm (usually in /usr/src/akmods)
    local SRC_RPM=$(find /usr/src/akmods -name "*${MODULE_NAME}*.src.rpm" | head -n 1)
    
    # 3. Install src.rpm into rpmbuild tree
    rpm -i --define "_topdir ${RPMBUILD_DIR}" "${SRC_RPM}"

    # 4. Prep source
    local SPEC_FILE=$(find "${RPMBUILD_DIR}/SPECS" -name "*${MODULE_NAME}*.spec" | head -n 1)
    rpmbuild -bp --define "_topdir ${RPMBUILD_DIR}" "${SPEC_FILE}" --nodeps

    # 5. Enter Build Directory
    cd "${RPMBUILD_DIR}/BUILD"
    local WRAPPER_DIR=$(find . -maxdepth 1 -type d -name "*${MODULE_NAME}*" | head -n 1)
    cd "${WRAPPER_DIR}"

    local SRC_DIR=$(find . -maxdepth 1 -mindepth 1 -type d -not -name "SPECPARTS" | head -n 1)
    if [[ -n "${SRC_DIR}" ]]; then
        cd "${SRC_DIR}"
    fi

    if [[ -n "${BUILD_SUBDIR}" ]]; then
        cd "${BUILD_SUBDIR}"
    fi

    # 6. Compile & Install
    make -C "${KERNEL_DIR}" M="$PWD" modules
    
    find . -type f -name "*.ko" -exec install -Dm644 {} "${INSTALL_MOD_DIR}/" \;
    
    # Cleanup
    rm -rf "${RPMBUILD_DIR}"/{BUILD,SPECS,SOURCES,RPMS,SRPMS}/*
}

build_akmod xone
build_akmod xpad-noone
build_akmod kvmfr "LookingGlass-master/module"

# Cleanup
rm -rf "$RPMBUILD_DIR" /usr/src/akmods

# Uninstall the RPMs we installed manually to avoid conflicts with rpm-ostree
echo "Cleaning up build RPMs..."
rpm -e --nopost \
    akmod-xone akmod-xpad-noone akmod-kvmfr xone xone-firmware xpad-noone kvmfr \
    akmods kmodtool fakeroot fakeroot-libs rpmdevtools grubby

# Reinstall userspace packages for xone and kvmfr
echo "Reinstalling userspace packages..."
rpm -Uvh --force --nodeps "$AKMOD_DL_DIR"/xone-*.rpm "$AKMOD_DL_DIR"/kvmfr-*.rpm

rm -rf "$AKMOD_DL_DIR"