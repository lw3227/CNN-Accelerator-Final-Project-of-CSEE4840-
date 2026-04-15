##################################################
# Shared helpers for system_e2e runtb scripts.
# Sourced by runtb_system_e2e_{behav,syn,pnr}.tcl.
##################################################

# --- RTL source list (behav only: all files compiled from input/RTL/) ---
proc compile_rtl_sources {proj_dir} {
    # SRAM wrappers
    foreach f {Addr_Gen.v sram_A_controller.v sram_B_controller.v \
               sram_A_wrapper.v sram_B_wrapper.v top_sram_A.v top_sram_B.v} {
        vlog +acc -incr [file join $proj_dir input RTL SRAM $f]
    }
    # Conv core
    foreach f {Line_Buffer.v input_row_aligner.v sa_skew_feeder.v Conv_Buffer.v \
               systolic_array_top.v weight_buffer.v conv_engine_ctrl.v conv_top.v} {
        vlog +acc -incr [file join $proj_dir input RTL conv_core $f]
    }
    # Quant / Pool
    foreach f {integration/quant_param_loader.v integration/conv_quant_adapter.v \
               integration/quant_pool_adapter.v quant/Quantization_PE.v \
               quant/Quantization_Top.v pool/pool_core.v pool/pool_stream_top.v} {
        vlog +acc -incr [file join $proj_dir input RTL quant_pool $f]
    }
    vlog +acc -incr [file join $proj_dir input RTL conv_core conv_quant_pool.v]
    # FSM
    foreach f {top_fsm.v layer_runner_fsm.v wt_prepad_inserter.v conv_data_adapter.v} {
        vlog +acc -incr [file join $proj_dir input RTL fsm $f]
    }
    # FC
    foreach f {mac.v fc_bias_loader.v FC.v fc_data_adapter.v} {
        vlog +acc -incr [file join $proj_dir input RTL fc $f]
    }
    # System top
    vlog +acc -incr [file join $proj_dir input RTL system_top.v]
}

# --- TB + SRAM model selection ---
# mode: "behav"  -> sram_behav.v + tb_system_e2e.v (unless USE_GATE_SRAM=1)
#       "gate"   -> SRAM_macro/*.v + tb_system_e2e_gate.v (forced)
# Returns tb_top name.
proc compile_tb {proj_dir mode} {
    set use_gate 0
    if {$mode eq "gate"} {
        set use_gate 1
    } elseif {[info exists ::env(USE_GATE_SRAM)] && $::env(USE_GATE_SRAM) ne "" && $::env(USE_GATE_SRAM) ne "0"} {
        set use_gate 1
    }

    if {$use_gate} {
        puts "INFO: using gate-level SRAM macro models + tb_system_e2e_gate."
        vlog +acc -incr [file join $proj_dir input SRAM_macro sram_A sram_A.v]
        vlog +acc -incr [file join $proj_dir input SRAM_macro sram_B sram_B.v]
        vlog +acc -incr [file join $proj_dir input TB tb_system_e2e_gate.v]
        return "tb_system_e2e_gate"
    } else {
        puts "INFO: using behavioral SRAM + tb_system_e2e."
        vlog +acc -incr [file join $proj_dir input TB sram_behav.v]
        vlog +acc -incr [file join $proj_dir input TB tb_system_e2e.v]
        return "tb_system_e2e"
    }
}

# --- Build/launch vsim and run ---
# extra_args: additional vsim arguments (e.g. -sdfmax ...)
proc launch_sim {proj_dir tb_top {extra_args {}}} {
    set vsim_cmd [list vsim -t ps]
    set vsim_cmd [concat $vsim_cmd $extra_args]
    lappend vsim_cmd work.$tb_top +PROJ_DIR=$proj_dir
    if {[info exists ::env(NO_VCD)] && $::env(NO_VCD) ne "" && $::env(NO_VCD) ne "0"} {
        lappend vsim_cmd +NO_VCD
    }
    eval $vsim_cmd
    log -r /*
    do [file join $proj_dir vf scripts wave.tcl]
    run -all
}
