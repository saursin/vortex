################################################################################
# Synopsys Design Compiler Script
################################################################################
# Build configurations
set output_dir  "output"
set report_dir  "report"

########################################
# Library Setup
set libpath     "$::env(HOME)/opt/pdk/freepdk-45nm"
set libname     "stdcells.db"

########################################
# Design Setup

set rtl_filelist    "sources.f"

set rtl_sources     {}
set rtl_incdirs     {}
set rtl_defines     {}
set blackbox_modules [list "VX_sp_ram" "VX_dp_ram"]

set top_module      "Vortex"
set clk_port        "clk"
set rst_port        "reset"

set clk_freq        100

########################################
# Synth Configuration

# Number of parallel jobs (set -1 for all cores)
set njobs 12

# Enable design flattening
set dc_flatten 0
set dc_flatten_effort "medium"

set max_fanout 32

# Gate Equivalent calculation
set NAND2_name      "NAND2_X1"


################################################################################
# Prepare
################################################################################
source "$::env(VORTEX_HOME)/hw/syn/freepdk45/util.tcl"

# Create directories
if {[file exists $output_dir] == 0} {
    file mkdir $output_dir
}
if {[file exists $report_dir] == 0} {
    file mkdir $report_dir
}

# Setup Libraries
set link_library [list $libpath/$libname]
set target_library [list $libpath/$libname]
set symbol_library ""
set search_path	[concat $search_path [list $libpath]]

# Design lib
define_design_lib WORK -path ./WORK

# Parse the RTL file list
set parse_flist_result [parse_filelist $rtl_filelist]
set flist_rtl_sources [lindex $parse_flist_result 0]
set flist_rtl_incdirs [lindex $parse_flist_result 1]
set flist_rtl_defines [lindex $parse_flist_result 2]

# Reorder the RTL sources to place package files first
set flist_rtl_sources [reorder_files_package_first $flist_rtl_sources]

# Append RTL sources from file list
set rtl_sources [concat $flist_rtl_sources]
# Append RTL include directories from file list
set rtl_incdirs [concat $flist_rtl_incdirs]
# Append RTL defines from file list
set rtl_defines [concat $flist_rtl_defines]


puts "======================================================"
# Print RTL defines
puts "RTL Defines:"
foreach define $rtl_defines {
    puts "  - $define"
}

# Print RTL includes
puts "RTL Include dirs:"
foreach dir $rtl_incdirs {
    puts "  - $dir"
}

# Print RTL sources
puts "RTL Sources:"
foreach file $rtl_sources {
    puts "  - $file"
}
puts "======================================================"


# Set number of parallel jobs
if { $njobs > 0 } {
    set_host_options -max_cores $njobs
}


################################################################################
# Read Design
################################################################################
# Add RTL include directory
set search_path [concat $search_path $rtl_incdirs]

# Read RTL files
analyze -format sverilog $rtl_sources -define $rtl_defines
elaborate $top_module

# Set blackbox atribute on modules          // FIXME: This is not working
if { [llength $blackbox_modules] > 0 } {
    foreach module $blackbox_modules {
        puts "Setting blackbox attribute for module $module"
        set_dont_touch "$module"
        # set_attribute [get_modules $module] blackbox true
    }
}

link

# Check for errors
if { [current_design] == "" } {
    puts "Error: undefined current design"
    exit 1
}


################################################################################
# Specify Constraints
################################################################################
# clock
set clk_period [expr 1000.0 / $clk_freq / 1.0]
create_clock -name "clk" \
             -period $clk_period \
             -waveform "0 [expr $clk_period/2]" \
             [get_ports $clk_port]

set_max_fanout $max_fanout [get_ports $clk_port]
set_ideal_network [get_ports $clk_port]

# reset
set_max_fanout $max_fanout [get_ports $rst_port]
set_false_path -from [get_ports $rst_port]

# # Set Blackboxes
# set_dont_touch "VX_sp_ram"
# set_dont_touch "VX_dp_ram"

# set_attribute [get_modules "VX_sp_ram"] dont_touch true
# set_attribute [get_modules "VX_dp_ram"] dont_touch true


################################################################################
# Synthesize
################################################################################
# Prevent assignment statements in the Verilog netlist.
set_fix_multiple_port_nets -all -buffer_constants

# Flatten the design if specified
if {$dc_flatten} {
   set_flatten true -effort $dc_flatten_effort
}

# Synthesize the design
check_design
compile_ultra -no_autoungroup
ungroup -all -flatten
uniquify

define_name_rules verilog -remove_internal_net_bus -remove_port_bus
change_names -rule verilog -hierarchy


################################################################################
# generate reports
################################################################################
# Timing
report_timing > ${report_dir}/${top_module}_timing.rpt
report_timing -path end  -delay max -max_paths 200 -cap -nets -nosplit > ${report_dir}/${top_module}_timing.max.rpt
report_timing -path end  -delay min -max_paths 200 -cap -nets -nosplit > ${report_dir}/${top_module}_timing.min.rpt
report_timing -path full -delay max -max_paths 50  -cap -nets -nosplit > ${report_dir}/${top_module}_timing.max.fullpath.rpt
report_timing -path full -delay min -max_paths 50  -cap -nets -nosplit > ${report_dir}/${top_module}_timing.min.fullpath.rpt

# Constraint violations
report_constraints -all_violators -verbose > ${report_dir}/${top_module}_constraints.rpt

# Area
report_area > ${report_dir}/${top_module}_area.rpt
report_area -physical -hier -nosplit > ${report_dir}/${top_module}_area.hier.rpt

# Power
report_power -hier -nosplit >  ${report_dir}/${top_module}_power.hier.rpt
report_power -verbose -nosplit >  ${report_dir}/${top_module}_power.rpt

# QOR
report_qor > ${report_dir}/${top_module}_qor.rpt

# Latches
query_objects -truncate 0 [all_registers -level_sensitive ] > ${report_dir}/${top_module}_latches.rpt

# High fanout nets
report_net_fanout -threshold 32 -nosplit > ${report_dir}/${top_module}_high_fanout.rpt

# Heirarchy
report_hierarchy > ${report_dir}/${top_module}_hierarchy.rpt

# Cell
report_cell > ${report_dir}/${top_module}_cell.rpt

# Reference
report_reference > ${report_dir}/${top_module}_reference.rpt

# Port
report_port > ${report_dir}/${top_module}_port.rpt

# Gate equivalent
if {[info exists $NAND2_name]} {
    set nand2_area [get_attribute [get_lib_cell $libname/$NAND2_name] area]
    puts "NAND2 Area: $nand2_area"
    redirect -variable area {report_area}
    regexp {Total cell area:\s+([^\n]+)\n} $area whole_match area
    set nand2_eq [expr $area/$nand2_area]
    set fp [open "${report_dir}/${top_module}_gate_equiv_area.rpt" w]
    puts $fp ""
    puts $fp "NAND2 equivalent cell area: $nand2_eq"
    close $fp
}

# Check for design errors
check_design > ${report_dir}/${top_module}_check_design.rpt


################################################################################
# Write output
################################################################################
# Post synthesis netlist
write -hierarchy -format verilog -output ${output_dir}/${top_module}.syn.v

# DB
write -h ${top_module} -output ${output_dir}/${top_module}.syn.db

# SDC
remove_ideal_network [get_ports $clk_port]
set_propagated_clock [get_ports $clk_port]
write_sdc -version 1.9 ${output_dir}/${top_module}.sdc

# SDF
write_sdf -context verilog -version 2.0 ${output_dir}/${top_module}.syn.sdf

# DDC
write_file -format ddc -output ${output_dir}/${top_module}.ddc

# Error/warning summary
print_message_info

exit 0
################################################################################