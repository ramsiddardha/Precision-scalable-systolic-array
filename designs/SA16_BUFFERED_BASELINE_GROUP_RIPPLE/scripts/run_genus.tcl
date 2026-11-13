# Genus Common UI. Run one synthesis or one VCD power analysis per process.
proc pe_text {path} {
    set f [open $path r]
    set status [catch {read $f} result options]
    close $f
    if {$status} {return -options $options $result}
    return $result
}

proc pe_record {path text} {
    set f [open $path w]
    set status [catch {puts $f $text} result options]
    close $f
    if {$status} {return -options $options $result}
}

proc pe_main {} {
    global env
    set root [file normalize [file join [file dirname [info script]] ..]]
    set lib [file normalize $env(PE_LIB_FILE)]
    set top systolic_array_power_top
    set stage $env(PE_STAGE)
    set variant $env(PE_VARIANT)
    set marker [file join [pwd] COMPLETED.txt]
    file delete -force $marker
    set_db init_lib_search_path [list [file dirname $lib]]
    set_db library [list $lib]
    set_db information_level 2

    if {$stage eq "synth"} {
        set rtl [file join $root variants $variant rtl]
        set sources [lsort [glob -nocomplain -directory $rtl *.v]]
        if {[llength $sources] != 25} {error "Expected 25 RTL sources for $variant"}
        set_db init_hdl_search_path [list $rtl]
        set_db lp_insert_clock_gating false
        read_hdl -sv $sources
        elaborate $top
        check_design -unresolved > unresolved.rpt
        check_design -all > design_checks.rpt
        read_sdc $env(PE_SDC)
        if {[llength [info commands check_timing_intent]]} {
            check_timing_intent > constraints_lint.rpt
        } else {
            pe_record constraints_lint.rpt "Skipped because check_timing_intent is unavailable."
        }

        set uncertainty [format %.3f [expr {0.100 + $env(PE_SETUP_MARGIN_PS)/1000.0}]]
        set_clock_uncertainty -setup $uncertainty [get_clocks clk]
        write_sdc > optimization_constraints.sdc
        syn_generic
        syn_map
        syn_opt
        report_timing > timing_optimization_target.rpt
        set_clock_uncertainty -setup 0.100 [get_clocks clk]
        report_timing > timing.rpt
        report_area > area.rpt
        report_gates > gates.rpt
        report_hierarchy > hierarchy.rpt
        write_hdl > mapped.v
        write_sdc > mapped.sdc
        write_db -to_file [file join [pwd] final.db]
        set native [file join [pwd] fv $top fv_map.map.do]
        if {![file isfile $native] || [file size $native] == 0} {
            error "Genus did not write its native RTL-to-gate map: $native"
        }
        file copy -force $native state.map.do
        pe_record conditions.txt "Buffered array $variant\nLibrary: $lib\nClock period: $env(PE_PERIOD) ns\nOptimization setup uncertainty: $uncertainty ns\nNominal setup uncertainty: 0.100 ns"
    } elseif {$stage eq "power"} {
        set mapped [file normalize $env(PE_MAPPED_DIR)]
        read_db [file join $mapped final.db]
        set_db lp_power_analysis_effort medium
        set map [file join $mapped state.map.do]
        if {$env(PE_POWER_METHOD) eq "time_based"} {
            set_db lp_enable_jls_sdb_flow 1
            set_rtl_stim_to_gate_config -map_file $map genus -golden rtl
            read_stimulus -file $env(PE_VCD_FILE) -dut_instance /block_tb/dut \
                -interval_size ${env(PE_PERIOD)}ns -start $env(PE_START) -end $env(PE_END) \
                -frame_count $env(PE_CYCLES)
            set stim /stim#1
            set frames {}
            for {set frame 1} {$frame <= $env(PE_CYCLES)} {incr frame} {
                lappend frames $stim/frame#$frame
            }
            set observed [get_sdb_frames -stims $stim]
            set physical [lsearch -all -inline -not -exact $observed $stim/frame#0]
            if {[lsort -dictionary $physical] ne $frames} {
                error "Expected $env(PE_CYCLES) physical frames; loaded [llength $physical]"
            }
            puts "TIME-BASED COVERAGE: $env(PE_CYCLES) physical frames"
        } else {
            set status [rtlstim2gate -map_file $map genus -golden rtl]
            puts "Native map import returned: $status"
            read_vcd -static -vcd_scope block_tb/dut $env(PE_VCD_FILE)
        }
        report_sdb_annotation > activity.rpt
        set annotation [pe_text activity.rpt]
        foreach {kind expected is_input} [list Inputs 39 1 Flop $env(PE_EXPECTED_FF) 0 Latch $env(PE_EXPECTED_LATCH) 0] {
            set pattern [format {^\s*%s\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)} $kind]
            if {![regexp -line $pattern $annotation whole asserted unasserted unconnected total] ||
                $unasserted != 0 || $asserted + $unconnected != $total ||
                ($is_input && $total != $expected) ||
                (!$is_input && $asserted < $expected)} {
                error "Incomplete $kind activity annotation. Inspect [file join [pwd] activity.rpt]"
            }
        }
        if {$env(PE_POWER_METHOD) eq "time_based"} {
            propagate_activity -mode time_based -force -stim $stim
            compute_power -mode time_based -skip_propagation -stim $stim
            report_power -stims $stim -frames $frames -collate frames -by_category -unit mW > power.rpt
            puts "TIME-BASED COMPLETE: $env(PE_MODE)"
        } else {
            report_power > power.rpt
            report_sdb_annotation > activity_after_power.rpt
        }
        pe_record conditions.txt "Buffered array $variant\nLibrary: $lib\nVCD: $env(PE_VCD_FILE)\nMode: $env(PE_MODE)\nMethod: $env(PE_POWER_METHOD)"
    } else {
        error "PE_STAGE must be synth or power"
    }
    pe_record $marker "COMPLETED $variant $stage"
    puts "COMPLETED $variant $stage"
}

if {[catch {pe_main} message options]} {
    puts stderr "PE COMPARISON ERROR: $message"
    if {[dict exists $options -errorinfo]} {puts stderr [dict get $options -errorinfo]}
    exit 1
}
exit 0
