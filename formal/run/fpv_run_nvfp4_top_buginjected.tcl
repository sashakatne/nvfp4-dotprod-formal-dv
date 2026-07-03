# VC Formal FPV: NVFP4 top AG proof with BUG_NAN injected (Task 8 hook).
# Identical to fpv_run_nvfp4_top.tcl except +define+BUG_NAN is added to the
# vcs read_file arguments. Expected outcome: a_scale_nan_ref falsified.
set_fml_appmode FPV
set design dotprod_top

# set_blackbox must be issued before read_file; -designs blackboxes all
# instances of the named module.
set_blackbox -designs {mul_lane_nvfp4}

read_file -top $design -format sverilog -sva -vcs {+define+BUG_NAN -f ../RTL/filelist_nvfp4_top}

# Combinational DUV: named virtual clock, no reset.
create_clock -name vclk -period 100
sim_run -stable
sim_save_reset

puts "BLACKBOX_DESIGNS=[get_blackbox -designs]"
puts "BLACKBOX_CELLS=[get_blackbox -cells]"

check_fv -block
report_fv -list
puts "FPV_RUN_NVFP4_TOP_BUGINJECTED_DONE"
quit -f
