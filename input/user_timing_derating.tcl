# Rui ("Ray") Xu
# Nov 2021
# CISL @ Columbia, Kinget Group
# user_timing_derating.tcl

# Optional.  
# Allows user to specify custom timing derating scale factors.

#####################################################################
# User-specified de-rating
#####################################################################
# adds pessimism to the hold analysis by making the latching clock path 20 percent slower.
set_timing_derate -delay_corner dc_min -late 1.2
set_timing_derate -delay_corner dc_min_lt -late 1.2
# adds pessimism to the setup analysis by making the latching clock path 20 percent faster.
set_timing_derate -delay_corner dc_max -early 0.8
report_timing_derate
