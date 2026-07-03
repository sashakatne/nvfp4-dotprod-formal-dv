# VC Formal FPV, bug-injected: BF16 top AG proof with BUG_SPECIAL must FALSIFY
# the special-ladder equivalence (proves the top AG proof has teeth). The bug
# drops the Inf-minus-Inf case in special_case_bf16, which is IN-CONE for the
# top proof (only the lane multiplier is blackboxed), so +Inf/-Inf together
# yields the wrong special outcome and falsifies a_special_result_matches_ref.
set_fml_appmode FPV
set design dotprod_top

set_blackbox -designs {mul_lane_bf16}

read_file -top $design -format sverilog -sva \
  -vcs {-f ../RTL/filelist_bf16_top +define+BUG_SPECIAL}

create_clock -name vclk -period 100
sim_run -stable
sim_save_reset

puts "BLACKBOX_DESIGNS=[get_blackbox -designs]"
check_fv -block
report_fv -list
puts "FPV_RUN_BF16_TOP_BUGINJECTED_DONE"
quit -f
