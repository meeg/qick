"""
Driver for axis_signal_gen_v6 IP core.
Uses PeakRDL-generated register model.
"""
import sys
from pathlib import Path
import numpy as np

_REGMAP_DIR = Path(__file__).parent.parent / "rdl"
if str(_REGMAP_DIR) not in sys.path:
    sys.path.insert(0, str(_REGMAP_DIR))

from axis_signal_gen_v6_regmap_pkg.reg_model.axis_signal_gen_v6 import axis_signal_gen_v6_cls
from axis_signal_gen_v6_regmap_pkg.lib import NormalCallbackSet
from axis_signal_gen_v6_regmap_pkg.sim.axis_signal_gen_v6 import axis_signal_gen_v6_simulator_cls

def to_unsigned(val, bits=16):
    return val & ((1 << bits) - 1)

def to_signed(val, bits=16):
    half = 1 << (bits - 1)
    return val - (1 << bits) if val >= half else val

class Axis_signal_gen_v6:
    """Driver for axis_signal_gen_v6 IP core."""
    
    def __init__(self):
        self._reg_model = None

    def configure(self, read_cb, write_cb):
        self._callbacks = NormalCallbackSet(
            read_callback=read_cb,
            write_callback=write_cb
        )
        self._reg_model = axis_signal_gen_v6_cls(
            callbacks=self._callbacks,
            address=0
        )

    @property
    def regs(self):
        return self._reg_model

    def create_test_model(self):
        sim = axis_signal_gen_v6_simulator_cls(address=0)
        return axis_signal_gen_v6_cls(
            callbacks=NormalCallbackSet(
                read_callback=sim.read,
                write_callback=sim.write
            ),
            address=0
        )
