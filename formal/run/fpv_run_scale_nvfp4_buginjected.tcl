# VC Formal FPV, bug-injected: NVFP4 scale proof with BUG_SCALE must FALSIFY
# a_exp. The injected bug uses k = exp - 9 (off-by-one) instead of exp - 10
# for normal UE4M3 inputs.
set_fml_appmode FPV
set design scale_mul_nvfp4
read_file -top $design -format sverilog -sva \
  -vcs {-f ../RTL/filelist_scale_nvfp4 +define+BUG_SCALE}
create_clock -name vclk -period 100
sim_run -stable
sim_save_reset
check_fv -block
report_fv -list
puts "FPV_RUN_SCALE_NVFP4_BUGINJECTED_DONE"
quit -f
