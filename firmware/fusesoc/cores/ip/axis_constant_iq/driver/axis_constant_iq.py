"""
QICK driver for axis_constant_iq IP core.
Uses the PeakRDL-generated register model. Register access via `.regs`, e.g.:
    ip = soc.axis_constant_iq_0
    ip.regs.CTRL_REG.ENABLE.write(1)

Works with both a raw PYNQ Overlay and QickSoc: the register model is built in
_init_firmware() (always called from SocIP.__init__, needs only self.mmio).
configure_connections() is reserved for soc-dependent wiring (revision/version, peers).
"""
import sys
from pathlib import Path
# Find the generated PeakRDL package in dev (next to driver) or prod (installed).
_RDL_PKG_PATHS = [
    Path(__file__).parent.parent / "rdl",        # dev: fusesoc/cores/ip/.../rdl
    Path(__file__).parent.parent / "rdl_pkgs",   # prod: qick_lib/qick/rdl_pkgs
]
for _path in _RDL_PKG_PATHS:
    if (_path / "axis_constant_iq_regmap_pkg").exists():
        if str(_path) not in sys.path:
            sys.path.insert(0, str(_path))
        break

from axis_constant_iq_regmap_pkg.reg_model import RegModel
from axis_constant_iq_regmap_pkg.lib import NormalCallbackSet
from qick.ip import SocIP


def _to_unsigned(val, bits=16):
    return val & ((1 << bits) - 1)


def _to_signed(val, bits=16):
    half = 1 << (bits - 1)
    return val - (1 << bits) if val >= half else val


class AxisConstantIq(SocIP):
    """QICK driver for axis_constant_iq. Register access through `.regs`."""
    bindto = ['qick:ip:axis_constant_iq:1.0']

    def _init_firmware(self):
        # Called from SocIP.__init__ for BOTH raw Overlay and QickSoc.
        # Only needs self.mmio (already set by DefaultIP.__init__).
        super()._init_firmware()
        self._reg_model = RegModel(
            callbacks=NormalCallbackSet(
                read_callback=self._hw_read,
                write_callback=self._hw_write,
                read_block_callback=self._hw_read_block,
                write_block_callback=self._hw_write_block,
            )
        )

    def _hw_read(self, addr, width, accesswidth):
        return self.mmio.read(addr)

    def _hw_write(self, addr, width, accesswidth, data):
        self.mmio.write(addr, int(data) & 0xFFFFFFFF)

    def _hw_read_block(self, addr, width, accesswidth, length):
        return [self.mmio.read(addr + 4*i) for i in range(length)]

    def _hw_write_block(self, addr, width, accesswidth, data):
        for i, d in enumerate(data):
            self.mmio.write(addr + 4*i, int(d) & 0xFFFFFFFF)

    @property
    def regs(self):
        if self._reg_model is None:
            raise RuntimeError(
                "AxisConstantIq: register model not initialized "
                "(expected _init_firmware to run in __init__)"
            )
        return self._reg_model

    # -- hand-written high-level methods below --
