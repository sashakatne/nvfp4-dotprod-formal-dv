#!/usr/bin/env bash
set -euo pipefail

mkdir -p doc/final_report/assets/figures
mkdir -p doc/final_report/assets/waveforms

convert_svg() {
  local src="$1"
  local dst="$2"
  rsvg-convert -f pdf -o "$dst" "$src"
}

convert_svg doc/architecture_dut.svg doc/final_report/assets/figures/architecture_dut.pdf
convert_svg doc/architecture_seq_dut.svg doc/final_report/assets/figures/architecture_seq_dut.pdf
convert_svg doc/architecture_bf16_dut.svg doc/final_report/assets/figures/architecture_bf16_dut.pdf
convert_svg doc/architecture_nvfp4_dut.svg doc/final_report/assets/figures/architecture_nvfp4_dut.pdf
convert_svg doc/architecture_uvm_tb.svg doc/final_report/assets/figures/architecture_uvm_tb.pdf
convert_svg doc/architecture_tb.svg doc/final_report/assets/figures/architecture_tb.pdf

python3 doc/final_report/scripts/vcd_to_svg.py \
  doc/final_report/generated/report_top_modes.vcd \
  doc/final_report/assets/waveforms/top_modes.svg \
  --title "Combinational top: INT8, BF16, NVFP4, and NaN-scale cases" \
  --signals case_id mode_bits result expected_result status_invalid status_is_nan status_is_inf sat

python3 doc/final_report/scripts/vcd_to_svg.py \
  doc/final_report/generated/report_seq_clean.vcd \
  doc/final_report/assets/waveforms/seq_clean.svg \
  --title "Sequential wrapper: clean backpressure hold" \
  --signals clk rst_n in_valid in_ready out_valid out_ready result report_assert_failed

python3 doc/final_report/scripts/vcd_to_svg.py \
  doc/final_report/generated/report_seq_bug.vcd \
  doc/final_report/assets/waveforms/seq_bug.svg \
  --title "Sequential wrapper: bug-injected p_hold_stable failure" \
  --signals clk rst_n in_valid in_ready out_valid out_ready result report_assert_failed

convert_svg doc/final_report/assets/waveforms/top_modes.svg doc/final_report/assets/waveforms/top_modes.pdf
convert_svg doc/final_report/assets/waveforms/seq_clean.svg doc/final_report/assets/waveforms/seq_clean.pdf
convert_svg doc/final_report/assets/waveforms/seq_bug.svg doc/final_report/assets/waveforms/seq_bug.pdf
