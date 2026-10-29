# Run in a FRESH Vivado RTL project, with rtl/tb/verification/vectors together.
# Python has already generated the shipped full-profile golden vectors.
# Source this file, then run: pe_run_python

set pe_python_root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists pe_python_use_hsm]} {set pe_python_use_hsm 0}
if {[llength [get_projects -quiet]] == 0} {
    error "Create/open a fresh Vivado RTL project, then source this script."
}
if {$pe_python_use_hsm ni {0 1}} {error "pe_python_use_hsm must be 0 or 1"}
foreach source [lsort [glob -directory [file join $pe_python_root rtl] *.v]] {
    if {[llength [get_files -quiet $source]] == 0} {
        add_files -fileset sources_1 -norecurse $source
    }
}
set pe_python_tb [file join $pe_python_root tb systolic_pe_python_tb.sv]
if {[llength [get_files -quiet $pe_python_tb]] == 0} {
    add_files -fileset sim_1 -norecurse $pe_python_tb
}
set_property top systolic_pe_signed [get_filesets sources_1]
set_property top systolic_pe_python_tb [get_filesets sim_1]
set_property target_simulator XSim [current_project]
set_property xsim.elaborate.debug_level all [get_filesets sim_1]
set_property -name xsim.elaborate.xelab.more_options \
    -value [format {-generic_top "USE_HSM=%d"} $pe_python_use_hsm] -objects [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set_property xsim.simulate.no_quit true [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

proc pe_run_python {} {
    global pe_python_root
    set vectors [file join $pe_python_root vectors vectors.txt]
    set output [file join $pe_python_root results]
    file mkdir $output
    if {![file readable $vectors]} {
        error "Run python verification/generate_vectors.py --profile full from the package folder first."
    }
    catch {close_sim}
    foreach stale {rtl_results.csv simulation_status.txt comparison_summary.json comparison_report.txt frame_comparison.csv product_and_sum_comparison.csv} {
        file delete -force [file join $output $stale]
    }
    set options [format {-testplusarg "VECTORS=%s" -testplusarg "RESULTS=%s" -testplusarg "STATUS=%s"} \
        $vectors [file join $output rtl_results.csv] [file join $output simulation_status.txt]]
    set_property -name xsim.simulate.xsim.more_options -value $options -objects [get_filesets sim_1]
    launch_simulation -simset sim_1 -mode behavioral
    run all
    set status_path [file join $output simulation_status.txt]
    if {![file readable $status_path]} {error "Simulation did not write completion status. Inspect the simulator log."}
    set stream [open $status_path r]
    set status [string trim [read $stream]]
    close $stream
    if {![string match {PASS *} $status]} {error "Simulation did not pass: $status"}
    puts $status
    puts "Now run from the extracted package folder in PowerShell/Command Prompt:"
    puts "python verification/compare_results.py"
    puts "It compares RTL output with Python and writes results/comparison_report.txt and frame_comparison.csv."
}
puts "Python verification bench ready (USE_HSM=$pe_python_use_hsm). Run: pe_run_python"
