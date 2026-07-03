# Directed self-checking dot-product sim with coverage for the unified
# INT8/BF16 top. Coverage requires a vopt instrumentation pass (+cover) before
# vsim, then a coverage save on the optimized top.
if {[file exists work]} {
  vdel -all
}
vlib work

vlog -sv +incdir+../ref +cover \
     ../rtl/dotprod_pkg.sv \
     ../rtl/front_end_int8.sv ../rtl/mul_lane.sv ../rtl/align_to_fixed.sv \
     ../rtl/exact_acc_tree.sv ../rtl/final_round.sv \
     ../rtl/front_end_bf16.sv ../rtl/mul_lane_bf16.sv ../rtl/align_bf16.sv \
     ../rtl/special_case_bf16.sv ../rtl/final_round_bf16.sv \
     ../rtl/front_end_nvfp4.sv ../rtl/mul_lane_nvfp4.sv ../rtl/align_nvfp4.sv \
     ../rtl/scale_mul_nvfp4.sv ../rtl/final_round_nvfp4.sv \
     ../rtl/dotprod_top.sv \
     tb/dotprod_int8_directed_tb.sv tb/dotprod_bf16_directed_tb.sv \
     tb/dotprod_nvfp4_directed_tb.sv

# ---- INT8 directed run (instrumented, coverage saved) ----
vopt dotprod_int8_directed_tb -o int8_opt +acc +cover=sbfec+dotprod_top
vsim -c int8_opt -coverage
set NoQuitOnFinish 1
onbreak {resume}
run -all
coverage save dotprod_int8.ucdb
quit -sim

# ---- BF16 directed run (instrumented, coverage saved) ----
vopt dotprod_bf16_directed_tb -o bf16_opt +acc +cover=sbfec+dotprod_top
vsim -c bf16_opt -coverage
set NoQuitOnFinish 1
onbreak {resume}
run -all
coverage save dotprod_bf16.ucdb
quit -sim

# ---- NVFP4 directed run (instrumented, coverage saved) ----
vopt dotprod_nvfp4_directed_tb -o nvfp4_opt +acc +cover=sbfec+dotprod_top
vsim -c nvfp4_opt -coverage
set NoQuitOnFinish 1
onbreak {resume}
run -all
coverage save dotprod_nvfp4.ucdb
quit -sim

# ---- Merge and report ----
vcover merge dotprod_directed.ucdb dotprod_int8.ucdb dotprod_bf16.ucdb dotprod_nvfp4.ucdb
vcover report dotprod_directed.ucdb
quit -f
