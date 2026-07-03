set_fml_appmode FPV
set design final_round_nvfp4
read_file -top $design -format sverilog -sva -vcs {-f ../RTL/filelist_round_nvfp4}
create_clock -name vclk -period 100
sim_run -stable
sim_save_reset
check_fv -block
report_fv -list
puts "FPV_RUN_ROUND_NVFP4_DONE"
quit -f
