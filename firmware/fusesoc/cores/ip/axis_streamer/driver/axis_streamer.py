"""
PYNQ driver for axis_streamer IP core.
Wraps the PeakRDL-generated register model over PYNQ MMIO.

AUTO-GENERATED placeholder. Access registers via `.regs`, e.g.:
    ip = overlay.axis_streamer_0
    ip.regs.CTRL_REG.ENABLE.write(1)
Add high-level convenience methods below the marker; this file is only
generated once and never overwritten by the generator.
"""
import sys
from pathlib import Path
from pynq import DefaultIP

_REGMAP_DIR = Path(__file__).parent.parent / "rdl"
if str(_REGMAP_DIR) not in sys.path:
    sys.path.insert(0, str(_REGMAP_DIR))

from axis_streamer_regmap_pkg.reg_model.axis_streamer import axis_streamer_cls
from axis_streamer_regmap_pkg.lib import NormalCallbackSet


def to_unsigned(val, bits=16):
    return val & ((1 << bits) - 1)


def to_signed(val, bits=16):
    half = 1 << (bits - 1)
    return val - (1 << bits) if val >= half else val


class AxisStreamer(DefaultIP):
    """PYNQ driver for axis_streamer. Register access through `.regs`."""

    bindto = ['qick:ip:axis_streamer:1.0']

    def __init__(self, description):
        super().__init__(description=description)
        self.regs = axis_streamer_cls(
            callbacks=NormalCallbackSet(
                read_callback=self._reg_read,
                write_callback=self._reg_write,
            ),
            address=0,
        )

    # PeakRDL invokes these with keyword args (addr, width, accesswidth, data)
    def _reg_read(self, addr, **kwargs):
        return self.mmio.read(addr)

    def _reg_write(self, addr, data, **kwargs):
        self.mmio.write(addr, int(data) & 0xFFFFFFFF)

    # ── hand-written high-level methods below ──────────────────────────
