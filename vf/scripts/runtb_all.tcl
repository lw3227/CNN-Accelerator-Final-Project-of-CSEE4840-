##################################################
# Run all three system_e2e variants back-to-back: behav + syn + pnr.
# Invoked via `vsim -c -do runtb_all.tcl`.
##################################################
source [file join [file dirname [info script]] runtb_system_e2e_behav.tcl]
source [file join [file dirname [info script]] runtb_system_e2e_syn.tcl]
source [file join [file dirname [info script]] runtb_system_e2e_pnr.tcl]

exit
