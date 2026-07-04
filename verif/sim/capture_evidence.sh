#!/usr/bin/env bash
# capture_evidence.sh - run UVM regression + coverage and write curated evidence.
# Run from verif/sim on the farm (vsim/vcover must be on PATH).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p transcripts coverage

raw="$(mktemp -d)"
trap 'rm -rf "${raw}"' EXIT

# ---------- UVM regression (run.do runs all 7 tests + merges + coverage) ----------
echo "RUN uvm regression"
vsim -c -do run.do > "${raw}/uvm.raw" 2>&1 || true

# Normalize raw output into the per-test contract format check_evidence.sh requires.
# shellcheck source=./uvm_normalize.sh
source "$(dirname "$0")/uvm_normalize.sh"

{
  grep -m1 -iE 'questa|version' "${raw}/uvm.raw" || echo "Tool version: (not printed)"
  echo "----- per-test normalized summary -----"
  normalize_uvm "${raw}/uvm.raw"
  echo "----- raw tool evidence -----"
  grep -iE 'SCOREBOARD|UVM Report Summary|UVM_ERROR|UVM_FATAL' "${raw}/uvm.raw" || true
} > transcripts/m5_uvm_regression.log

echo "capture_evidence(uvm): wrote transcripts/m5_uvm_regression.log"

# ---------- Coverage (run.do already merged + applied waivers) ----------
echo "RUN coverage report"
# If merged_excl.ucdb was produced by run.do, report directly.
# Otherwise re-apply waivers and generate it.
if [ ! -f merged_excl.ucdb ]; then
  echo "  merged_excl.ucdb not found; re-applying waivers"
  vsim -c -viewcov merged.ucdb \
    -do "do coverage_waivers.do; coverage save merged_excl.ucdb; quit -f" \
    > "${raw}/covview.raw" 2>&1 || true
fi

vcover report -summary merged_excl.ucdb > "${raw}/covreport.raw" 2>&1 || true

{
  grep -m1 -iE 'questa|version' "${raw}/covreport.raw" || echo "Tool version: (not printed)"
  echo "----- merged coverage summary (merged_excl.ucdb) -----"
  cat "${raw}/covreport.raw"
} > coverage/coverage_summary_m5.txt

echo "capture_evidence(cov): wrote coverage/coverage_summary_m5.txt"
echo "capture_evidence: done"
