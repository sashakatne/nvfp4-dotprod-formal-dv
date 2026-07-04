#!/usr/bin/env bash
set -uo pipefail
logs_dir="${1:?usage: check_evidence.sh <logs_dir> <uvm_log> <cov_summary>}"
uvm_log="${2:?}"
cov_summary="${3:?}"
err() { echo "check_evidence: $*" >&2; exit 1; }

shopt -s nullglob
tails=("${logs_dir}"/*.log)
[ "${#tails[@]}" -gt 0 ] || err "no formal tails in ${logs_dir}"

for f in "${tails[@]}"; do
  grep -qi 'version' "$f" || err "$f: missing tool-version marker"
  # real assertion-table row = a proven/falsified line that is NOT the verdict line
  grep -E 'proven|falsified' "$f" | grep -qv 'EVIDENCE_VERDICT:' \
    || err "$f: empty assertion table"
  v="$(grep -m1 '^EVIDENCE_VERDICT:' "$f")" || err "$f: no EVIDENCE_VERDICT line"
  kind="$(sed -n 's/.* kind=\([a-z]*\).*/\1/p' <<<"$v")"
  fals="$(sed -n 's/.* falsified=\([0-9]*\).*/\1/p' <<<"$v")"
  [ -n "$kind" ] || err "$f: could not parse kind= from EVIDENCE_VERDICT line"
  [ -n "$fals" ] || err "$f: could not parse falsified= from EVIDENCE_VERDICT line"
  case "$kind" in
    clean) [ "$fals" = "0" ] || err "$f: clean job has falsified=$fals (expected 0)";;
    bug)   [ "${fals:-0}" -ge 1 ] || err "$f: bug job has falsified=$fals (expected >=1)";;
    *)     err "$f: bad kind='$kind'";;
  esac
done

# UVM: no mismatch/leftover/errors on any TEST line
grep -q 'TEST ' "$uvm_log" || err "uvm log has no TEST lines"
# All 7 UVM tests must be present — a missing test (crash/timeout) must not pass silently.
n_tests=$(grep -c '^TEST ' "$uvm_log" 2>/dev/null || true)
[ "${n_tests:-0}" -eq 7 ] || err "uvm log: expected 7 TEST lines, found ${n_tests:-0}"
# A test that truly ran has numeric counters; NA means missing scoreboard output.
grep -E '^TEST ' "$uvm_log" | grep -q 'NA' && err "uvm log: a TEST line has NA counters (a test did not report results)" || true
grep -E 'mismatched=[1-9]|leftover=[1-9]|UVM_ERROR=[1-9]|UVM_FATAL=[1-9]' "$uvm_log" \
  && err "uvm log shows a mismatch/leftover/error"

# Coverage: must state 100.00%
grep -q '100.00%' "$cov_summary" || err "coverage summary is not 100.00%"

echo "check_evidence: OK (${#tails[@]} formal tails, uvm clean, coverage 100.00%)"
