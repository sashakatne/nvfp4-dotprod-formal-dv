# VC Formal FPV, bug-injected: standalone rounder proof with BUG_BF16_TRUNC must
# FALSIFY a_numeric_round (the injected truncate-instead-of-RNE bug lives inside
# final_round_bf16, which this proof checks directly).
set_fml_appmode FPV
set design final_round_bf16
read_file -top $design -format sverilog -sva \
  -vcs {-f ../RTL/filelist_round_bf16 +define+BUG_BF16_TRUNC}
create_clock -name vclk -period 100
sim_run -stable
sim_save_reset
check_fv -block
report_fv -list
puts "FPV_RUN_ROUND_BF16_BUGINJECTED_DONE"
quit -f
