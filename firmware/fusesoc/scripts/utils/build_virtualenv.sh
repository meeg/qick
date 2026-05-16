#!/usr/bin/bash

set -e

#!/bin/bash

PACKAGE_NAME="python3-venv"

if dpkg -s "$PACKAGE_NAME" &> /dev/null; then
    echo "$PACKAGE_NAME is installed."
else
    echo "$PACKAGE_NAME is NOT installed."
    # Optional: Offer to install it
    read -p "Do you want to install $PACKAGE_NAME? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo "Installing $PACKAGE_NAME..."
        sudo apt update && sudo apt install -y "$PACKAGE_NAME"
        if [ $? -eq 0 ]; then
            echo "$PACKAGE_NAME installed successfully."
        else
            echo "Failed to install $PACKAGE_NAME."
            exit 1 # Exit with an error code if installation fails
        fi
    else
        echo "Skipping installation of $PACKAGE_NAME."
        exit 1 # Exit with an error code if user declines
    fi
fi

# You can proceed with other script logic here, knowing venv is available.
echo "Proceeding with script..."
python3 -m venv venv
echo "Virtual environment 'venv' created."
# activate virtualenv and install requirements
source venv/bin/activate
pip install --upgrade pip
pip install -e .
