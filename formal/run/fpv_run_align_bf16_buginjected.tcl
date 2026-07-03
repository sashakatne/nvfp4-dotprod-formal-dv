# VC Formal FPV, bug-injected: standalone align proof with BUG_ALIGN must
# FALSIFY a_align_lane (the off-by-one shift lives in align_bf16, checked here
# directly against ref_align_bf16_lane).
set_fml_appmode FPV
set design align_bf16
read_file -top $design -format sverilog -sva \
  -vcs {-f ../RTL/filelist_align_bf16 +define+BUG_ALIGN}
create_clock -name vclk -period 100
sim_run -stable
sim_save_reset
check_fv -block
report_fv -list
puts "FPV_RUN_ALIGN_BF16_BUGINJECTED_DONE"
quit -f
