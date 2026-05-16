# Generate the HDL wrapper for the design and capture the generated filename
set wrapper_file [make_wrapper -files [get_files d_1.bd] -top]

# Add the generated wrapper file to the project
add_files $wrapper_file

# Update the project hierarchy to include the new wrapper file
update_compile_order -fileset sources_1


set_property strategy "Flow_PerfOptimized_high" [get_runs synth_1]
#set_property strategy "Flow_AlternateRoutability" [get_runs synth_1]

#set_property strategy "Performance_ExtraTimingOpt" [get_runs impl_1]
#set_property strategy "Performance_Explore" [get_runs impl_1]
#set_property strategy "Flow_RunPostRoutePhysOpt" [get_runs impl_1]
set_property strategy "Performance_NetDelay_high" [get_runs impl_1]
