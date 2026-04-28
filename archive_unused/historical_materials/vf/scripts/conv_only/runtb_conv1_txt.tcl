##################################################
# Modelsim do file to run txt-driven Conv1 verification
##################################################
proc __find_proj_dir {} {
    if {[info exists ::env(CONV1_PROJ_DIR)] && $::env(CONV1_PROJ_DIR) ne ""} {
        set env_proj [file normalize $::env(CONV1_PROJ_DIR)]
        if {[file exists [file join $env_proj input RTL conv_core Line_Buffer.v]]} {
            return $env_proj
        }
    }

    set cur [file normalize [pwd]]
    while {1} {
        if {[file exists [file join $cur input RTL conv_core Line_Buffer.v]] &&
            [file exists [file join $cur vf scripts wave.tcl]]} {
            return $cur
        }
        set parent [file dirname $cur]
        if {$parent eq $cur} {
            break
        }
        set cur $parent
    }
    return ""
}

set PROJ_DIR [__find_proj_dir]
if {$PROJ_DIR eq ""} {
    error "Cannot locate project root. Please run from project tree or set env(CONV1_PROJ_DIR)."
}
set SCRIPT_DIR [file join $PROJ_DIR vf scripts]
set VCD_DIR    "/user/stud/fall25/lw3227/vcd"

file mkdir $VCD_DIR

vlib work
vmap work work

vlog +acc -incr [file join $PROJ_DIR input RTL conv_core Line_Buffer.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core input_row_aligner.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core sa_skew_feeder.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core Conv_Buffer.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core systolic_array_top.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core weight_buffer.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core conv_engine_ctrl.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core conv_top.v]
vlog +acc -incr [file join $PROJ_DIR input TB conv_only tb_conv1_txt.v]

set vsim_cmd [list vsim -t ps work.tb_conv1_txt +VCD_FILE=[file join $VCD_DIR tb_conv1_txt.vcd]]
if {[info exists ::env(NO_VCD)] && $::env(NO_VCD) ne "" && $::env(NO_VCD) ne "0"} {
    lappend vsim_cmd +NO_VCD
    puts "INFO: VCD dump disabled."
}
if {[info exists ::env(CASE_NAME)] && $::env(CASE_NAME) ne ""} {
    lappend vsim_cmd +CASE_NAME=$::env(CASE_NAME)
    puts "INFO: run tb_conv1_txt with +CASE_NAME=$::env(CASE_NAME)"
}
if {[info exists ::env(IN_TXT)] && $::env(IN_TXT) ne ""} {
    lappend vsim_cmd +IN_TXT=$::env(IN_TXT)
    puts "INFO: run tb_conv1_txt with +IN_TXT=$::env(IN_TXT)"
}
if {[info exists ::env(WT_TXT)] && $::env(WT_TXT) ne ""} {
    lappend vsim_cmd +WT_TXT=$::env(WT_TXT)
    puts "INFO: run tb_conv1_txt with +WT_TXT=$::env(WT_TXT)"
}
if {[info exists ::env(OUT_TXT)] && $::env(OUT_TXT) ne ""} {
    lappend vsim_cmd +OUT_TXT=$::env(OUT_TXT)
    puts "INFO: run tb_conv1_txt with +OUT_TXT=$::env(OUT_TXT)"
}
eval $vsim_cmd

# Load internal-signal-rich wave view in GUI mode.
if {[llength [info commands batch_mode]] && ![batch_mode]} {
    do [file join $SCRIPT_DIR conv_only wave_conv1_txt.tcl]
}

run -all
