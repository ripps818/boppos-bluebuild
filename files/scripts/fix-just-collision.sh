#!/bin/bash
set -ouex pipefail

# Rename the upstream command to prevent conflict with 60-boppos.just
sed -i 's/^enroll-secure-boot-key:/enroll-secure-boot-key-upstream:/' /usr/share/ublue-os/just/00-default.just
