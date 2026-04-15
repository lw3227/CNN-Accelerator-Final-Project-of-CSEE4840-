##################################################
# Modelsim do file to run generic conv layer TB
# Supports L1/L2/L3 via env var LAYER (default: L1)
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

# Determine layer define
set layer_define ""
if {[info exists ::env(LAYER)] && $::env(LAYER) ne ""} {
    set layer_upper [string toupper $::env(LAYER)]
    if {$layer_upper eq "L2"} {
        set layer_define "+define+LAYER_L2"
    } elseif {$layer_upper eq "L3"} {
        set layer_define "+define+LAYER_L3"
    }
    # L1 is default (no define needed)
}

# Compile RTL
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core Line_Buffer.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core input_row_aligner.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core sa_skew_feeder.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core Conv_Buffer.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core systolic_array_top.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core weight_buffer.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core conv_engine_ctrl.v]
vlog +acc -incr [file join $PROJ_DIR input RTL conv_core conv_top.v]

# Compile TB with layer define
if {$layer_define ne ""} {
    vlog +acc -incr $layer_define [file join $PROJ_DIR input TB conv_only tb_conv_layer_txt.v]
} else {
    vlog +acc -incr [file join $PROJ_DIR input TB conv_only tb_conv_layer_txt.v]
}

set vsim_cmd [list vsim -t ps work.tb_conv_layer_txt +VCD_FILE=[file join $VCD_DIR tb_conv_layer_txt.vcd]]
if {[info exists ::env(NO_VCD)] && $::env(NO_VCD) ne "" && $::env(NO_VCD) ne "0"} {
    lappend vsim_cmd +NO_VCD
    puts "INFO: VCD dump disabled."
}
if {[info exists ::env(CASE_NAME)] && $::env(CASE_NAME) ne ""} {
    lappend vsim_cmd +CASE_NAME=$::env(CASE_NAME)
}
if {[info exists ::env(IN_TXT)] && $::env(IN_TXT) ne ""} {
    lappend vsim_cmd +IN_TXT=$::env(IN_TXT)
}
if {[info exists ::env(WT_TXT)] && $::env(WT_TXT) ne ""} {
    lappend vsim_cmd +WT_TXT=$::env(WT_TXT)
}
if {[info exists ::env(OUT_TXT)] && $::env(OUT_TXT) ne ""} {
    lappend vsim_cmd +OUT_TXT=$::env(OUT_TXT)
}
if {[info exists ::env(PASS_ID)] && $::env(PASS_ID) ne ""} {
    lappend vsim_cmd +PASS_ID=$::env(PASS_ID)
}
eval $vsim_cmd

run -all
