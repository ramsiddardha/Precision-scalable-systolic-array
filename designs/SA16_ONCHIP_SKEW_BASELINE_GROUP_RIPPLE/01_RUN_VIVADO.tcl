# Vivado 2024.1. Use the Windows CMD launcher or source this file in Vivado.
set pe_root [file normalize [file dirname [info script]]]
set pe_batch_marker [file join $pe_root logs vivado_capture_completed.txt]
file delete -force $pe_batch_marker
source [file join $pe_root scripts setup_vivado.tcl]
source [file join $pe_root scripts capture_vcd.tcl]
set pe_variants {baseline group_ripple}
if {[info exists env(PE_VARIANT)] && $env(PE_VARIANT) ne ""} {
    if {$env(PE_VARIANT) ni $pe_variants} {error "Unknown PE_VARIANT: $env(PE_VARIANT)"}
    set pe_variants [list $env(PE_VARIANT)]
}
# Invalidate all requested captures before compilation. An interrupted run
# cannot leave an earlier PASS VCD under a requested variant.
foreach pe_variant $pe_variants {
    foreach pe_mode {int4 int8 int16} {
        set pe_output [file join $pe_root variants $pe_variant activity $pe_period_tag]
        file delete -force [file join $pe_output array_${pe_mode}.vcd] \
            [file join $pe_output array_${pe_mode}_runinfo.txt]
    }
}
foreach pe_variant $pe_variants {
    set pe_vcd_package_dir [file join $pe_root variants $pe_variant]
    set pe_vcd_output_dir [file join $pe_vcd_package_dir activity $pe_period_tag]
    file mkdir $pe_vcd_output_dir
    puts "===== $pe_variant ====="
    pe_compile_snapshots
    foreach pe_mode {0 1 2} {pe_run_vcd $pe_mode}
    catch {close_sim}
}
set pe_done "DONE: [expr {3 * [llength $pe_variants]}] checked on-chip-skew array VCD captures at $pe_clock_period_ns ns."
file mkdir [file dirname $pe_batch_marker]
set pe_marker_file [open $pe_batch_marker w]
puts $pe_marker_file $pe_done
close $pe_marker_file
puts $pe_done
