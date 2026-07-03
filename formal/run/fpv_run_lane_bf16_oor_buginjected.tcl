# VC Formal FPV, bug-injected: BF16 lane proof with BUG_OOR must FALSIFY the
# lane equivalence (proves the out-of-range guard has teeth). The injected bug
# clears is_oor in front_end_bf16, restoring the old silently-wrong behavior for
# out-of-window normals; the golden still flags them, so a_product_matches_ref
# (and a_oor_forces_invalid_nan) falsify for any out-of-window operand.
set_fml_appmode FPV
set design mul_lane_bf16
read_file -top $design -format sverilog -sva \
  -vcs {-f ../RTL/filelist_lane_bf16 +define+BUG_OOR}
create_clock -name vclk -period 100
sim_run -stable
sim_save_reset
check_fv -block
report_fv -list
puts "FPV_RUN_LANE_BF16_OOR_BUGINJECTED_DONE"
quit -f
