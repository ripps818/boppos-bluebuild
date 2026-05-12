# Boot into MOK Manager to enroll the BoppOS key
enroll-secure-boot-keys:
    @echo "🔐 Enrolling BoppOS Key into MOK (Shim)..."
    @if [ ! -f "/usr/share/boppos/keys/boppos.der" ]; then \
        echo "❌ Error: /usr/share/boppos/keys/boppos.der not found!"; \
        exit 1; \
    fi
    @echo "1. You will be asked for a ONE-TIME password."
    @echo "2. Remember it. You will need it after reboot."
    @echo "3. On the blue 'MOK Management' screen: Select 'Enroll MOK' -> 'Continue' -> 'Yes'."
    @echo ""
    sudo mokutil --import /usr/share/boppos/keys/boppos.der
    @echo ""
    @echo "✅ Setup complete. Please REBOOT now to finish enrollment."

# Enable KVMFR and Nested Virtualization setup
setup-kvm-extras:
    sudo cp /usr/share/boppos/unused_files/kvmfr.conf /etc/modprobe.d/
    sudo cp /usr/share/boppos/unused_files/kvm_nested.conf /etc/modprobe.d/
    sudo cp /usr/share/boppos/unused_files/kvmfr.rules /etc/udev/rules.d/
    echo "Configs copied. Please reboot to apply changes."

# Toggle between Preemption modes (Latency vs. Throughput)
toggle-preempt:
    #!/usr/bin/env bash
    # Get current mode (strips parentheses from output)
    CURRENT=$(cat /sys/kernel/debug/sched/preempt | grep -oP '\(\K[^\)]+')
    echo "Current preemption mode is: $CURRENT"
    echo "Choose a new mode:"
    echo "1) Full      (Lowest Latency - Best for Gaming)"
    echo "2) Lazy      (Balanced - General Desktop/Workstation)"
    echo "3) Voluntary (Highest Throughput - Best for Compiling)"
    read -p "Selection [1-3]: " CHOICE
    case $CHOICE in
        1) sudo sh -c 'echo full > /sys/kernel/debug/sched/preempt' && echo "Switched to FULL.";;
        2) sudo sh -c 'echo lazy > /sys/kernel/debug/sched/preempt' && echo "Switched to LAZY.";;
        3) sudo sh -c 'echo voluntary > /sys/kernel/debug/sched/preempt' && echo "Switched to VOLUNTARY.";;
        *) echo "Invalid selection.";;
    esac

# Set up Cloudflare WARP via native WireGuard and import it into NetworkManager
setup-warp-wireguard:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "--- Creating Cloudflare WARP WireGuard Profile ---"

    # Isolate configuration files in the user's config directory
    WORK_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wgcf"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    if [ -f "wgcf-account.toml" ]; then
        echo "Found existing wgcf account."
    else
        echo "Registering new wgcf account..."
        wgcf register --accept-tos
    fi

    echo ""
    read -p "Do you have a WARP+ (premium) License Key? [y/N]: " HAS_KEY
    if [[ "$HAS_KEY" =~ ^[Yy]$ ]]; then
        read -p "Enter your WARP+ License Key: " WARP_KEY
        if [ -n "$WARP_KEY" ]; then
            # Replace the license_key line in the toml file
            sed -i "s/license_key = .*/license_key = '${WARP_KEY}'/" wgcf-account.toml
            echo "Applying WARP+ license..."
            if wgcf update; then
                echo "WARP+ license applied successfully!"
            else
                echo "⚠️ Warning: Failed to apply WARP+ license. Please check if the key is valid."
                sed -i "s/license_key = .*/license_key = ''/" wgcf-account.toml
            fi
        fi
    fi

    echo "Generating WireGuard profile..."
    wgcf generate

    # Import into NetworkManager (Requires root/sudo for system connections)
    if nmcli connection show "wgcf-profile" >/dev/null 2>&1; then
        echo "Profile 'wgcf-profile' already exists in NetworkManager."
        echo "If you need to update it, please remove the old connection first: nmcli connection delete wgcf-profile"
    else
        echo "Importing profile into NetworkManager..."
        sudo nmcli connection import type wireguard file wgcf-profile.conf
    fi

    echo "--- Setup Complete! ---"
    echo "You can now toggle WARP via your system's Network Settings GUI!"
