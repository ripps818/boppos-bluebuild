#!/bin/bash
# Check if the directory exists for the current user
if [ -d "$HOME/.cargo/bin" ]; then
    # Check if the path is already in PATH using Bash string matching
    if [[ ":$PATH:" != *":$HOME/.cargo/bin:"* ]]; then
        export PATH="$HOME/.cargo/bin:$PATH"
    fi
fi
