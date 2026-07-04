#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
checker="${here}/../check_evidence.sh"
fix="${here}/fixtures"
fails=0
pass_case() { # dir should pass
  if bash "$checker" "$1" "$2" "$3" >/dev/null 2>&1; then echo "ok  $4"; else echo "FAIL(expected pass) $4"; fails=$((fails+1)); fi
}
fail_case() { # dir should fail — also print stderr for visibility
  if bash "$checker" "$1" "$2" "$3" >/dev/null 2>&1; then echo "FAIL(expected fail) $4"; fails=$((fails+1)); else echo "ok  $4"; fi
}

# Build a good UVM + coverage fixture on the fly — MUST have all 7 real test names.
tmp="$(mktemp -d)"
cat > "${tmp}/uvm_good.log" <<'EOF'
UVM report summary
TEST dotprod_random_test matched=500 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_backpressure_test matched=1000 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_corner_test matched=9 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_bf16_test matched=500 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_bf16_corner_test matched=10 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_nvfp4_test matched=500 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_nvfp4_corner_test matched=8 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
EOF
echo 'Total Coverage: 100.00%' > "${tmp}/cov_good.txt"

# good logs dir = clean_good + bug_good
good="$(mktemp -d)"; cp "${fix}/clean_good.log" "${fix}/bug_good.log" "${good}/"
pass_case "$good" "${tmp}/uvm_good.log" "${tmp}/cov_good.txt" "all-good"

# bad: clean job falsified
bad1="$(mktemp -d)"; cp "${fix}/clean_bad_falsified.log" "${bad1}/"
fail_case "$bad1" "${tmp}/uvm_good.log" "${tmp}/cov_good.txt" "clean-falsified-rejected"

# bad: empty assertion table
bad2="$(mktemp -d)"; cp "${fix}/empty_table.log" "${bad2}/"
fail_case "$bad2" "${tmp}/uvm_good.log" "${tmp}/cov_good.txt" "empty-table-rejected"

# bad: coverage not 100
badcov="$(mktemp -d)"; cp "${fix}/clean_good.log" "${fix}/bug_good.log" "${badcov}/"
echo 'Total Coverage: 93.58%' > "${tmp}/cov_bad.txt"
fail_case "$badcov" "${tmp}/uvm_good.log" "${tmp}/cov_bad.txt" "coverage-not-100-rejected"

# bad: UVM mismatch
baduvm="$(mktemp -d)"; cp "${fix}/clean_good.log" "${fix}/bug_good.log" "${baduvm}/"
printf 'TEST dotprod_random_test items=500 matched=499 mismatched=1 leftover=0 UVM_ERROR=1 UVM_FATAL=0\n' > "${tmp}/uvm_bad.log"
fail_case "$baduvm" "${tmp}/uvm_bad.log" "${tmp}/cov_good.txt" "uvm-mismatch-rejected"

# I2: only 6 TEST lines (one test missing) — must fail even though all are clean
cat > "${tmp}/uvm_6tests.log" <<'EOF'
UVM report summary
TEST dotprod_random_test matched=500 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_backpressure_test matched=1000 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_corner_test matched=9 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_bf16_test matched=500 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_bf16_corner_test matched=10 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_nvfp4_test matched=500 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
EOF
fail_case "$good" "${tmp}/uvm_6tests.log" "${tmp}/cov_good.txt" "uvm-6tests-rejected (I2 count)"

# I2: 7 TEST lines but one has NA counters (test launched, no scoreboard output) — must fail
cat > "${tmp}/uvm_na.log" <<'EOF'
UVM report summary
TEST dotprod_random_test matched=500 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_backpressure_test matched=1000 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_corner_test matched=9 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_bf16_test matched=500 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_bf16_corner_test matched=10 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_nvfp4_test matched=500 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0
TEST dotprod_nvfp4_corner_test matched=NA mismatched=NA leftover=NA UVM_ERROR=NA UVM_FATAL=NA
EOF
fail_case "$good" "${tmp}/uvm_na.log" "${tmp}/cov_good.txt" "uvm-na-counters-rejected (I2 NA)"

# I1: malformed EVIDENCE_VERDICT (uppercase kind=CLEAN) — must fail with parse error
bad_verdict="$(mktemp -d)"
cat > "${bad_verdict}/malformed_verdict.log" <<'EOF'
Synopsys VC Formal Version V-2023.12-SP2-3
Assertion                         Status
a_result_matches_ref              proven
EVIDENCE_VERDICT: job=fpv_run_top kind=CLEAN proven=1 falsified=0 covered=2
EOF
fail_case "$bad_verdict" "${tmp}/uvm_good.log" "${tmp}/cov_good.txt" "malformed-verdict-rejected (I1 parse)"

echo "---"; [ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
