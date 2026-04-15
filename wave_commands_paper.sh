#!/usr/bin/env bash

# Run from the repo root:
#   /courses/ee6350/proj_2026Spring/team05/SAA/Layer_v1

# L1 paper waveform
env LAYER=L1 CASE_NAME=paper vsim -do "do vf/scripts/runtb_conv_quant_pool_e2e_wave.tcl"

# L2 paper waveform
env LAYER=L2 CASE_NAME=paper vsim -do "do vf/scripts/runtb_conv_quant_pool_e2e_wave.tcl"

# L3 paper waveform
env LAYER=L3 CASE_NAME=paper vsim -do "do vf/scripts/runtb_conv_quant_pool_e2e_wave.tcl"
