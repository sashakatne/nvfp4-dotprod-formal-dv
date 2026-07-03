set_fml_appmode FPV
set design special_case_bf16
read_file -top $design -format sverilog -sva -vcs {-f ../RTL/filelist_special_bf16}
create_clock -name vclk -period 100
sim_run -stable
sim_save_reset
check_fv -block
report_fv -list
puts "FPV_RUN_SPECIAL_BF16_DONE"
quit -f
