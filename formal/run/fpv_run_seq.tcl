set_fml_appmode FPV
set design dotprod_seq
read_file -top $design -format sverilog -sva -vcs {-f ../RTL/filelist_seq}
create_clock clk -period 100
create_reset rst_n -sense low
sim_run -stable
sim_save_reset
check_fv -block
report_fv -list
puts "FPV_RUN_SEQ_DONE"
quit -f
