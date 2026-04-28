quietly catch {view wave}

if {[llength [info commands batch_mode]] && [batch_mode]} {
    return
}

quietly catch {delete wave *}

proc add_wave_if_exists {path {opts {}}} {
    if {[llength [find signals $path]]} {
        eval add wave -position insertpoint $opts [list $path]
    }
}

proc add_divider {name} {
    add wave -divider $name
}

proc add_signal_group {base sigs {hex_sigs {}} {dec_sigs {}}} {
    foreach sig $sigs {
        set path "$base/$sig"
        if {[lsearch -exact $hex_sigs $sig] >= 0} {
            add_wave_if_exists $path {-radix hexadecimal}
        } elseif {[lsearch -exact $dec_sigs $sig] >= 0} {
            add_wave_if_exists $path {-radix decimal}
        } else {
            add_wave_if_exists $path
        }
    }
}

proc add_system_e2e_waves {} {
    # Pick whichever TB is loaded (behavioral or gate variant).
    set tb_root ""
    foreach cand {sim:/tb_system_e2e sim:/tb_system_e2e_gate} {
        if {[llength [find signals $cand/*]]} {
            set tb_root $cand
            break
        }
    }
    if {$tb_root eq ""} {
        return 0
    }
    set dut_root $tb_root/u_dut

    add_divider "Host IO"
    add_signal_group $tb_root \
        {clk rst_n load_sel load_valid load_ready load_data load_last busy predict_valid predict_class} \
        {load_data} {}

    add_divider "TopFSM"
    add_signal_group $dut_root/u_top_fsm \
        {state load_sel load_valid load_ready load_last runner_start runner_layer_sel runner_pass_id runner_is_fc runner_done sram_a_start sram_a_layer_sel sram_a_data_sel preload_wr_valid preload_wr_ready predict_valid predict_class} \
        {} {}

    add_divider "RunnerFSM"
    add_signal_group $dut_root/u_runner \
        {state start layer_sel pass_id is_fc done sram_a_start sram_a_layer_sel sram_a_data_sel sram_a_pass_id sram_a_done sram_b_start sram_b_layer_sel sram_b_data_sel sram_b_pass_id sram_b_done pool_frame_done conv_frame_rearm fc_done} \
        {} {}

    add_divider "SRAM Control"
    add_signal_group $dut_root \
        {preload_mode active_data_sel active_is_fc runner_layer_sel runner_pass_id runner_is_fc sram_a_start sram_a_layer_sel sram_a_data_sel sram_a_pass_id sram_a_done run_sram_b_start run_sram_b_layer_sel run_sram_b_data_sel run_sram_b_pass_id sram_b_done} \
        {} {}

    add_divider "SRAM_A Dataflow"
    add_signal_group $dut_root \
        {sram_a_data_valid sram_a_data_ready sram_a_data_last sram_a_read_data sram_a_pool_valid sram_a_pool_ready sram_a_pool_last sram_a_pool_data route_conv_cfg route_conv_wt route_conv_in route_fc_cfg route_fc_wt} \
        {sram_a_read_data sram_a_pool_data} {}

    add_divider "SRAM_B Dataflow"
    add_signal_group $dut_root \
        {sram_b_data_valid sram_b_data_ready sram_b_data_last sram_b_read_data sram_b_pool_valid sram_b_pool_ready sram_b_pool_last sram_b_pool_data route_conv_in_b route_fc_data_b} \
        {sram_b_read_data sram_b_pool_data} {}

    add_divider "WT Prepad"
    add_signal_group $dut_root/u_wt_prepad \
        {is_wt_read up_valid up_ready up_last up_data dn_valid dn_ready dn_last dn_data} \
        {up_data dn_data} {}

    add_divider "Conv Input Adapter"
    add_signal_group $dut_root \
        {conv_in_raw_valid conv_in_raw_last conv_in_raw_data conv_in_valid conv_in_ready conv_in_last conv_in_data conv_in_byte_en} \
        {conv_in_raw_data conv_in_data} {}
    add_signal_group $dut_root/u_conv_data_adapter \
        {up_valid up_ready up_last up_data dn_valid dn_ready dn_last dn_data dn_byte_en hold_valid hold_reg byte_sel is_l1} \
        {up_data dn_data hold_reg} {}

    add_divider "Active Top"
    add_signal_group $dut_root/u_conv \
        {layer_sel in_valid in_ready in_last in_data in_byte_en wt_valid wt_ready wt_last wt_data cfg_valid cfg_ready cfg_last cfg_data pool_valid pool_ready pool_last pool_data frame_rearm_done frame_done_pulse wt_load_done} \
        {in_data wt_data cfg_data pool_data} {}

    add_divider "Conv1 Frontend"
    add_signal_group $dut_root/u_conv/u_conv1 \
        {pix_accept pix_cnt frame_done frame_rearm bank_can_write have_ready_block launch_from_A partial_pending pix3_valid in_valid in_ready in_last in_data in_byte_en wt_valid wt_ready wt_last wt_data start_pulse_r rd_en_r rd_bank_r rd_col_r sa_done} \
        {in_data wt_data} {}
    add_signal_group $dut_root/u_conv/u_conv1/u_input_row_aligner \
        {pix3_valid row0_out row1_out row2_out} \
        {row0_out row1_out row2_out} {}

    add_divider "Conv Buffer"
    add_signal_group $dut_root/u_conv/u_conv1/u_conv_buffer \
        {accepting_input_col fill_base_x_r fill_cols_r x_pos_r ready_A_r ready_B_r valid_rows_A_r valid_rows_B_r seed_pending_r consuming_r bank_can_write have_ready_block launch_from_A partial_pending raw_firstcol_flat} \
        {raw_firstcol_flat} {}

    add_divider "Conv Ctrl / SA"
    add_signal_group $dut_root/u_conv/u_conv1/u_conv_engine_ctrl \
        {state_dbg wt_ready weights_loaded wt_load_active wt_load_cnt feed_cnt_dbg consume_ready_bank consume_bank_sel rd_en rd_bank rd_col wb_ring start_pulse} \
        {} {}
    add_signal_group $dut_root/u_conv/u_conv1/u_systolic_array_top \
        {start_pulse mode_cfg valid_rows_cfg a_in_flat b_in_flat c_out_flat done col_stream_data_flat col_stream_valid col_stream_last} \
        {a_in_flat b_in_flat c_out_flat col_stream_data_flat} {}

    add_divider "Conv To Quant"
    add_signal_group $dut_root/u_conv/u_conv_quant_adapter \
        {in_valid1 in_valid2 in_valid3 in_valid4 start1 start2 start3 start4 qp_rso0 qp_rso1 qp_rso2 qp_rso3} \
        {} {qp_rso0 qp_rso1 qp_rso2 qp_rso3}

    add_divider "Quant"
    add_signal_group $dut_root/u_conv \
        {bias_in_w M_in_w sh_in_w cut1 cut2 cut3 cut4 cut_valid1 cut_valid2 cut_valid3 cut_valid4} \
        {bias_in_w M_in_w sh_in_w} {cut1 cut2 cut3 cut4}

    add_divider "Pool"
    add_signal_group $dut_root/u_conv \
        {cut1_out cut2_out cut3_out cut4_out cut_valid1_out cut_valid2_out cut_valid3_out cut_valid4_out} \
        {} {cut1_out cut2_out cut3_out cut4_out}
    add_signal_group $dut_root/u_conv/u_pool \
        {pool_valid pool_ready pool_last pool_data frame_done_pulse} \
        {pool_data} {}
    add_signal_group $dut_root/u_conv/u_pool/u_pool_core \
        {emit_active emit_cnt burst_idx drop_until_idle any_cut_valid lane_reset_r} \
        {} {}

    add_divider "FC Path"
    add_signal_group $dut_root \
        {fc_cfg_valid fc_cfg_ready fc_cfg_last fc_cfg_data fc_wt_valid fc_wt_last fc_data_valid fc_data_last fc_all_done fc_done fc_acc0 fc_acc1 fc_acc2 predict_valid predict_class} \
        {fc_cfg_data} {fc_acc0 fc_acc1 fc_acc2}
    add_signal_group $dut_root/u_fc_adapter \
        {wt_valid wt_ready wt_last wt_data data_valid data_ready data_last data_data mul_en pixel0 pixel1 pixel2 kernel0 kernel1 kernel2 all_done fc_done} \
        {wt_data data_data} {pixel0 pixel1 pixel2 kernel0 kernel1 kernel2}
    add_signal_group $dut_root/u_fc \
        {cfg_valid cfg_ready cfg_last cfg_data param_load_done mul_en pixel0 pixel1 pixel2 kernel0 kernel1 kernel2 acc0 acc1 acc2 all_done} \
        {cfg_data} {acc0 acc1 acc2 pixel0 pixel1 pixel2 kernel0 kernel1 kernel2}

    quietly WaveRestoreZoom {0 ps} {200000 ps}
    return 1
}

proc add_conv_debug_waves {} {
    set tb_root ""
    foreach cand {sim:/tb_conv1_txt sim:/tb_conv_layer_txt sim:/tb_system_e2e} {
        if {[llength [find signals $cand/*]]} {
            set tb_root $cand
            break
        }
    }

    if {$tb_root eq ""} {
        return 0
    }

    set dut_root "$tb_root/dut"
    if {![llength [find signals $dut_root/*]]} {
        return 0
    }

    add_divider "Conv1_top Ports"
    add_signal_group $dut_root \
        {clk rst_n in_valid in_data in_ready wt_valid wt_ready wt_last rd_en sa_done wt_data b_in_flat c_out_col_stream_flat c_out_col_valid c_out_col_last} \
        {in_data wt_data b_in_flat c_out_col_stream_flat} {}

    quietly WaveRestoreZoom {0 ps} {200000 ps}
    return 1
}

if {[add_system_e2e_waves]} {
    return
}

if {[add_conv_debug_waves]} {
    return
}

puts "wave.tcl: no supported hierarchy found."
