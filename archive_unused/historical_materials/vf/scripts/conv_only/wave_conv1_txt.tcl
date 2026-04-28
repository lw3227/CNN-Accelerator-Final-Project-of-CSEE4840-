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

set tb_root "sim:/tb_conv1_txt"
if {![llength [find signals $tb_root/*]]} {
    puts "wave_conv1_txt.tcl: tb_conv1_txt not found."
    return
}

set dut_root "$tb_root/dut"
if {![llength [find signals $dut_root/*]]} {
    puts "wave_conv1_txt.tcl: dut not found under tb_conv1_txt."
    return
}

add_divider "Top Ports"
foreach sig {clk rst_n in_valid in_ready wt_valid wt_ready wt_last rd_en sa_done} {
    add_wave_if_exists $dut_root/$sig
}
add_wave_if_exists $dut_root/in_data {-radix decimal}
add_wave_if_exists $dut_root/wt_data {-radix hexadecimal}
add_wave_if_exists $dut_root/b_in_flat {-radix hexadecimal}
add_wave_if_exists $dut_root/c_out_col_valid {-radix hexadecimal}
add_wave_if_exists $dut_root/c_out_col_last {-radix hexadecimal}
add_wave_if_exists $dut_root/c_out_col_stream_flat {-radix hexadecimal}

add_divider "Top Control"
foreach sig {state feed_cnt wt_load_cnt rd_en_r rd_bank_r rd_col_r wb_ring_r start_pulse_r frame_done weights_loaded wt_load_active} {
    if {$sig eq "state" || $sig eq "rd_bank_r" || $sig eq "frame_done" || $sig eq "weights_loaded" || $sig eq "wt_load_active"} {
        add_wave_if_exists $dut_root/$sig
    } else {
        add_wave_if_exists $dut_root/$sig {-radix unsigned}
    }
}
foreach sig {ready_A_r ready_B_r wr_bank_r fill_cols_r seed_pending_r} {
    add_wave_if_exists $dut_root/u_conv_buffer/$sig {-radix unsigned}
}

add_divider "SA Datapath"
add_wave_if_exists $dut_root/a_in_flat {-radix hexadecimal}
add_wave_if_exists $dut_root/b_in_to_sa {-radix hexadecimal}
add_wave_if_exists $dut_root/c_out_raw_flat {-radix hexadecimal}
add_wave_if_exists $dut_root/u_systolic_array_top/a_in_flat {-radix hexadecimal}
add_wave_if_exists $dut_root/u_systolic_array_top/b_in_flat {-radix hexadecimal}
add_wave_if_exists $dut_root/u_systolic_array_top/c_out_flat {-radix hexadecimal}

add_divider "SA Stream"
foreach sig {start_pulse done col_stream_valid col_stream_last} {
    add_wave_if_exists $dut_root/u_systolic_array_top/$sig {-radix hexadecimal}
}
add_wave_if_exists $dut_root/u_systolic_array_top/col_stream_data_flat {-radix hexadecimal}

quietly WaveRestoreZoom {0 ps} {200000 ps}
