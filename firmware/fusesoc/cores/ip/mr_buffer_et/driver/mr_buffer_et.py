"""
QICK driver for mr_buffer_et IP core.
Uses the PeakRDL-generated register model. Register access via `.regs`, e.g.:
    ip = soc.mr_buffer_et_0
    ip.regs.CTRL_REG.ENABLE.write(1)
"""
import sys
from pathlib import Path

# Find the generated PeakRDL package in dev (next to driver) or prod (installed).
_RDL_PKG_PATHS = [
    Path(__file__).parent.parent / "rdl",        # dev: fusesoc/cores/ip/.../rdl
    Path(__file__).parent.parent / "rdl_pkgs",   # prod: qick_lib/qick/rdl_pkgs
]
for _path in _RDL_PKG_PATHS:
    if (_path / "mr_buffer_et_regmap_pkg").exists():
        if str(_path) not in sys.path:
            sys.path.insert(0, str(_path))
        break

from mr_buffer_et_regmap_pkg.reg_model import RegModel
from mr_buffer_et_regmap_pkg.lib import NormalCallbackSet
from qick.ip import SocIP


def _to_unsigned(val, bits=16):
    return val & ((1 << bits) - 1)


def _to_signed(val, bits=16):
    half = 1 << (bits - 1)
    return val - (1 << bits) if val >= half else val


class MrBufferEt(SocIP):
    """QICK driver for mr_buffer_et. Register access through `.regs`."""
    bindto = ['qick:ip:mr_buffer_et:1.2']

    def configure_connections(self, soc):
        super().configure_connections(soc)
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
        return self._reg_model

    # -- hand-written high-level methods below --
