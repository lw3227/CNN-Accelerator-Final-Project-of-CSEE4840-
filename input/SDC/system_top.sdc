set sdc_version 1.6

set clk_name   clk
set clkperiod  20.0

create_clock -name $clk_name -period $clkperiod [get_ports clk]

set_false_path -from [get_ports rst_n]

set all_in_no_clk_rst [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set all_outs          [all_outputs]

set_input_transition 0.1 $all_in_no_clk_rst
set_input_delay  -clock $clk_name 0.2 $all_in_no_clk_rst
set_output_delay -clock $clk_name 0.2 $all_outs
