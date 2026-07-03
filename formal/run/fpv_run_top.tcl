# VC Formal FPV: prove dotprod_top (INT8) == dotprod_ref (combinational, no clock)
set_fml_appmode FPV
set design dotprod_top

read_file -top $design -format sverilog -sva -vcs {-f ../RTL/filelist}

# Combinational DUV: no functional clock/reset in the RTL. Define a named
# virtual clock so the tool has an evaluation tick; no reset is declared.
create_clock -name vclk -period 100

sim_run -stable
sim_save_reset

check_fv -block
report_fv -list
puts "FPV_RUN_TOP_DONE"
quit -f
