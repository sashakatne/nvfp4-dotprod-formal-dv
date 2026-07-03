# VC Formal FPV: standalone proof of final_round_bf16 vs the golden rounder.
# Isolates the nonlinear RNE/normalize logic so it proves independently; the top
# AG proof blackboxes this module and assumes its guarantee.
set_fml_appmode FPV
set design final_round_bf16
read_file -top $design -format sverilog -sva -vcs {-f ../RTL/filelist_round_bf16}
create_clock -name vclk -period 100
sim_run -stable
sim_save_reset
check_fv -block
report_fv -list
puts "FPV_RUN_ROUND_BF16_DONE"
quit -f
