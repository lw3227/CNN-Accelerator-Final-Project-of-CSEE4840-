##################################################
# Modelsim do file to run generic conv-layer txt verification
# across L2/L3, paper/rock/scissors, and PASS_ID=0/1.
#
# This suite launches one child vsim process per combination so that
# compile-time layer defines and runtime plusargs change cleanly.
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

proc __layer_files {layer case_dir} {
    set layer_upper [string toupper $layer]
    if {$layer_upper eq "L2"} {
        return [list \
            [file join $case_dir tb_conv2_in_i8_31x31x4.txt] \
            [file join $case_dir tb_conv2_w_i8_3x3x4x8.txt] \
            [file join $case_dir tb_conv2_out_i32_29x29x8.txt]]
    }
    if {$layer_upper eq "L3"} {
        return [list \
            [file join $case_dir tb_conv3_in_i8_14x14x8.txt] \
            [file join $case_dir tb_conv3_w_i8_3x3x8x8.txt] \
            [file join $case_dir tb_conv3_out_i32_12x12x8.txt]]
    }
    error "Unsupported layer: $layer"
}

proc __run_case {proj_dir layer case_name case_dir pass_id use_no_vcd} {
    lassign [__layer_files $layer $case_dir] in_txt wt_txt out_txt

    foreach req_file [list $in_txt $wt_txt $out_txt] {
        if {![file exists $req_file]} {
            error "Missing txt case file: $req_file"
        }
    }

    set env_cmd [list \
        env \
        CONV1_PROJ_DIR=$proj_dir \
        LAYER=$layer \
        CASE_NAME=$case_name \
        IN_TXT=$in_txt \
        WT_TXT=$wt_txt \
        OUT_TXT=$out_txt \
        PASS_ID=$pass_id]
    if {$use_no_vcd} {
        lappend env_cmd NO_VCD=1
    }

    set child_do [file join $proj_dir vf scripts conv_only runtb_conv_layer_txt.tcl]
    set child_cmd [concat $env_cmd [list vsim -c -do "do $child_do; quit -f"]]
    set child_out [eval exec $child_cmd]
    puts $child_out
}

set PROJ_DIR [__find_proj_dir]
if {$PROJ_DIR eq ""} {
    error "Cannot locate project root. Please run from project tree or set env(CONV1_PROJ_DIR)."
}
set CASE_ROOT [file join $PROJ_DIR matlab debug txt_cases]
set use_no_vcd 0

if {[info exists ::env(NO_VCD)] && $::env(NO_VCD) ne "" && $::env(NO_VCD) ne "0"} {
    set use_no_vcd 1
    puts "INFO: VCD dump disabled."
}

foreach layer {L2 L3} {
    foreach case_name {paper rock scissors} {
        set case_dir [file join $CASE_ROOT $case_name]
        foreach pass_id {0 1} {
            puts "INFO: running txt-driven $layer case $case_name pass $pass_id"
            __run_case $PROJ_DIR $layer $case_name $case_dir $pass_id $use_no_vcd
        }
    }
}
