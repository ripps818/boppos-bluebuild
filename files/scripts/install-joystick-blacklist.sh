#!/bin/bash
set -ouex pipefail

# Download the upstream joystick blacklist
echo "Downloading udev-joystick-blacklist..."
curl -fL "https://raw.githubusercontent.com/denilsonsa/udev-joystick-blacklist/master/51-these-are-not-joysticks.rules" \
    -o /usr/lib/udev/rules.d/51-these-are-not-joysticks.rules

# Append custom Keychron V1 Max rule to the downloaded blacklist
echo 'SUBSYSTEM=="input", ATTRS{idVendor}=="3434", ATTRS{idProduct}=="0913", ENV{ID_INPUT_JOYSTICK}=="?*", ENV{ID_INPUT_JOYSTICK}=""' >> /usr/lib/udev/rules.d/51-these-are-not-joysticks.rules
echo 'SUBSYSTEM=="input", ATTRS{idVendor}=="3434", ATTRS{idProduct}=="0913", KERNEL=="js[0-9]*", MODE="0000", ENV{ID_INPUT_JOYSTICK}=""' >> /usr/lib/udev/rules.d/51-these-are-not-joysticks.rules