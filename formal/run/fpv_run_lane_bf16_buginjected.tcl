# VC Formal FPV, bug-injected: BF16 lane proof with BUG_INJECTION must FALSIFY
# a lane assertion (proves the lane proof has teeth). The injected bug treats
# BF16 subnormals as normal instead of flushing to zero.
set_fml_appmode FPV
set design mul_lane_bf16
read_file -top $design -format sverilog -sva \
  -vcs {-f ../RTL/filelist_lane_bf16 +define+BUG_INJECTION}
create_clock -name vclk -period 100
sim_run -stable
sim_save_reset
check_fv -block
report_fv -list
puts "FPV_RUN_LANE_BF16_BUGINJECTED_DONE"
quit -f
