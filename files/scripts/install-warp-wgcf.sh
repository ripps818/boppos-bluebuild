#!/usr/bin/env bash
set -ouex pipefail

echo "--- Force-installing cloudflare-warp (CLI only) ---"
# We bypass DNF's dependency resolver because modern Fedora lacks webkit2gtk3.
# This intentionally breaks the GUI but leaves warp-cli and warp-svc fully functional.
mkdir -p /tmp/warp
cd /tmp/warp

dnf5 download -y --resolve cloudflare-warp
rpm -ivh --nodeps ./cloudflare-warp*.rpm

echo "--- Installing wgcf (Native WireGuard alternative) ---"
# wgcf is a tool to generate WireGuard profiles from Cloudflare WARP accounts
# We pull the latest release binary for linux_amd64 directly from GitHub
WGCF_URL=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest | \
    jq -r '.assets[].browser_download_url' | \
    grep 'linux_amd64$' | \
    head -n 1)

curl -fsSL "$WGCF_URL" -o /usr/bin/wgcf
chmod +x /usr/bin/wgcf

# Clean up
cd /
rm -rf /tmp/warp