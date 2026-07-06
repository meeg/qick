import pytest
from axis_signal_gen_v4_regmap_pkg.reg_model import RegModel
from axis_signal_gen_v4_regmap_pkg.sim import Simulator
from axis_signal_gen_v4_regmap_pkg.lib import NormalCallbackSet


def make_sim_regs():
    """Register model backed by the in-memory simulator (no hardware)."""
    sim = Simulator(address=0)
    return RegModel(
        callbacks=NormalCallbackSet(
            read_callback=sim.read,
            write_callback=sim.write,
            read_block_callback=sim.read_block,
            write_block_callback=sim.write_block,
        )
    )


@pytest.fixture
def regs():
    return make_sim_regs()


def test_reset_values(regs):
    assert regs.START_ADDR_REG.START_ADDR.read() == 0
    assert regs.WE_REG.WE.read() == 0
    assert regs.STATUS_REG.SATURATING.read() == 0
    assert regs.CTRL_REG.SAT_CLEAR.read() == 0
    assert regs.OUTSEL_REG.OUTSEL.read() == 0        # v4-only, resets to real


def test_register_offsets(regs):
    # Opción B: STATUS/CTRL match v6; OUTSEL appended at 0x14.
    assert regs.START_ADDR_REG.address == 0x00
    assert regs.WE_REG.address         == 0x04
    assert regs.RNDQ_REG.address       == 0x08
    assert regs.STATUS_REG.address     == 0x0C
    assert regs.CTRL_REG.address       == 0x10
    assert regs.OUTSEL_REG.address     == 0x14


def test_start_addr_roundtrip(regs):
    regs.START_ADDR_REG.START_ADDR.write(0x1234)
    assert regs.START_ADDR_REG.START_ADDR.read() == 0x1234


def test_load_sequence(regs):
    # Mirrors driver.load(): _wr_enable(addr) -> <DMA> -> _wr_disable()
    addr = 0x40
    regs.START_ADDR_REG.START_ADDR.write(addr)
    regs.WE_REG.WE.write(1)
    assert regs.START_ADDR_REG.START_ADDR.read() == addr
    assert regs.WE_REG.WE.read() == 1
    regs.WE_REG.WE.write(0)          # _wr_disable
    assert regs.WE_REG.WE.read() == 0


def test_saturation_clear_sequence(regs):
    # SATURATING is HW-set (0 in the pure-register sim); exercise the SW path.
    assert regs.STATUS_REG.SATURATING.read() == 0
    regs.CTRL_REG.SAT_CLEAR.write(1)
    assert regs.CTRL_REG.SAT_CLEAR.read() == 1
    regs.CTRL_REG.SAT_CLEAR.write(0)
    assert regs.CTRL_REG.SAT_CLEAR.read() == 0


def test_outsel_roundtrip(regs):
    # v4-only static real/imag select.
    assert regs.OUTSEL_REG.OUTSEL.read() == 0        # real
    regs.OUTSEL_REG.OUTSEL.write(1)                  # imag
    assert regs.OUTSEL_REG.OUTSEL.read() == 1
    regs.OUTSEL_REG.OUTSEL.write(0)
    assert regs.OUTSEL_REG.OUTSEL.read() == 0


def test_rndq_dummy_roundtrip(regs):
    # Deprecated but retained for bindto compat: must still read/write back.
    regs.RNDQ_REG.RNDQ.write(0xDEADBEEF)
    assert regs.RNDQ_REG.RNDQ.read() == 0xDEADBEEF


def test_register_independence(regs):
    regs.START_ADDR_REG.START_ADDR.write(0xABCD)
    regs.WE_REG.WE.write(1)
    regs.CTRL_REG.SAT_CLEAR.write(1)
    regs.OUTSEL_REG.OUTSEL.write(1)
    assert regs.START_ADDR_REG.START_ADDR.read() == 0xABCD
    assert regs.WE_REG.WE.read() == 1
    assert regs.CTRL_REG.SAT_CLEAR.read() == 1
    assert regs.OUTSEL_REG.OUTSEL.read() == 1
