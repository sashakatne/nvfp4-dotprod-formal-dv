# VC Formal FPV: standalone proof of align_bf16 lane placement vs the golden
# ref_align_bf16_lane. Per-lane barrel-shift equivalence; composes with the
# accumulator adds to give sum_bf16 == golden acc.
set_fml_appmode FPV
set design align_bf16
read_file -top $design -format sverilog -sva -vcs {-f ../RTL/filelist_align_bf16}
create_clock -name vclk -period 100
sim_run -stable
sim_save_reset
check_fv -block
report_fv -list
puts "FPV_RUN_ALIGN_BF16_DONE"
quit -f
