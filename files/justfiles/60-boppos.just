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
