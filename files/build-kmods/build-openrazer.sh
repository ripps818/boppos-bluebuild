#!/bin/bash
set -ouex pipefail

groupadd -f plugdev
make -C "${KERNEL_DIR}" M="$PWD/driver" modules
find driver -name '*.ko' -exec strip --strip-debug {} \;
find driver -name '*.ko' -exec install -Dm644 {} "${INSTALL_MOD_DIR}/" \;
make install-systemd DESTDIR=/ PREFIX=/usr
make udev_install DESTDIR=/ PREFIX=/usr
make daemon_install DESTDIR=/ PREFIX=/usr
make python_library_install DESTDIR=/ PREFIX=/usr