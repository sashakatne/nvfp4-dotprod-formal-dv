# VC Formal FPV, bug-injected: dotprod_top with BUG_INT8_ROUND must FALSIFY
# the equivalence property (proves the proof has teeth).
set_fml_appmode FPV
set design dotprod_top

read_file -top $design -format sverilog -sva \
  -vcs {-f ../RTL/filelist +define+BUG_INT8_ROUND}

# Combinational DUV: named virtual clock, no reset.
create_clock -name vclk -period 100

sim_run -stable
sim_save_reset

check_fv -block
report_fv -list
puts "FPV_RUN_TOP_BUGINJECTED_DONE"
quit -f
