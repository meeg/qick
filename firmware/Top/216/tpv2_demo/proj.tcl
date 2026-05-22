# Sourced by HOG via others.src after the project is created.
# DO NOT call create_project here — HOG already did it.

set origin_dir [file dirname [info script]]
if { [info exists ::origin_dir_loc] } {
  set origin_dir $::origin_dir_loc
}

# Source the Block Design TCL
source [file normalize "$origin_dir/bd_2023-1.tcl"]

# Generate the BD wrapper — Vivado writes it to the project .gen/ directory
make_wrapper -files [get_files d_1.bd] -top

# Add the wrapper from the Vivado-generated location (not from Top/)
set wrapper [get_files -of_objects [get_filesets sources_1] \
    -filter {NAME =~ "*/d_1/hdl/d_1_wrapper.v"}]
if {$wrapper eq ""} {
    set proj_dir  [get_property DIRECTORY [current_project]]
    set proj_name [get_property NAME      [current_project]]
    set wrapper_path [file normalize \
        "$proj_dir/${proj_name}.gen/sources_1/bd/d_1/hdl/d_1_wrapper.v"]
    add_files -norecurse -fileset [get_filesets sources_1] $wrapper_path
}

# Synthesis and implementation strategies
set_property strategy "Flow_PerfOptimized_high"   [get_runs synth_1]
set_property strategy "Performance_NetDelay_high" [get_runs impl_1]
