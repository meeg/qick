###############################################################################
# Functional constraints for axis_tprocv1 IP core
#
# These constraints apply when the IP is used within a larger design
# (e.g., integrated into a block design or top-level module).
# They provide timing guidance beyond what OOC synthesis defines.
#
# Clock/async definitions are in axis_tprocv1_ooc.xdc (out-of-context).
###############################################################################

#=============================================================================
# DMEM dual-clock BRAM constraints
#
# The dual-clock BRAM (bram_tdp) bridges s_axi_aclk (port A) to aclk (port B).
# Internally synchronized via CDC primitives; no additional timing needed.
# Mark the internal BRAM as a multi-cycle path to relax timing on the crossing.
#=============================================================================
set_multicycle_path 2 -hold -through [get_cells axis_tprocv1_i/dmem_i/xpm_mem*]
set_multicycle_path 2 -setup -through [get_cells axis_tprocv1_i/dmem_i/xpm_mem*]

#=============================================================================
# tProc FIFO dispatcher (per-channel, 16 x 216-bit)
#
# Each channel has an independent FIFO for timed instructions.
# Mark as multicycle (2) since FIFO depth absorption is > 1 cycle.
#=============================================================================
set_multicycle_path 2 -hold -through [get_cells *tproc_i/gen_channel*/fifo_time_i*]
set_multicycle_path 2 -setup -through [get_cells *tproc_i/gen_channel*/fifo_time_i*]

#=============================================================================
# AXIS handshake (tready/tvalid feedback loops)
#
# tready is a multi-cycle signal in streaming contexts. Allow 2 cycles
# for handshake propagation through FIFO logic and multiplexers.
#=============================================================================
set_multicycle_path 2 -hold -to [get_pins *axis*/tready]
set_multicycle_path 2 -setup -to [get_pins *axis*/tready]

#=============================================================================
# Optional: relax paths for debugging
#
# If timing is still tight after P&R, uncomment to relax non-critical paths:
#=============================================================================
# set_false_path -through [get_pins *tproc_i/regfile_i/*/dout*]
