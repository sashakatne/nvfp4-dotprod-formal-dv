proc compile_report {bug} {
  if {[file exists work]} {
    vdel -all
  }
  vlib work

  set defs ""
  if {$bug} {
    set defs "+define+BUG_INJECTION"
  }

  vlog -sv +incdir+ref +incdir+rtl $defs \
    rtl/dotprod_pkg.sv \
    rtl/front_end_int8.sv rtl/mul_lane.sv rtl/align_to_fixed.sv \
    rtl/exact_acc_tree.sv rtl/final_round.sv \
    rtl/front_end_bf16.sv rtl/mul_lane_bf16.sv rtl/align_bf16.sv \
    rtl/special_case_bf16.sv rtl/final_round_bf16.sv \
    rtl/front_end_nvfp4.sv rtl/mul_lane_nvfp4.sv rtl/align_nvfp4.sv \
    rtl/scale_mul_nvfp4.sv rtl/final_round_nvfp4.sv \
    rtl/dotprod_top.sv rtl/dotprod_seq.sv \
    doc/final_report/scripts/report_top_modes_tb.sv \
    doc/final_report/scripts/report_seq_wave_tb.sv
}

proc run_vcd {opt top out signals} {
  file mkdir doc/final_report/generated
  set cmd "set NoQuitOnFinish 1; vcd file $out;"
  foreach sig $signals {
    append cmd " vcd add $sig;"
  }
  append cmd " run -all; vcd flush; quit -sim"
  vsim -c $opt -do $cmd
}

compile_report 0
vopt report_top_modes_tb -o report_top_modes_opt +acc
run_vcd report_top_modes_opt report_top_modes_tb doc/final_report/generated/report_top_modes.vcd {
  /report_top_modes_tb/case_id
  /report_top_modes_tb/mode_bits
  /report_top_modes_tb/result
  /report_top_modes_tb/expected_result
  /report_top_modes_tb/status_invalid
  /report_top_modes_tb/status_is_nan
  /report_top_modes_tb/status_is_inf
  /report_top_modes_tb/sat
}

vopt report_seq_wave_tb -o report_seq_clean_opt +acc
run_vcd report_seq_clean_opt report_seq_wave_tb doc/final_report/generated/report_seq_clean.vcd {
  /report_seq_wave_tb/clk
  /report_seq_wave_tb/rst_n
  /report_seq_wave_tb/in_valid
  /report_seq_wave_tb/in_ready
  /report_seq_wave_tb/out_valid
  /report_seq_wave_tb/out_ready
  /report_seq_wave_tb/result
  /report_seq_wave_tb/report_assert_failed
}

compile_report 1
vopt report_seq_wave_tb -o report_seq_bug_opt +acc
run_vcd report_seq_bug_opt report_seq_wave_tb doc/final_report/generated/report_seq_bug.vcd {
  /report_seq_wave_tb/clk
  /report_seq_wave_tb/rst_n
  /report_seq_wave_tb/in_valid
  /report_seq_wave_tb/in_ready
  /report_seq_wave_tb/out_valid
  /report_seq_wave_tb/out_ready
  /report_seq_wave_tb/result
  /report_seq_wave_tb/report_assert_failed
}

quit -f
