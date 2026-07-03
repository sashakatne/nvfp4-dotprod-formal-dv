if {[file exists work]} { vdel -all }
vlib work

# RTL + reference (unified INT8/BF16/NVFP4 sequential DUT and its datapath).
vlog -sv +incdir+../../ref +incdir+../../rtl \
     ../../rtl/dotprod_pkg.sv \
     ../../rtl/front_end_int8.sv ../../rtl/mul_lane.sv ../../rtl/align_to_fixed.sv \
     ../../rtl/exact_acc_tree.sv ../../rtl/final_round.sv \
     ../../rtl/front_end_bf16.sv ../../rtl/mul_lane_bf16.sv ../../rtl/align_bf16.sv \
     ../../rtl/special_case_bf16.sv ../../rtl/final_round_bf16.sv \
     ../../rtl/front_end_nvfp4.sv ../../rtl/mul_lane_nvfp4.sv ../../rtl/align_nvfp4.sv \
     ../../rtl/scale_mul_nvfp4.sv ../../rtl/final_round_nvfp4.sv \
     ../../rtl/dotprod_seq.sv

# UVM interface + package (needs uvm)
vlog -sv +incdir+../uvm ../uvm/dotprod_if.sv ../uvm/dotprod_uvm_pkg.sv

# TB top
vlog -sv +incdir+../uvm ../tb/dotprod_seq_tb.sv

# Instrument coverage on the sequential DUT once.
vopt dotprod_seq_tb -o tb_opt +acc +cover=sbfec+dotprod_seq -L mtiUvm

# Run each test as its own sim, saving a per-test ucdb.
proc run_test {name ucdb} {
  vsim -c tb_opt -coverage -L mtiUvm +UVM_NO_RELNOTES +UVM_TESTNAME=$name \
       -do "set NoQuitOnFinish 1; onbreak {resume}; run -all; coverage save $ucdb; quit -sim"
}

run_test dotprod_random_test        cov_int8_random.ucdb
run_test dotprod_backpressure_test  cov_int8_backpressure.ucdb
run_test dotprod_corner_test        cov_int8_corner.ucdb
run_test dotprod_bf16_test          cov_bf16_random.ucdb
run_test dotprod_bf16_corner_test   cov_bf16_corner.ucdb
run_test dotprod_nvfp4_test         cov_nvfp4_random.ucdb
run_test dotprod_nvfp4_corner_test  cov_nvfp4_corner.ucdb

# Merge, apply waivers, and report.
vcover merge merged.ucdb \
  cov_int8_random.ucdb cov_int8_backpressure.ucdb cov_int8_corner.ucdb \
  cov_bf16_random.ucdb cov_bf16_corner.ucdb \
  cov_nvfp4_random.ucdb cov_nvfp4_corner.ucdb
vsim -c -viewcov merged.ucdb -do "do coverage_waivers.do; coverage save merged_excl.ucdb; quit -f"
vcover report -summary merged_excl.ucdb
quit -f
