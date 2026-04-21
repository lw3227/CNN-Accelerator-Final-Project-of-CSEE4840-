
    create_clock -name clock_50 -period 20ns [get_ports CLOCK_50]
    create_generated_clock -name fabric_clk_div2 -source [get_ports CLOCK_50] -divide_by 2 [get_registers {*fabric_clk_div2}]
    derive_pll_clocks -create_base_clocks
    derive_clock_uncertainty

