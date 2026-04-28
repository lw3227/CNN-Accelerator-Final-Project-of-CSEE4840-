##################################################
# Modelsim do file: cnn_mmio_interface smoke test.
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
    error "Cannot locate project root."
}

source [file join $PROJ_DIR vf scripts runtb_system_e2e_common.tcl]

vlib work
vmap work work

vlog +acc -incr [file join $PROJ_DIR input TB sram_behav.v]
compile_rtl_sources $PROJ_DIR
vlog +acc -incr [file join $PROJ_DIR input RTL interface cnn_mmio_interface.v]
vlog +acc -incr [file join $PROJ_DIR input TB tb_cnn_mmio_interface.v]

vsim -t ps work.tb_cnn_mmio_interface +PROJ_DIR=$PROJ_DIR +NO_VCD
log -r /*
run -all
