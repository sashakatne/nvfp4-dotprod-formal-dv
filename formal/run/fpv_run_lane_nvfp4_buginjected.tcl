# VC Formal FPV, bug-injected: NVFP4 lane proof with BUG_INJECTION must FALSIFY
# a_product_matches_ref (and a_decode_matches_ref if present). The injected bug
# maps the 6.0 pattern {ee,m}==3'b111 to mag_int=8 instead of 12.
set_fml_appmode FPV
set design mul_lane_nvfp4
read_file -top $design -format sverilog -sva \
  -vcs {-f ../RTL/filelist_lane_nvfp4 +define+BUG_INJECTION}
create_clock -name vclk -period 100
sim_run -stable
sim_save_reset
check_fv -block
report_fv -list
puts "FPV_RUN_LANE_NVFP4_BUGINJECTED_DONE"
quit -f
