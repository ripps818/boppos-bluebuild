#!/usr/bin/env bash
set -euo pipefail

# The configuration is passed as the first argument
CONFIG="${1:-}"

# Ensure CONFIG is set
if [[ -z "${CONFIG}" ]]; then
    echo "ERROR: No configuration passed to module."
    exit 1
fi

# --- Helper Functions ---

get_config_value() {
    local query="$1"
    echo "$CONFIG" | jq -r "$query // empty"
}

install_packages() {
    local pkgs=("$@")
    if [[ ${#pkgs[@]} -eq 0 ]]; then return; fi

    echo "Installing required packages: ${pkgs[*]}"
    if command -v dnf5 &> /dev/null; then
        dnf5 install -y "${pkgs[@]}"
    elif command -v dnf &> /dev/null; then
        dnf install -y "${pkgs[@]}"
    elif command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y "${pkgs[@]}"
    elif command -v apk &> /dev/null; then
        apk add "${pkgs[@]}"
    else
        echo "WARNING: No supported package manager found. Please ensure '${pkgs[*]}' are installed."
    fi
}

ensure_dependencies() {
    local missing_pkgs=()
    
    if ! command -v jq &> /dev/null; then
        missing_pkgs+=("jq")
    fi
    
    if ! command -v sbsign &> /dev/null; then
        missing_pkgs+=("sbsigntools")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_pkgs+=("openssl")
    fi

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        install_packages "${missing_pkgs[@]}"
    fi
}

# --- Main Logic ---

ensure_dependencies

# 1. Parse Keys
PRIV_KEY=$(get_config_value '.keys.priv')
PEM_KEY=$(get_config_value '.keys.pem')
DER_KEY=$(get_config_value '.keys.der')

if [[ -z "$PRIV_KEY" ]]; then
    echo "ERROR: 'keys.priv' is required in configuration."
    exit 1
fi

if [[ ! -f "$PRIV_KEY" ]]; then
    echo "ERROR: Private key not found at: $PRIV_KEY"
    exit 1
fi

# Determine Public Key (PEM preferred for sbsign/sign-file usually accepts both)
PUB_KEY=""
if [[ -n "$PEM_KEY" && -f "$PEM_KEY" ]]; then
    PUB_KEY="$PEM_KEY"
elif [[ -n "$DER_KEY" && -f "$DER_KEY" ]]; then
    PUB_KEY="$DER_KEY"
fi

if [[ -z "$PUB_KEY" ]]; then
    echo "ERROR: A valid public key ('keys.pem' or 'keys.der') is required."
    exit 1
fi

# Trap to ensure private key is wiped from the image
trap 'echo "Cleaning up private key..."; rm -f "$PRIV_KEY"' EXIT

# Determine Modules Root Directory
MODULES_ROOT=$(get_config_value '.modules_dir')
if [[ -z "$MODULES_ROOT" ]]; then
    MODULES_ROOT="/lib/modules"
fi

# 2. Determine Kernels
KERNELS=()
# Check if 'kernel' is defined in config
if echo "$CONFIG" | jq -e '.kernel' >/dev/null; then
    # Check if it is an array or a single string
    if echo "$CONFIG" | jq -e '.kernel | type == "array"' >/dev/null; then
        mapfile -t KERNELS < <(echo "$CONFIG" | jq -r '.kernel[]')
    else
        KERNELS+=("$(get_config_value '.kernel')")
    fi
else
    echo "No specific kernel version configured. Auto-detecting installed kernels..."
    # Look in MODULES_ROOT for installed kernels
    for dir in "$MODULES_ROOT"/*; do
        if [[ -d "$dir" ]]; then
            KERNELS+=("$(basename "$dir")")
        fi
    done
fi

if [[ ${#KERNELS[@]} -eq 0 ]]; then
    echo "WARNING: No kernels found to sign."
    exit 0
fi

# 3. Process Each Kernel
for KVER in "${KERNELS[@]}"; do
    echo "--- Processing Kernel: $KVER ---"
    
    MODULES_DIR="${MODULES_ROOT}/$KVER"

    if [[ ! -f "$MODULES_DIR/modules.dep" ]]; then
        echo "Skipping $KVER: Incomplete installation (modules.dep missing)."
        continue
    fi

    VMLINUZ_PATH="$MODULES_DIR/vmlinuz"
    
    # Locate vmlinuz
    if [[ ! -f "$VMLINUZ_PATH" ]]; then
        # Try finding it with a suffix or in /boot if not in modules dir
        FOUND_KERNEL=$(find "$MODULES_DIR" -maxdepth 1 -name "vmlinuz*" | head -n 1)
        if [[ -n "$FOUND_KERNEL" ]]; then
            VMLINUZ_PATH="$FOUND_KERNEL"
        fi
    fi

    # Locate sign-file tool
    # Common locations:
    # /usr/src/kernels/$KVER/scripts/sign-file
    # /lib/modules/$KVER/build/scripts/sign-file
    SIGN_TOOL=""
    POSSIBLE_TOOLS=(
        "/usr/src/kernels/$KVER/scripts/sign-file"
        "$MODULES_DIR/build/scripts/sign-file"
        "${MODULES_ROOT}/$KVER/build/scripts/sign-file"
    )
    
    for tool in "${POSSIBLE_TOOLS[@]}"; do
        if [[ -f "$tool" && -x "$tool" ]]; then
            SIGN_TOOL="$tool"
            break
        fi
    done

    # Sign Kernel Image
    if [[ -f "$VMLINUZ_PATH" ]]; then
        echo "Signing kernel binary: $VMLINUZ_PATH"
        if command -v sbsign >/dev/null; then
            # sbsign requires a cert (PEM/DER) and key
            sbsign --key "$PRIV_KEY" --cert "$PUB_KEY" --output "$VMLINUZ_PATH" "$VMLINUZ_PATH"
            echo "Signed $VMLINUZ_PATH"

            if command -v sbverify >/dev/null; then
                echo "Verifying kernel signature..."
                sbverify --cert "$PUB_KEY" "$VMLINUZ_PATH"
            fi
        else
            echo "WARNING: 'sbsign' command not found. Skipping kernel binary signing."
        fi
    else
        echo "WARNING: vmlinuz not found for $KVER at $VMLINUZ_PATH"
    fi

    # Sign Modules
    if [[ -n "$SIGN_TOOL" ]]; then
        echo "Signing kernel modules in $MODULES_DIR..."
        # Find all .ko files (skipping compressed ones as sign-file usually requires uncompressed ELF)
        # This will catch modules in 'extra' as well as any other uncompressed modules.
        find "$MODULES_DIR" -type f -name "*.ko" | while read -r mod; do
            "$SIGN_TOOL" sha256 "$PRIV_KEY" "$PUB_KEY" "$mod"
        done

        echo "Verifying module signatures..."
        # Check for the magic string "~Module signature appended~" in the binary files
        total_mods=$(find "$MODULES_DIR" -type f -name "*.ko" | wc -l)
        signed_mods=$(find "$MODULES_DIR" -type f -name "*.ko" -exec grep -a -l "~Module signature appended~" {} + | wc -l || echo 0)
        
        echo "Verified signatures: $signed_mods/$total_mods modules."

        echo "Module signing complete for $KVER."
    else
        echo "WARNING: 'sign-file' tool not found for $KVER. Skipping module signing."
        echo "Ensure kernel-devel or headers are installed."
    fi
done

echo "--- Signing Complete ---"
