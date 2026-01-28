#!/bin/bash
set -ux

echo "=============================================="
echo "🔍 DIAGNOSTIC: Checking for Secure Boot Keys"
echo "=============================================="

# Check if the directory structure even exists
if [ ! -d "/usr/share/boppos/keys" ]; then
    echo "❌ CRITICAL FAIL: Directory /usr/share/boppos/keys does NOT exist."
    echo "   Current contents of /usr/share:"
    ls -la /usr/share
    exit 1
fi

# List the contents (so we can see what actually made it)
echo "📂 Contents of /usr/share/boppos/keys:"
ls -laR /usr/share/boppos/keys

# Explicitly verify the Private Key
KEY_PATH="/usr/share/boppos/keys/boppos.priv"
if [ ! -f "$KEY_PATH" ]; then
    echo "❌ CRITICAL FAIL: boppos.priv is MISSING from the image."
    exit 1
elif [ ! -s "$KEY_PATH" ]; then
    echo "❌ CRITICAL FAIL: boppos.priv exists but is EMPTY (0 bytes)."
    exit 1
else
    echo "✅ SUCCESS: boppos.priv found and is not empty."
fi

# Explicitly verify the Public PEM Key
PEM_PATH="/usr/share/boppos/keys/boppos.pem"
if [ ! -f "$PEM_PATH" ]; then
    echo "❌ CRITICAL FAIL: boppos.pem is MISSING."
    exit 1
else
    echo "✅ SUCCESS: boppos.pem found."
fi

# Explicitly verify the Public DER Key
DER_PATH="/usr/share/boppos/keys/boppos.der"
if [ ! -f "$DER_PATH" ]; then
    echo "❌ CRITICAL FAIL: boppos.der is MISSING."
    exit 1
else
    echo "✅ SUCCESS: boppos.der found."
fi

echo "=============================================="
echo "🎉 ALL FILES PRESENT. Proceeding to Install..."
echo "=============================================="
