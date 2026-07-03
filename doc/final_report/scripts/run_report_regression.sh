#!/usr/bin/env bash
set -euo pipefail

repo_root=$(pwd)
out_dir="${1:-doc/final_report/generated/evidence}"
mkdir -p "$out_dir"

run_logged() {
  local name="$1"
  shift
  echo "RUN ${name}"
  ( "$@" ) >"${repo_root}/${out_dir}/${name}.log" 2>&1
}

run_logged directed_sim bash -c 'cd sim && vsim -c -do run.do'
run_logged uvm_regression bash -c 'cd verif/sim && vsim -c -do run.do'

formal_jobs=(
  fpv_run_top
  fpv_run_top_buginjected
  fpv_run_seq
  fpv_run_seq_buginjected
  fpv_run_lane_bf16
  fpv_run_align_bf16
  fpv_run_round_bf16
  fpv_run_special_bf16
  fpv_run_bf16_top
  fpv_run_bf16_top_buginjected
  fpv_run_lane_nvfp4
  fpv_run_lane_nvfp4_buginjected
  fpv_run_scale_nvfp4
  fpv_run_scale_nvfp4_buginjected
  fpv_run_round_nvfp4
  fpv_run_round_nvfp4_buginjected
  fpv_run_nvfp4_top
  fpv_run_nvfp4_top_buginjected
)

for job in "${formal_jobs[@]}"; do
  run_logged "$job" bash -c "cd formal/run && vcf -batch -f ${job}.tcl"
done

echo "REPORT_REGRESSION_DONE"
