
    create_clock -name clock_50 -period 20ns [get_ports CLOCK_50]
    derive_pll_clocks -create_base_clocks
    derive_clock_uncertainty

