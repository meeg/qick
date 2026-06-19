"""
Driver for axis_constant_iq IP core.
Uses PeakRDL-generated register model.
"""
import sys
from pathlib import Path
from typing import Tuple
import numpy as np

# Buscar el paquete PeakRDL en múltiples ubicaciones
_RDL_PKG_PATHS = [
    Path(__file__).parent.parent / "rdl",                    # dev: fusesoc/cores/ip/.../rdl
    Path(__file__).parent.parent / "rdl_pkgs",               # prod: qick_lib/qick/rdl_pkgs
]

for _path in _RDL_PKG_PATHS:
    if (_path / "axis_constant_iq_regmap_pkg").exists():
        if str(_path) not in sys.path:
            sys.path.insert(0, str(_path))
        break

from axis_constant_iq_regmap_pkg.reg_model.axis_constant_iq import axis_constant_iq_cls
from axis_constant_iq_regmap_pkg.lib import NormalCallbackSet

from qick.ip import SocIP


def _to_unsigned(val: int, bits: int = 16) -> int:
    return val & ((1 << bits) - 1)

def _to_signed(val: int, bits: int = 16) -> int:
    half = 1 << (bits - 1)
    return val - (1 << bits) if val >= half else val


class AxisConstantIQ(SocIP):
    bindto = ['user.org:user:axis_constant_iq:1.0',
              'QICK:QICK:axis_constant_iq:1.0']
    HAS_MIXER = True
    MAXV = 2**15 - 2
    IQ_BITS = 16

    def __init__(self, description):
        super().__init__(description)
        self._reg_model = None

    def _init_config(self, description):
        self.cfg['maxv'] = self.MAXV
        self.cfg['has_mixer'] = self.HAS_MIXER
        super()._init_config(description)

    def configure_connections(self, soc):
        super().configure_connections(soc)
        self._callbacks = NormalCallbackSet(
            read_callback=self._hw_read,
            write_callback=self._hw_write
        )
        self._reg_model = axis_constant_iq_cls(
            callbacks=self._callbacks, address=0
        )

    def _hw_read(self, addr: int, width: int, accesswidth: int) -> int:
        return self.mmio.read(addr // 4)

    def _hw_write(self, addr: int, width: int, accesswidth: int, data: int) -> None:
        self.mmio.write(addr // 4, data)

    @property
    def regs(self):
        if self._reg_model is None:
            raise RuntimeError("Not configured")
        return self._reg_model

    def _init_firmware(self):
        self.regs.REAL_REG.I.write(_to_unsigned(self.MAXV, self.IQ_BITS))
        self.regs.IMAG_REG.Q.write(_to_unsigned(self.MAXV, self.IQ_BITS))
        self.update()

    def update(self):
        self.regs.WE_REG.WE.write(1)

    def set_iq(self, i=1.0, q=1.0):
        i_int = int(np.clip(i, -1, 1) * self.MAXV)
        q_int = int(np.clip(q, -1, 1) * self.MAXV)
        self.regs.REAL_REG.I.write(_to_unsigned(i_int, self.IQ_BITS))
        self.regs.IMAG_REG.Q.write(_to_unsigned(q_int, self.IQ_BITS))
        self.update()

    def get_iq(self) -> Tuple[float, float]:
        i_raw = _to_signed(self.regs.REAL_REG.I.read(), self.IQ_BITS)
        q_raw = _to_signed(self.regs.IMAG_REG.Q.read(), self.IQ_BITS)
        return (i_raw / self.MAXV, q_raw / self.MAXV)
