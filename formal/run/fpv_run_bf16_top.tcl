# VC Formal FPV: BF16 top assume-guarantee proof (pre-round boundary).
# The 8 mul_lane_bf16 instances are blackboxed; the bound SVA assumes each lane
# output equals ref_mul_bf16 and proves the DUT's LINEAR reduction (fixed-point
# accumulate + special ladder) equals the golden pre-round reduction. The
# rounded-result equivalence then follows by transitivity with the standalone
# rounder proof. Asserting before the round keeps the nonlinear rounder network
# off both sides of the miter (the in-cone rounder variants went inconclusive).
set_fml_appmode FPV
set design dotprod_top

# set_blackbox must be issued before read_file; -designs blackboxes all
# instances of the named module.
set_blackbox -designs {mul_lane_bf16}

read_file -top $design -format sverilog -sva -vcs {-f ../RTL/filelist_bf16_top}

# Combinational DUV: named virtual clock, no reset.
create_clock -name vclk -period 100
sim_run -stable
sim_save_reset

puts "BLACKBOX_DESIGNS=[get_blackbox -designs]"
puts "BLACKBOX_CELLS=[get_blackbox -cells]"

check_fv -block
report_fv -list
puts "FPV_RUN_BF16_TOP_DONE"
quit -f
