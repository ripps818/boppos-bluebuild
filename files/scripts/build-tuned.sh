#!/usr/bin/env bash

set -ouex pipefail

# Clone the CachyOS tuned repository
git clone --depth=1 --branch=cachyos https://github.com/cachyos/tuned.git /tmp/tuned

# Get build dependencies from spec file
# and install them
dnf install -y rpm-build
dnf builddep -y /tmp/tuned/tuned.spec

# --- Patch the tuned.spec file to include powerprofilesctl ---
# This addresses the "Installed (but unpackaged) file(s) found" error.
# The `make install-ppd` step installs this binary, but it's not always
# explicitly listed in the upstream tuned.spec for all distributions.
echo "Patching tuned.spec to include /usr/bin/powerprofilesctl..."
sed -i '/^%files -n tuned-ppd/a /usr/bin/powerprofilesctl' /tmp/tuned/tuned.spec
# Create the source tarball
pushd /tmp/tuned
NAME=$(grep -m1 '^Name:' tuned.spec | awk '{print $2}')
VERSION=$(grep -m1 '^Version:' tuned.spec | awk '{print $2}')
git archive --format=tar.gz --prefix="${NAME}-${VERSION}/" --output="${NAME}-${VERSION}.tar.gz" HEAD
popd

# Build the RPM
rpmbuild -bb --nocheck \
    --define "_topdir /tmp/rpmbuild" \
    --define "_sourcedir /tmp/tuned" \
    /tmp/tuned/tuned.spec

# Create a directory for our custom RPMs (using /var/tmp for better persistence)
mkdir -p /var/tmp/rpms

# Copy and rename RPMs to fixed names so they can be explicitly listed in recipe.yml
# (BlueBuild's dnf module does not support glob expansion for local files)
cp /tmp/rpmbuild/RPMS/noarch/tuned-[0-9]*.rpm /var/tmp/rpms/tuned.rpm
cp /tmp/rpmbuild/RPMS/noarch/tuned-ppd-[0-9]*.rpm /var/tmp/rpms/tuned-ppd.rpm
cp /tmp/rpmbuild/RPMS/noarch/tuned-utils-[0-9]*.rpm /var/tmp/rpms/tuned-utils.rpm
