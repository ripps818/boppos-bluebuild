#!/usr/bin/env bash
set -ouex pipefail

echo "--- Force-installing cloudflare-warp (CLI only) ---"
# We bypass DNF's dependency resolver because modern Fedora lacks webkit2gtk3.
# This intentionally breaks the GUI but leaves warp-cli and warp-svc fully functional.
mkdir -p /tmp/warp
cd /tmp/warp

# Add the repository explicitly since BlueBuild cleans up repos after the dnf module
curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo -o /etc/yum.repos.d/cloudflare-warp-ascii.repo

dnf5 download -y cloudflare-warp --arch=x86_64
rpm -ivh --nodeps ./cloudflare-warp*.rpm

echo "--- Installing wgcf (Native WireGuard alternative) ---"
# wgcf is a tool to generate WireGuard profiles from Cloudflare WARP accounts
# We parse the redirect header to avoid GitHub API rate-limiting in CI
LATEST_TAG=$(curl -sI https://github.com/ViRb3/wgcf/releases/latest | grep -i '^location:' | awk -F'/' '{print $NF}' | tr -d '\r')
VERSION="${LATEST_TAG#v}"
WGCF_URL="https://github.com/ViRb3/wgcf/releases/download/${LATEST_TAG}/wgcf_${VERSION}_linux_amd64"

curl -fsSL "$WGCF_URL" -o /usr/bin/wgcf
chmod +x /usr/bin/wgcf

# Clean up
cd /
rm -f /etc/yum.repos.d/cloudflare-warp-ascii.repo
rm -rf /tmp/warp