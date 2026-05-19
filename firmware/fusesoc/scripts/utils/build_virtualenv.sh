#!/bin/bash
set -e
PACKAGE_NAME="python3-venv"
if ! dpkg -s "$PACKAGE_NAME" &> /dev/null; then
    echo "ERROR: $PACKAGE_NAME is not installed. Run: sudo apt install python3-venv"
    exit 1
fi
echo "Creating virtual environment..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
echo "✓ Virtual environment ready"
