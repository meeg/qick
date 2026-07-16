#!/bin/bash
# gen_driver.sh - Generate a PYNQ DefaultIP driver for an IP core (if missing).
# Idempotent: never overwrites an existing driver.
# Usage: ./scripts/gen_driver.sh <ip_name>
set -e
IP_NAME=$1
[ -z "$IP_NAME" ] && { echo "Usage: $0 <ip_name>"; exit 1; }

IP_DIR="cores/ip/$IP_NAME"
DRIVER_FILE="$IP_DIR/driver/${IP_NAME}.py"
CLASS_NAME=$(echo "$IP_NAME" | sed -r 's/(^|_)([a-z])/\U\2/g')

mkdir -p "$IP_DIR/driver"

if [ -f "$DRIVER_FILE" ]; then
    echo "  driver ${IP_NAME}.py already exists — not overwriting"
    exit 0
fi

cat > "$DRIVER_FILE" << EOF
"""
PYNQ driver for ${IP_NAME} IP core.
Wraps the PeakRDL-generated register model over PYNQ MMIO.

Access registers via \`.regs\`, e.g.:
    ip = overlay.${IP_NAME}_0
    ip.regs.CTRL_REG.ENABLE.write(1)
"""
import sys
from pathlib import Path
from pynq import DefaultIP

_REGMAP_DIR = Path(__file__).parent.parent / "rdl"
if str(_REGMAP_DIR) not in sys.path:
    sys.path.insert(0, str(_REGMAP_DIR))

from ${IP_NAME}_regmap_pkg.reg_model.${IP_NAME} import ${IP_NAME}_cls
from ${IP_NAME}_regmap_pkg.lib import NormalCallbackSet


def to_unsigned(val, bits=16):
    return val & ((1 << bits) - 1)


def to_signed(val, bits=16):
    half = 1 << (bits - 1)
    return val - (1 << bits) if val >= half else val


class ${CLASS_NAME}(DefaultIP):
    """PYNQ driver for ${IP_NAME}. Register access through \`.regs\`."""

    bindto = ['qick:ip:${IP_NAME}:1.0']

    def __init__(self, description):
        super().__init__(description=description)
        self.regs = ${IP_NAME}_cls(
            callbacks=NormalCallbackSet(
                read_callback=self._reg_read,
                write_callback=self._reg_write,
            ),
            address=0,
        )

    def _reg_read(self, addr, **kwargs):
        return self.mmio.read(addr)

    def _reg_write(self, addr, data, **kwargs):
        self.mmio.write(addr, int(data) & 0xFFFFFFFF)

    # -- hand-written high-level methods below --
EOF
echo "  driver ${IP_NAME}.py created (PYNQ DefaultIP)"
