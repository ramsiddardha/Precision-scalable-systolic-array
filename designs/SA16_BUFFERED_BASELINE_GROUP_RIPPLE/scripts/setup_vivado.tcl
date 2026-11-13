# Vivado 2024.1 project-independent RTL compilation and checked VCD capture.
# Documented flow: xvlog -> xelab -> xsim. No launch_simulation/compile.bat.
set pe_num_frames 10
if {[info exists env(SA_MATRICES)]} {set pe_num_frames $env(SA_MATRICES)}
set pe_clock_period_ns 3.333
if {[info exists env(SA_PERIOD)]} {set pe_clock_period_ns $env(SA_PERIOD)}
set pe_frame_cycles 308
set pe_capture_start 313
switch -- $pe_clock_period_ns {
    3.333 {set pe_period_tag 3p333}
    3.000 {set pe_period_tag 3ns}
    default {error "Set SA_PERIOD to 3.333 or 3.000."}
}
if {![info exists pe_random_seed]} {set pe_random_seed 1a2b3c4d}
set pe_root [file normalize [file join [file dirname [info script]] ..]]
set pe_sim_setup_signature {}

proc pe_check_sim_config {} {
    global pe_num_frames pe_clock_period_ns pe_random_seed
    if {![string is integer -strict $pe_num_frames] || $pe_num_frames < 1} {
        error "pe_num_frames must be a positive integer."
    }

    if {![regexp {^[0-9a-fA-F]{1,8}$} $pe_random_seed] || [scan $pe_random_seed %x]==0} {
        error "pe_random_seed must be 1-8 nonzero hexadecimal digits."
    }
}

# Quote literal batch arguments, including paths with spaces; no delayed ! expansion.
proc pe_cmd_quote {value} {
    if {[regexp {[\r\n"]} $value]} {error "Unsupported quote/newline in tool argument."}
    return "\"[string map [list % %%] $value]\""
}
proc pe_resolve_compiler {name} {
    global env tcl_platform
    if {$tcl_platform(platform) eq "windows"} {
        set roots {}
        if {[info exists env(XILINX_VIVADO)]} {lappend roots $env(XILINX_VIVADO)}
        lappend roots [file join [file dirname [info nameofexecutable]] .. .. ..]
        foreach root $roots {
            set tool [file normalize [file join $root bin ${name}.bat]]
            if {[file isfile $tool]} {
                set env(XILINX_VIVADO) [file normalize $root]
                return $tool
            }
        }
        error "Cannot find $name.bat. Run from Vivado 2024.1 or use 01_RUN_VCD_WINDOWS.cmd with PE_VIVADO_ROOT set."
    }
    set tool [auto_execok $name]
    if {$tool eq ""} {error "Cannot find $name; source Vivado settings64.sh first."}
    return [lindex $tool 0]
}
proc pe_exec_compiler {tool arguments label} {
    global pe_build_dir pe_log_dir env tcl_platform
    set executable [pe_resolve_compiler $tool]
    set log [file join $pe_log_dir ${label}.log]
    puts "RUN: $label (log: $log)"
    if {$tcl_platform(platform) eq "windows"} {
        set wrapper [file join $pe_build_dir ${label}.cmd]
        set fh [open $wrapper w]
        fconfigure $fh -translation crlf
        puts $fh "@echo off"
        puts $fh "setlocal DisableDelayedExpansion"
        set words [list call [pe_cmd_quote $executable]]
        foreach arg $arguments {lappend words [pe_cmd_quote $arg]}
        puts $fh [join $words " "]
        puts $fh "exit /b %errorlevel%"
        close $fh
        set shell cmd.exe
        if {[info exists env(COMSPEC)]} {set shell $env(COMSPEC)}
        set command [list $shell /d /c $wrapper]
    } else {
        set command [linsert $arguments 0 $executable]
    }
    set rc [catch {exec {*}$command >$log 2>@1} message]
    if {$rc} {
        set detail ""
        if {[file isfile $log]} {
            set fh [open $log r];set detail [read $fh];close $fh
        }
        error "$label failed: $message\n$detail\nFull log: $log\nBuild directory: $pe_build_dir"
    }
}
proc pe_compile_snapshots {} {
    global pe_vcd_package_dir pe_vcd_rtl_files pe_vcd_benches
    global pe_build_dir pe_log_dir pe_sim_setup_signature env pe_root pe_variant
    pe_check_sim_config
    set pe_vcd_rtl_files [lsort [glob -nocomplain -directory [file join $pe_vcd_package_dir rtl] *.v]]
    if {[llength $pe_vcd_rtl_files] != 25} {error "Expected 25 RTL sources for $pe_variant."}
    set pe_vcd_benches [list [file join $pe_root tb block_tb.sv]]
    foreach source [concat $pe_vcd_rtl_files $pe_vcd_benches] {
        if {![file isfile $source] || ![file readable $source]} {error "Missing/unreadable source: $source"}
    }
    set base [file join $pe_vcd_package_dir .xsim_build]
    foreach name {TEMP TMP TMPDIR} {
        if {[info exists env($name)] && [file isdirectory $env($name)]} {set base $env($name);break}
    }
    set run_id [format "pe_%s_%s_%s" $pe_variant [pid] [clock clicks]]
    set pe_build_dir [file normalize [file join $base $run_id]]
    set pe_log_dir [file join $pe_vcd_package_dir logs vivado_vcd $run_id]
    file mkdir $pe_build_dir $pe_log_dir
    set fh [open [file join $pe_vcd_package_dir logs vivado_vcd LAST_RUN.txt] w]
    puts $fh "Build directory: $pe_build_dir\nStage logs: $pe_log_dir";close $fh
    set pe_sim_setup_signature [pe_sim_source_signature]
    set old_dir [pwd]
    try {
        cd $pe_build_dir
        # Compile a fixed source manifest from scratch: no UVM, glbl, or FPGA IP.
        pe_exec_compiler xvlog [concat [list -sv -relax -work xil_defaultlib] \
            $pe_vcd_rtl_files $pe_vcd_benches] compile
        foreach top {block_tb} {
            pe_exec_compiler xelab [list -relax -debug all -mt off -timescale 1ns/1fs \
                xil_defaultlib.$top -s ${top}_checked] elaborate_$top
        }
    } finally {cd $old_dir}
    pe_check_sim_sources
}
proc pe_load_snapshot {top plusargs} {
    global pe_build_dir pe_sim_setup_signature
    if {$pe_sim_setup_signature eq ""} {error "Compile the selected array variant first."}
    pe_check_sim_sources
    catch {close_sim}
    set old_dir [pwd]
    try {
        cd $pe_build_dir
        xsim ${top}_checked -onfinish stop -onerror stop {*}$plusargs
    } finally {cd $old_dir}
}
