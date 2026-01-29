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
