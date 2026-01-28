#!/bin/bash
set -ux

echo "=============================================="
echo "🔍 DIAGNOSTIC: Checking for Secure Boot Keys"
echo "=============================================="

# 1. Check if the directory structure even exists
if [ ! -d "/usr/share/boppos/keys" ]; then
    echo "❌ CRITICAL FAIL: Directory /usr/share/boppos/keys does NOT exist."
    echo "   Current contents of /usr/share:"
    ls -la /usr/share
    exit 1
fi

# 2. List the contents (so we can see what actually made it)
echo "📂 Contents of /usr/share/boppos/keys:"
ls -laR /usr/share/boppos/keys

# 3. Explicitly verify the Private Key
KEY_PATH="/usr/share/boppos/keys/boppos.priv"
if [ ! -f "$KEY_PATH" ]; then
    echo "❌ CRITICAL FAIL: boppos.priv is MISSING from the image."
    echo "   (This confirms the .gitignore or build context is still filtering it out)"
    exit 1
elif [ ! -s "$KEY_PATH" ]; then
    echo "❌ CRITICAL FAIL: boppos.priv exists but is EMPTY (0 bytes)."
    exit 1
else
    echo "✅ SUCCESS: boppos.priv found and is not empty."
fi

# 4. Explicitly verify the Public Key
PEM_PATH="/usr/share/boppos/keys/boppos.pem"
if [ ! -f "$PEM_PATH" ]; then
    echo "❌ CRITICAL FAIL: boppos.pem is MISSING."
    exit 1
else
    echo "✅ SUCCESS: boppos.pem found."
fi

echo "=============================================="
echo "🎉 ALL FILES PRESENT. Proceeding to Kernel..."
echo "=============================================="
