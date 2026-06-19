# PeakRDL Driver Generation

This document describes how to generate Python drivers for QICK IP cores
using [PeakRDL](https://peakrdl.readthedocs.io) and SystemRDL.

## Overview

PeakRDL enables a **single source of truth** approach where you define your
IP's register map once in a `.rdl` file and automatically generate:

- **SystemVerilog**: AXI4-Lite slave module (`peakrdl regblock`)
- **Python**: Type-safe register package (`peakrdl python`)
- **QICK Driver**: Python class that inherits from `SocIP`
- **HTML Documentation**: Register map docs (`peakrdl html`)

```
cores/ip/<ip_name>/
├── rdl/
│   ├── <ip_name>_regmap.rdl          ← SOURCE OF TRUTH (you edit this)
│   ├── <ip_name>_regmap.core
│   ├── Makefile
│   ├── <ip_name>_regmap_pkg/         ← Generated Python package
│   └── docs/                         ← Generated HTML docs
├── driver/
│   └── <ip_name>.py                  ← QICK driver (symlinked to qick_lib/)
├── hdl/
│   └── <ip_name>.sv
└── test/
    └── <ip_name>_tc00.sv
```

## How It Works on the RFSoC Board

When you run `make driver`, three things happen:

1. The generated PeakRDL package is **copied** to `qick_lib/qick/rdl_pkgs/`
2. The driver is **symlinked** to `qick_lib/qick/drivers/`
3. HTML documentation is **generated** in `cores/ip/<ip_name>/rdl/docs/`

The driver searches for the PeakRDL package in multiple locations:

```python
_RDL_PKG_PATHS = [
    Path(__file__).parent.parent / "rdl",        # dev: next to driver
    Path(__file__).parent.parent / "rdl_pkgs",   # prod: installed with QICK
]
```

This means it works both:
- **In development**: finds the package in `fusesoc/cores/ip/.../rdl/`
- **On the RFSoC board**: finds the package in `qick/rdl_pkgs/`

## Prerequisites

Install PeakRDL and its plugins:

```bash
cd firmware/fusesoc
source venv/bin/activate

pip install peakrdl-regblock
pip install peakrdl-python
pip install peakrdl-html
```

Verify installation:

```bash
python3 -c "
from systemrdl import RDLCompiler; print('✓ systemrdl')
from peakrdl_regblock import RegblockExporter; print('✓ peakrdl_regblock')
from peakrdl_python import PythonExporter; print('✓ peakrdl_python')
from peakrdl_html import HTMLExporter; print('✓ peakrdl_html')
"
```

## Quick Start

### For an existing IP

```bash
cd firmware/fusesoc
source venv/bin/activate

# Generate everything (RDL → SystemVerilog + Python + QICK symlink + rdl_pkgs copy)
make driver IP=axis_constant_iq

# Generate HTML documentation
make rdl-docs IP=axis_constant_iq

# Simulate
make sim IP=axis_constant_iq
```

### Creating a new IP with PeakRDL

```bash
cd firmware/fusesoc

# Create IP structure from template
make new-ip IP=my_new_ip

# Edit the RDL to define your registers
vim cores/ip/my_new_ip/rdl/my_new_ip_regmap.rdl

# Generate everything
make driver IP=my_new_ip

# Generate docs
make rdl-docs IP=my_new_ip
```

## SystemRDL File Format

The `.rdl` file is the single source of truth for your IP's registers.

**Example: `axis_constant_iq_regmap.rdl`**

```systemrdl
addrmap axis_constant_iq {
    name = "AXIS Constant IQ Registers";
    desc = "Registers for the axis_constant_iq IP core.";

    default regwidth = 32;
    default accesswidth = 32;
    default addressing = compact;

    // 0x00: REAL_REG - I component
    reg {
        name = "REAL_REG";
        desc = "16-bit I (real) component of the constant output.";
        field {
            name = "I";
            desc = "In-phase component";
            sw = rw;
            hw = r;
        } I[15:0] = 0;
    } REAL_REG @0x00;

    // 0x04: IMAG_REG - Q component
    reg {
        name = "IMAG_REG";
        desc = "16-bit Q (imaginary) component of the constant output.";
        field {
            name = "Q";
            desc = "Quadrature component";
            sw = rw;
            hw = r;
        } Q[15:0] = 0;
    } IMAG_REG @0x04;

    // 0x08: WE_REG - Write-enable strobe
    reg {
        name = "WE_REG";
        desc = "Write-enable strobe. Writing 1 triggers an IQ update.";
        field {
            name = "WE";
            desc = "Write Enable. Self-clearing pulse.";
            sw = rw;
            hw = r;
            swmod;  // Hardware generates single-cycle pulse on write
        } WE[0:0] = 0;
    } WE_REG @0x08;
};
```

### Common RDL Patterns

**Signed fields (16-bit):**

```systemrdl
field {
    sw = rw;
    hw = r;
} I[15:0] = 0;
```

> **Note**: PeakRDL-python validates fields as unsigned by default. Use
> `_to_unsigned()` / `_to_signed()` helpers in your driver for signed values.

**Self-clearing strobe:**

```systemrdl
field {
    swmod;  // Single-cycle pulse on write
} WE[0:0] = 0;
```

**Read-only status with write-clear:**

```systemrdl
field {
    sw = rw;
    hw = w;
    swmod;
    onwrite = woclr;
} IRQ_FLAG[7:0];
```

**Counter with read-clear:**

```systemrdl
field {
    sw = r;
    hw = r;
    counter;
    onread = rclr;
} COUNTER[31:0];
```

**Arrays of registers:**

```systemrdl
reg {
    field { sw = rw; hw = r; } DATA[31:0];
} CHANNEL[4] @0x10;  // Creates CHANNEL[0] through CHANNEL[3]
```

## Generating HTML Documentation

You can generate HTML register documentation from your `.rdl` file:

```bash
# From the project root
make rdl-docs IP=axis_constant_iq

# Or directly from the IP's rdl directory
cd cores/ip/axis_constant_iq/rdl
make docs
```

This generates in `cores/ip/<ip_name>/rdl/docs/`:

```
docs/
├── index.html              ← Full register map
├── registers/
│   ├── REAL_REG.html       ← Per-register details
│   ├── IMAG_REG.html
│   └── WE_REG.html
└── fields/
    ├── I.html              ← Per-field details
    ├── Q.html
    └── WE.html
```

Open in your browser:

```bash
firefox cores/ip/axis_constant_iq/rdl/docs/index.html
```

Each page shows:
- Register name, description, and address offset
- Field bit positions and access rights (rw/r/w)
- Default values and special properties (swmod, counter, sticky, etc.)
- Enumerations if defined in the RDL

## Generated Python Package

After running `make driver`, PeakRDL generates a Python package:

```
<ip_name>_regmap_pkg/
├── reg_model/
│   └── <ip_name>.py          ← Register model class
├── lib/
│   ├── base.py               ← Base classes
│   ├── base_field.py
│   └── register_and_field.py
├── sim/
│   └── <ip_name>.py          ← Simulator (no hardware needed)
└── example.py                ← Usage example
```

### Generated API

```python
from <ip_name>_regmap_pkg.reg_model.<ip_name> import <ip_name>_cls
from <ip_name>_regmap_pkg.lib import NormalCallbackSet
from <ip_name>_regmap_pkg.sim.<ip_name> import <ip_name>_simulator_cls

# Create model with simulator
sim = <ip_name>_simulator_cls(address=0)
model = <ip_name>_cls(
    callbacks=NormalCallbackSet(
        read_callback=sim.read,
        write_callback=sim.write
    ),
    address=0
)

# Register access API
model.REAL_REG.I.write(100)       # Write field
model.REAL_REG.I.read()           # Read field → 100
model.REAL_REG.write(200)         # Write full register
model.REAL_REG.read()             # Read full register → 200
model.WE_REG.WE.write(1)          # Write strobe (swmod)

# Register properties
model.REAL_REG.address             # → 0x00
model.REAL_REG.width               # → 32
model.REAL_REG.I.high              # → 15
model.REAL_REG.I.low               # → 0

# Iterate over registers and fields
for reg in model:
    print(f"{reg.rdl_name} @ 0x{reg.address:02X}")
    for field in reg:
        print(f"  {field.rdl_name} [{field.high}:{field.low}]")
```

## Writing the QICK Driver

The driver lives in `cores/ip/<ip_name>/driver/<ip_name>.py` and is symlinked
to `qick_lib/qick/drivers/` for QICK import.

### Driver Template

```python
import sys
from pathlib import Path
from typing import Tuple
import numpy as np

# Multi-path search for PeakRDL package (dev + prod)
_RDL_PKG_PATHS = [
    Path(__file__).parent.parent / "rdl",        # dev: fusesoc/cores/ip/.../rdl
    Path(__file__).parent.parent / "rdl_pkgs",   # prod: qick_lib/qick/rdl_pkgs
]

for _path in _RDL_PKG_PATHS:
    if (_path / "<ip_name>_regmap_pkg").exists():
        if str(_path) not in sys.path:
            sys.path.insert(0, str(_path))
        break

from <ip_name>_regmap_pkg.reg_model.<ip_name> import <ip_name>_cls
from <ip_name>_regmap_pkg.lib import NormalCallbackSet
from qick.ip import SocIP


def _to_unsigned(val: int, bits: int = 16) -> int:
    """Convert signed to unsigned for hardware write."""
    return val & ((1 << bits) - 1)


def _to_signed(val: int, bits: int = 16) -> int:
    """Convert unsigned to signed after hardware read."""
    half = 1 << (bits - 1)
    return val - (1 << bits) if val >= half else val


class MyIP(SocIP):
    bindto = ['user.org:user:<ip_name>:1.0']
    MAXV = 2**15 - 2

    def __init__(self, description):
        super().__init__(description)
        self._reg_model = None

    def configure_connections(self, soc):
        super().configure_connections(soc)
        self._callbacks = NormalCallbackSet(
            read_callback=self._hw_read,
            write_callback=self._hw_write
        )
        self._reg_model = <ip_name>_cls(
            callbacks=self._callbacks, address=0
        )

    def _hw_read(self, addr, width, accesswidth):
        return self.mmio.read(addr // 4)

    def _hw_write(self, addr, width, accesswidth, data):
        self.mmio.write(addr // 4, data)

    @property
    def regs(self):
        return self._reg_model

    def _init_firmware(self):
        # Initialize registers here
        pass
```

### Driver Example: `AxisConstantIQ`

```python
class AxisConstantIQ(SocIP):
    bindto = ['user.org:user:axis_constant_iq:1.0']
    HAS_MIXER = True
    MAXV = 2**15 - 2
    IQ_BITS = 16

    def set_iq(self, i=1.0, q=1.0):
        i_int = int(np.clip(i, -1, 1) * self.MAXV)
        q_int = int(np.clip(q, -1, 1) * self.MAXV)
        self.regs.REAL_REG.I.write(_to_unsigned(i_int, self.IQ_BITS))
        self.regs.IMAG_REG.Q.write(_to_unsigned(q_int, self.IQ_BITS))
        self.regs.WE_REG.WE.write(1)

    def get_iq(self) -> Tuple[float, float]:
        i_raw = _to_signed(self.regs.REAL_REG.I.read(), self.IQ_BITS)
        q_raw = _to_signed(self.regs.IMAG_REG.Q.read(), self.IQ_BITS)
        return (i_raw / self.MAXV, q_raw / self.MAXV)
```

## Testing Without Hardware

You can test your driver without an RFSoC board using the generated simulator:

```python
import sys
from pathlib import Path

sys.path.insert(0, 'rdl')

from <ip_name>_regmap_pkg.reg_model.<ip_name> import <ip_name>_cls
from <ip_name>_regmap_pkg.lib import NormalCallbackSet
from <ip_name>_regmap_pkg.sim.<ip_name> import <ip_name>_simulator_cls

# Create model with simulator
sim = <ip_name>_simulator_cls(address=0)
model = <ip_name>_cls(
    callbacks=NormalCallbackSet(
        read_callback=sim.read,
        write_callback=sim.write
    ),
    address=0
)

# Test your registers
model.REAL_REG.I.write(100)
assert model.REAL_REG.I.read() == 100
print("✓ Test passed")
```

Or run the generated example:

```bash
cd cores/ip/<ip_name>/rdl/<ip_name>_regmap_pkg
python3 example.py
```

## Makefile Targets

| Command | Description |
|---------|-------------|
| `make driver IP=<name>` | Generate RDL + QICK symlink + copy rdl_pkgs |
| `make gen IP=<name>` | Generate RDL only (no symlink, no copy) |
| `make rdl-docs IP=<name>` | Generate HTML documentation from RDL |
| `make docs IP=<name>` | Generate HTML docs (same as above) |
| `make sim IP=<name>` | Generate + simulate |
| `make new-ip IP=<name>` | Create new IP from template |
| `make driver-all` | Generate all IPs |

## Installation on RFSoC Board

When you install QICK on the board, the PeakRDL packages must be included:

```bash
# On development machine
cd ~/git/qick_internal
make driver-all   # Generates and copies all rdl_pkgs

# On the RFSoC board
cd ~/git/qick_internal
pip install -e qick_lib/
# or
cp -r qick_lib/qick /usr/local/lib/python3.*/site-packages/
```

The installed structure on the board:

```
qick/
├── drivers/
│   └── axis_constant_iq.py       ← Driver
├── rdl_pkgs/
│   └── axis_constant_iq_regmap_pkg/  ← PeakRDL package
├── ip.py
└── ...
```

The driver finds `rdl_pkgs/` because it's at `Path(__file__).parent.parent / "rdl_pkgs"`:

```
qick/drivers/axis_constant_iq.py   ← __file__
qick/rdl_pkgs/                     ← Path(__file__).parent.parent / "rdl_pkgs"
```

## Signed vs Unsigned Fields

PeakRDL-python validates fields as unsigned by default. For signed 16-bit
fields (e.g., IQ values), use the helper functions:

```python
def _to_unsigned(val, bits=16):
    """Convert signed to unsigned for register write."""
    return val & ((1 << bits) - 1)

def _to_signed(val, bits=16):
    """Convert unsigned to signed after register read."""
    half = 1 << (bits - 1)
    return val - (1 << bits) if val >= half else val
```

**Why?** Your hardware uses two's complement (signed 16-bit: -32768 to 32767),
but PeakRDL-python validates as unsigned (0 to 65535). These helpers convert
between the two representations.

## Files to Version Control

Commit these files:

```
cores/ip/<ip_name>/
├── rdl/
│   ├── <ip_name>_regmap.rdl       ← YES: source of truth
│   ├── <ip_name>_regmap.core      ← YES
│   └── Makefile                   ← YES
├── driver/
│   └── <ip_name>.py               ← YES: driver code
└── <ip_name>.core                 ← YES
```

Add to `.gitignore`:

```gitignore
# Generated by PeakRDL - DO NOT COMMIT
*_regmap_pkg/
*_regmap.sv
*_regmap_pkg.sv
*_regmap.svh
docs/
*.pyc
__pycache__/
```

The `qick_lib/qick/rdl_pkgs/` directory contains generated packages that are
copied during `make driver`. Add it to `qick_lib/.gitignore`:

```gitignore
qick/rdl_pkgs/
```

## Troubleshooting

**`ModuleNotFoundError: No module named 'qick'`**

Add QICK to your Python path:
```bash
export PYTHONPATH=$PYTHONPATH:~/git/qick_internal/qick_lib
```

**`ModuleNotFoundError: No module named '<ip>_regmap_pkg'`**

The PeakRDL package wasn't generated or copied. Run:
```bash
make driver IP=<ip_name>
```

**`ValueError: value to be written to register must be greater than or equal to 0`**

You're writing a negative value to an unsigned field. Use `_to_unsigned()`:
```python
model.REAL_REG.I.write(_to_unsigned(-100))  # OK
```

**Generated files not updating**

Clean and regenerate:
```bash
cd cores/ip/<ip_name>/rdl && make clean && make gen
```

**Driver works in dev but not on the board**

The `rdl_pkgs` directory may not have been deployed. Re-run `make driver` and
reinstall QICK on the board.
