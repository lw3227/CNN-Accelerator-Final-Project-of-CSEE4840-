##################################################
# Modelsim do file to run txt-driven Conv1 verification
# across paper / rock / scissors image cases.
#
# This suite launches one child vsim process per image case so that
# plusargs can change cleanly between runs.
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

proc __run_case {proj_dir case_name case_dir use_no_vcd} {
    set in_txt  [file join $case_dir tb_conv1_in_i8_64x64x1.txt]
    set wt_txt  [file join $case_dir tb_conv1_w_i8_3x3x4.txt]
    set out_txt [file join $case_dir tb_conv1_out_i32_62x62x4.txt]

    foreach req_file [list $in_txt $wt_txt $out_txt] {
        if {![file exists $req_file]} {
            error "Missing txt case file: $req_file"
        }
    }

    set env_cmd [list env CONV1_PROJ_DIR=$proj_dir CASE_NAME=$case_name IN_TXT=$in_txt WT_TXT=$wt_txt OUT_TXT=$out_txt]
    if {$use_no_vcd} {
        lappend env_cmd NO_VCD=1
    }

    set child_do [file join $proj_dir vf scripts conv_only runtb_conv1_txt.tcl]
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

foreach case_name {paper rock scissors} {
    set case_dir [file join $CASE_ROOT $case_name]
    puts "INFO: running txt-driven Conv1 case $case_name"
    __run_case $PROJ_DIR $case_name $case_dir $use_no_vcd
}
