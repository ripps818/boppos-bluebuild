
# Initialize BoppOS Secure Boot (Run once)
setup-secureboot:
    @echo "Setting up BoppOS keys..."
    @echo "Step 1: Generating local keys..."
    sudo sbctl create-keys
    
    @echo "Step 2: Importing BoppOS signing certificate..."
    # Ensure this directory exists before copying
    sudo mkdir -p /var/lib/sbctl/keys/db
    sudo cp /usr/share/boppos/keys/boppos.pem /var/lib/sbctl/keys/db/boppos.pem
    
    @echo "Step 3: Enrolling keys (including Microsoft compatibility)..."
    sudo sbctl enroll-keys --microsoft
    
    @echo "Success! Secure Boot is configured. Please reboot."