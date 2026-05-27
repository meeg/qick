#!/bin/bash
set -e

# Verificamos si el intérprete de Python puede cargar el módulo venv
if ! python3 -c "import venv" &> /dev/null; then
    echo "ERROR: Python 3 'venv' module is missing."
    echo "Please install the appropriate package for your distribution:"
    echo "  - Debian/Ubuntu: sudo apt install python3-venv"
    echo "  - RHEL/AlmaLinux: sudo dnf install python3-virtualenv (or python3-devel)"
    exit 1
fi

echo "Creating virtual environment..."
python3 -m venv venv

source venv/bin/activate
echo "Upgrading pip..."
pip install --upgrade pip

if [ -f "requirements.txt" ]; then
    echo "Installing requirements..."
    pip install -r requirements.txt
else
    echo "Warning: requirements.txt not found, skipping installation."
fi

echo "! Virtual environment ready"
