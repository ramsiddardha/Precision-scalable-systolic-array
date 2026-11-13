# Project-independent XSim checks and capture procedures.
# Loaded by setup_vivado.tcl; no project or fileset mutation.

proc pe_sim_source_signature {} {
    global pe_vcd_rtl_files pe_vcd_benches
    set signature {}
    foreach path [concat $pe_vcd_rtl_files $pe_vcd_benches] {
        lappend signature [list $path [file size $path] [file mtime $path]]
    }
    return $signature
}

proc pe_check_sim_sources {} {
    global pe_sim_setup_signature
    if {[pe_sim_source_signature] ne $pe_sim_setup_signature} {
        error "A source changed after setup. Source setup_vivado.tcl again before simulating."
    }
}
proc pe_sim_uint {path} {
    return [string trim [get_value -radix unsigned $path]]
}

proc pe_run_vcd {selected_mode} {
    global pe_vcd_output_dir pe_clock_period_ns pe_num_frames pe_random_seed
    global pe_vcd_rtl_files pe_vcd_benches pe_variant pe_frame_cycles pe_capture_start
    pe_check_sim_config
    pe_check_sim_sources
    if {$selected_mode ni {0 1 2}} { error "Use pe_run_vcd 0, 1 or 2." }
    set mode_name [lindex {int4 int8 int16} $selected_mode]
    set activity_path [file join $pe_vcd_output_dir array_${mode_name}.vcd]
    set info_path [file join $pe_vcd_output_dir array_${mode_name}_runinfo.txt]
    file delete -force $activity_path $info_path
    catch {close_sim}
    set options [list -testplusarg POWER_MODE=$selected_mode \
        -testplusarg NUM_FRAMES=$pe_num_frames \
        -testplusarg CLOCK_PERIOD_NS=$pe_clock_period_ns \
        -testplusarg SEED=$pe_random_seed]

    set run_code [catch {
        pe_load_snapshot block_tb $options
        run [format %.6f [expr {$pe_capture_start * $pe_clock_period_ns}]] ns
        if {[pe_sim_uint /block_tb/capture_ready] ne "1" ||
            [pe_sim_uint /block_tb/selected_mode] ne "$selected_mode" ||
            [pe_sim_uint /block_tb/num_frames] ne "$pe_num_frames" ||
            [pe_sim_uint /block_tb/clock_period_fs] != [expr {round($pe_clock_period_ns * 1.0e6)}] ||
            [pe_sim_uint /block_tb/initial_random_seed] != [scan $pe_random_seed %x]} {
            error "Power bench configuration/reset check failed. Inspect the simulator log."
        }
        open_vcd $activity_path
        # Level zero records every level below DUT, excluding golden TB math.
        log_vcd -level 0 /block_tb/dut/*
        run all
        if {[pe_sim_uint /block_tb/capture_done] ne "1" ||
            [pe_sim_uint /block_tb/completed_frames] ne "$pe_num_frames"} {
            error "A power-workload check failed or not all frames completed."
        }
        set begin_fs [pe_sim_uint /block_tb/capture_begin_fs]
        set end_fs [pe_sim_uint /block_tb/capture_end_fs]
        set expected_begin [expr {round($pe_capture_start * $pe_clock_period_ns * 1.0e6)}]
        set expected_end [expr {round(($pe_capture_start + $pe_frame_cycles * $pe_num_frames) * $pe_clock_period_ns * 1.0e6)}]
        if {$begin_fs != $expected_begin || $end_fs != $expected_end} {
            error "Actual capture timestamps differ from the on-chip skew schedule."
        }
    } run_message run_options]
    catch {flush_vcd}
    catch {close_vcd}
    if {$run_code} {
        file delete -force $activity_path $info_path
        return -options $run_options $run_message
    }
    if {![file isfile $activity_path] || [file size $activity_path] < 1000} {
        file delete -force $activity_path
        error "No usable VCD was written: $activity_path"
    }

    pe_check_sim_sources
    # A PASS sidecar is written only after arithmetic, pipeline and clock checks.
    set record [open $info_path w]
    puts $record "Design top: systolic_array_skew_top"
    puts $record "Variant: $pe_variant"
    puts $record "VCD DUT scope: block_tb/dut"
    puts $record "Mode: $selected_mode ($mode_name)"
    puts $record "Clock period: $pe_clock_period_ns ns"
    puts $record "Random seed: 0x$pe_random_seed"
    puts $record "Frames: $pe_num_frames; checked MACs: [expr {4096 * $pe_num_frames}]"
    puts $record "Capture begins: [format %.6f [expr {$begin_fs / 1.0e6}]] ns"
    puts $record "Capture ends: [format %.6f [expr {$end_fs / 1.0e6}]] ns"
    puts $record "Each matrix includes start, clear, 48 run steps, and check. The first 16 RUN edges consume unskewed vectors."
    puts $record "Test result: PASS"
    puts $record "VCD CRC32: [pe_crc32 $activity_path]"
    foreach source [concat $pe_vcd_rtl_files $pe_vcd_benches] {
        puts $record "Source CRC32: [file tail $source] [pe_crc32 $source]"
    }
    close $record
    puts "PASS: wrote $activity_path"
    puts "Run metadata: $info_path"
}


proc pe_crc32 {path} {
    set f [open $path rb]
    set crc 0
    try {
        while {![eof $f]} {set crc [zlib crc32 [read $f 1048576] $crc]}
    } finally {close $f}
    return [format %08x $crc]
}
