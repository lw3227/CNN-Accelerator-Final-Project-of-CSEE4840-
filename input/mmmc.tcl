# Rui ("Ray") Xu
# Nov 2021
# CISL @ Columbia, Kinget Group
# mmmc.tcl

# Sets up multi-mode-multi-corner analysis for Innovus flow.
# Point library paths appropriately to all std cell libraries used.



#####################################################################
# QRC Extraction Corners
#####################################################################
# Default is to use QRC techfile
create_rc_corner -name RC_BEST -qrc_tech  "$PDK_PATH/Base_PDK/PDK_CRN65GP_v1.0c_official_IC61_20101010/Assura/lvs_rcx/tn65cmsp007v1_1_3a/RC_QRC_crn65lp_1p9m_6x1z1u_alrdl_5corners_13a/RC_QRC_crn65lp_1p09m+alrdl_6x1z1u_rcbest/qrcTechFile"
create_rc_corner -name RC_TYP -qrc_tech   "$PDK_PATH/Base_PDK/PDK_CRN65GP_v1.0c_official_IC61_20101010/Assura/lvs_rcx/tn65cmsp007v1_1_3a/RC_QRC_crn65lp_1p9m_6x1z1u_alrdl_5corners_13a/RC_QRC_crn65lp_1p09m+alrdl_6x1z1u_typical/qrcTechFile"
create_rc_corner -name RC_WORST -qrc_tech "$PDK_PATH/Base_PDK/PDK_CRN65GP_v1.0c_official_IC61_20101010/Assura/lvs_rcx/tn65cmsp007v1_1_3a/RC_QRC_crn65lp_1p9m_6x1z1u_alrdl_5corners_13a/RC_QRC_crn65lp_1p09m+alrdl_6x1z1u_rcworst/qrcTechFile"
#create_rc_corner -name RC_BEST -cap_table  "$PDK_DIGITAL/Back_End/lef/tcbn65gplus_200a/techfiles/captable/cln65g+_1p09m+alrdl_rcbest_top2.captable"
#create_rc_corner -name RC_TYP -cap_table  "$PDK_DIGITAL/Back_End/lef/tcbn65gplus_200a/techfiles/captable/cln65g+_1p09m+alrdl_typical_top2.captable"
#create_rc_corner -name RC_WORST -cap_table  "$PDK_DIGITAL/Back_End/lef/tcbn65gplus_200a/techfiles/captable/cln65g+_1p09m+alrdl_rcworst_top2.captable"

#####################################################################
# Process Corners
#####################################################################
## TYP TIMING: VDD 1.0 PROC TT TEMP 25
create_library_set -name libs_typ -timing [list  \
    "$PDK_DIGITAL/Front_End/timing_power_noise/NLDM/tcbn65gplus_200a/tcbn65gplustc.lib"  \
    "../../input/SRAM_macro/sram_A/sram_A_libs/sram_A_nldm_tt_1p00v_1p00v_25c_syn.lib" \
    "../../input/SRAM_macro/sram_B/sram_B_libs/sram_B_nldm_tt_1p00v_1p00v_25c_syn.lib" \
    ] -si [list  \
    "$PDK_DIGITAL/Back_End/celtic/tcbn65gplus_200a/tcbn65gplustc.cdb"  \
]

## MIN TIMING: VDD 1.1 PROC FF TEMP 0
create_library_set -name libs_min -timing [list  \
    "$PDK_DIGITAL/Front_End/timing_power_noise/NLDM/tcbn65gplus_200a/tcbn65gplusbc.lib"  \
    "../../input/SRAM_macro/sram_A/sram_A_libs/sram_A_nldm_ff_1p10v_1p10v_0c_syn.lib" \
    "../../input/SRAM_macro/sram_B/sram_B_libs/sram_B_nldm_ff_1p10v_1p10v_0c_syn.lib" \
    ] -si [list  \
    "$PDK_DIGITAL/Back_End/celtic/tcbn65gplus_200a/tcbn65gplusbc.cdb"  \
]

## MIN LT TIMING: VDD 1.1 PROC FF TEMP -40
create_library_set -name libs_min_lt -timing [list  \
    "$PDK_DIGITAL/Front_End/timing_power_noise/NLDM/tcbn65gplus_200a/tcbn65gpluslt.lib"  \
    "../../input/SRAM_macro/sram_A/sram_A_libs/sram_A_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
    "../../input/SRAM_macro/sram_B/sram_B_libs/sram_B_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
    ] -si [list  \
    "$PDK_DIGITAL/Back_End/celtic/tcbn65gplus_200a/tcbn65gpluslt.cdb"  \
]

## MAX TIMING: VDD 0.9 PROC SS TEMP 125
create_library_set -name libs_max -timing [list  \
    "$PDK_DIGITAL/Front_End/timing_power_noise/NLDM/tcbn65gplus_200a/tcbn65gpluswc.lib"  \
    "../../input/SRAM_macro/sram_A/sram_A_libs/sram_A_nldm_ss_0p90v_0p90v_125c_syn.lib" \
    "../../input/SRAM_macro/sram_B/sram_B_libs/sram_B_nldm_ss_0p90v_0p90v_125c_syn.lib" \
    ] -si [list  \
    "$PDK_DIGITAL/Back_End/celtic/tcbn65gplus_200a/tcbn65gpluswc.cdb"  \
]

#####################################################################
# Create PVT corner definitions
#####################################################################
create_opcond -name oc_typ    -process 1 -voltage 1.0 -temperature  25
create_opcond -name oc_min    -process 1 -voltage 1.1 -temperature  0
create_opcond -name oc_min_lt -process 1 -voltage 1.1 -temperature -40
create_opcond -name oc_max    -process 1 -voltage 0.9 -temperature 125

create_timing_condition -name tc_typ     -library_set libs_typ     -opcond oc_typ
create_timing_condition -name tc_min     -library_set libs_min     -opcond oc_min
create_timing_condition -name tc_min_lt  -library_set libs_min_lt  -opcond oc_min_lt
create_timing_condition -name tc_max     -library_set libs_max     -opcond oc_max

# For PNR experiments, use the hand-written top-level SDC directly rather than
# the Genus-exported SDC so timing assumptions stay easy to control.
create_constraint_mode  -name mode_normal -sdc_files ../../input/SDC/$TOPCELL.sdc

#####################################################################
# Merge with extraction corners
#####################################################################
create_delay_corner -name dc_typ    -timing_condition tc_typ     -rc_corner {RC_TYP}
create_delay_corner -name dc_min    -timing_condition tc_min     -rc_corner {RC_BEST}
create_delay_corner -name dc_min_lt -timing_condition tc_min_lt  -rc_corner {RC_BEST}
create_delay_corner -name dc_max    -timing_condition tc_max     -rc_corner {RC_WORST}

create_analysis_view -name av_normal_typ     -constraint_mode {mode_normal}  -delay_corner {dc_typ}
create_analysis_view -name av_normal_min     -constraint_mode {mode_normal}  -delay_corner {dc_min}
create_analysis_view -name av_normal_min_lt  -constraint_mode {mode_normal}  -delay_corner {dc_min_lt}
create_analysis_view -name av_normal_max     -constraint_mode {mode_normal}  -delay_corner {dc_max}

set_analysis_view \
	-setup {  av_normal_max   av_normal_typ     av_normal_min   av_normal_min_lt }  \
	-hold  {  av_normal_min   av_normal_min_lt  av_normal_typ   av_normal_max}







