##################################################
# Modelsim do file: behavioral RTL simulation of system_top.
#   - Default SRAM model: sram_behav.v (+ tb_system_e2e.v)
#   - Set USE_GATE_SRAM=1 to switch to foundry SRAM macros (+ tb_system_e2e_gate.v)
##################################################
set __cur [file normalize [pwd]]
set PROJ_DIR ""
if {[info exists ::env(CONV1_PROJ_DIR)] && $::env(CONV1_PROJ_DIR) ne ""} {
    set PROJ_DIR [file normalize $::env(CONV1_PROJ_DIR)]
} else {
    while {1} {
        if {[file exists [file join $__cur vf scripts runtb_system_e2e_common.tcl]]} {
            set PROJ_DIR $__cur
            break
        }
        set __par [file dirname $__cur]
        if {$__par eq $__cur} { break }
        set __cur $__par
    }
}
if {$PROJ_DIR eq ""} {
    error "Cannot locate project root (runtb_system_e2e_common.tcl)."
}
source [file join $PROJ_DIR vf scripts runtb_system_e2e_common.tcl]
set VCD_DIR "/user/stud/fall25/lw3227/vcd"
file mkdir $VCD_DIR

vlib work
vmap work work

set tb_top [compile_tb $PROJ_DIR "behav"]
compile_rtl_sources $PROJ_DIR

launch_sim $PROJ_DIR $tb_top
