###############################################################################
# Out-of-context clock definitions for axis_tprocv1 IP synthesis.
#
# Two real clock domains:
#   s_axi_aclk : 100 MHz  (AXI-Lite config, DMEM port A, dmem arbiter)
#   aclk       : 250 MHz  (tProcessor core, DMEM port B, AXIS outputs)
#
# Dummy clocks (interface-only, not used in RTL):
#   s0_axis_aclk, m0_axis_aclk  — tie low or ignore
###############################################################################

#=============================================================================
# Real clock domains
#=============================================================================
create_clock -period 10.000 -name s_axi_aclk -waveform {0.000 5.000} [get_ports s_axi_aclk]
create_clock -period 4.000  -name aclk       -waveform {0.000 2.000} [get_ports aclk]

#=============================================================================
# Clock domain crossing (asynchronous domains)
#
# CDC is implemented via:
#   1. bram_tdp : dual-clock BRAM (port A: s_axi_aclk, port B: aclk)
#   2. cdc_gray_sync: start_src_reg, start_reg, start_input (all in aclk)
#
# Declaring the domains asynchronous covers all cross-domain paths.
#=============================================================================
set_clock_groups -asynchronous \
    -group [get_clocks -of_objects [get_ports s_axi_aclk]] \
    -group [get_clocks -of_objects [get_ports aclk]]

#=============================================================================
# False paths for unused AXIS clock ports (interface-only, not driven)
#
# s0_axis_aclk and m0_axis_aclk are declared in the interface but not
# actually used in the RTL. They appear in the IP because dmem uses
# axi4_stream_if for s0/m0, but the clock is s_axi_aclk internally.
# These ports should be tied to s_axi_aclk externally, but mark them
# as false paths to avoid timing violations on unconnected pins.
#=============================================================================
set_false_path -from [get_ports s0_axis_aclk]
set_false_path -from [get_ports m0_axis_aclk]

#=============================================================================
# Input constraints (s_axi_aclk domain)
#
# AXI4-Lite control signals — standard AXI timing.
# Relax by 2ns from clock edge to account for I/O + slave logic.
#=============================================================================
set_input_delay -clock s_axi_aclk -min 1.0 [get_ports s_axi_*]
set_input_delay -clock s_axi_aclk -max 3.0 [get_ports s_axi_*]
set_input_delay -clock s_axi_aclk -min 1.0 [get_ports start]
set_input_delay -clock s_axi_aclk -max 3.0 [get_ports start]

#=============================================================================
# Output constraints (s_axi_aclk domain)
#
# AXI4-Lite response signals — similar to inputs.
#=============================================================================
set_output_delay -clock s_axi_aclk -min 1.0 [get_ports s_axi_*]
set_output_delay -clock s_axi_aclk -max 3.0 [get_ports s_axi_*]

#=============================================================================
# Program memory read (asynchronous ROM interface)
#
# pmem_addr is synchronous to aclk (output).
# pmem_do is an async ROM read (no clock constraint, just path delay).
# 
# ROM access time: assume ~2ns (typical BRAM/ROM latency).
#=============================================================================
set_output_delay -clock aclk -min 0.5 [get_ports pmem_addr]
set_output_delay -clock aclk -max 2.5 [get_ports pmem_addr]

# pmem_do is an input from ROM (combinatorial path, no setup/hold on falling edge).
# False path for async read data.
set_false_path -to [get_ports pmem_do]

#=============================================================================
# Data Memory interface (port B, aclk domain)
#
# All signals driven by tprocv1 are synchronous to aclk.
#=============================================================================
set_output_delay -clock aclk -min 0.5 [get_ports dmem_we]
set_output_delay -clock aclk -max 2.5 [get_ports dmem_we]
set_output_delay -clock aclk -min 0.5 [get_ports dmem_addr]
set_output_delay -clock aclk -max 2.5 [get_ports dmem_addr]
set_output_delay -clock aclk -min 0.5 [get_ports dmem_di]
set_output_delay -clock aclk -max 2.5 [get_ports dmem_di]

# dmem_do is read by tprocv1 with 1-cycle latency from dual-clock BRAM.
# The BRAM handles the s_axi_aclk -> aclk crossing internally.
# No setup/hold constraint needed (BRAM guarantees it).
set_false_path -to [get_ports dmem_do]

#=============================================================================
# Slave AXIS inputs (s1..s4, aclk domain, 64-bit data)
#
# tprocv1 consumes these via axis_set_reg, which has 1-cycle latency.
# Relax constraints for high-frequency operation.
#=============================================================================
set_input_delay -clock aclk -min 0.5 [get_ports s1_axis_t* s2_axis_t* s3_axis_t* s4_axis_t*]
set_input_delay -clock aclk -max 2.5 [get_ports s1_axis_t* s2_axis_t* s3_axis_t* s4_axis_t*]

#=============================================================================
# Master AXIS outputs (m1..m8, aclk domain, 160-bit data)
#
# tprocv1 drives these via internal mux + timed dispatcher.
# Allow 2.5ns for mux + AXIS pipeline delay.
#=============================================================================
set_output_delay -clock aclk -min 0.5 [get_ports m1_axis_t* m2_axis_t* m3_axis_t* m4_axis_t* m5_axis_t* m6_axis_t* m7_axis_t* m8_axis_t*]
set_output_delay -clock aclk -max 2.5 [get_ports m1_axis_t* m2_axis_t* m3_axis_t* m4_axis_t* m5_axis_t* m6_axis_t* m7_axis_t* m8_axis_t*]

#=============================================================================
# s0/m0 AXIS (32-bit dmem read/write, s_axi_aclk domain)
#
# These are used by the dmem arbiter to burst read/write the data memory.
# Relax to allow flexibility in a streaming context.
#=============================================================================
set_input_delay -clock s_axi_aclk -min 0.5 [get_ports s0_axis_tdata s0_axis_tlast s0_axis_tvalid]
set_input_delay -clock s_axi_aclk -max 3.0 [get_ports s0_axis_tdata s0_axis_tlast s0_axis_tvalid]

set_output_delay -clock s_axi_aclk -min 0.5 [get_ports m0_axis_tdata m0_axis_tlast m0_axis_tvalid]
set_output_delay -clock s_axi_aclk -max 3.0 [get_ports m0_axis_tdata m0_axis_tlast m0_axis_tvalid]

#=============================================================================
# tready handshake paths (all domains)
#
# tready is asynchronous flow-control feedback. Mark as multi-cycle to
# account for FIFO fullness propagation.
#=============================================================================
set_multicycle_path 2 -hold -to [get_ports *_tready]
set_multicycle_path 2 -setup -to [get_ports *_tready]

#=============================================================================
# Reset signals (asynchronous, no timing constraints)
#=============================================================================
set_false_path -to [get_ports *aresetn]
