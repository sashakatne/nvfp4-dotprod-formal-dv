#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
normalizer="${here}/../uvm_normalize.sh"
fails=0

ok()   { echo "ok  $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# Source the normalizer (must not execute side effects on source)
# shellcheck source=../uvm_normalize.sh
source "$normalizer"

# ---------- build realistic 7-segment raw fixture ----------
# Each segment: UVM banner with +UVM_TESTNAME=<name>, SCOREBOARD line, UVM Report Summary block.
make_segment() {
  local name="$1" matched="$2" mismatched="$3" leftover="$4" err="$5" fatal="$6"
  cat <<EOF
# vsim invocation echoes the testname arg
+UVM_TESTNAME=${name}
UVM_INFO dotprod_seq_tb.sv(42) @ 0: reporter [RNTST] Running test ${name}...
UVM_INFO dotprod_scoreboard.sv(83) @ 1000ns: uvm_test_top.env.sb [SCB] SCOREBOARD matched=${matched} mismatched=${mismatched} leftover=${leftover}

--- UVM Report Summary ---

** Report counts by severity
UVM_INFO :  ${matched}
UVM_WARNING :    0
UVM_ERROR :    ${err}
UVM_FATAL :    ${fatal}

** Report counts by id
[SCB]   mismatched: ${mismatched}

EOF
}

# Happy-path fixture: 7 tests, all zeros
good_raw="$(mktemp)"
make_segment dotprod_random_test       500 0 0 0 0 >> "$good_raw"
make_segment dotprod_backpressure_test 200 0 0 0 0 >> "$good_raw"
make_segment dotprod_corner_test       100 0 0 0 0 >> "$good_raw"
make_segment dotprod_bf16_test         300 0 0 0 0 >> "$good_raw"
make_segment dotprod_bf16_corner_test   50 0 0 0 0 >> "$good_raw"
make_segment dotprod_nvfp4_test        250 0 0 0 0 >> "$good_raw"
make_segment dotprod_nvfp4_corner_test  75 0 0 0 0 >> "$good_raw"

good_out="$(normalize_uvm "$good_raw")"

# Must have exactly 7 TEST lines
n_test_lines=$(echo "$good_out" | grep -c '^TEST ' || true)
[ "$n_test_lines" -eq 7 ] \
  && ok  "good: 7 TEST lines" \
  || fail "good: expected 7 TEST lines, got ${n_test_lines}"

# All 7 test names present in order
expected_names=(
  dotprod_random_test
  dotprod_backpressure_test
  dotprod_corner_test
  dotprod_bf16_test
  dotprod_bf16_corner_test
  dotprod_nvfp4_test
  dotprod_nvfp4_corner_test
)
actual_names=( $(echo "$good_out" | awk '/^TEST / {print $2}') )
for i in "${!expected_names[@]}"; do
  exp="${expected_names[$i]}"
  got="${actual_names[$i]:-MISSING}"
  [ "$got" = "$exp" ] \
    && ok  "good: name[$i]=${exp}" \
    || fail "good: name[$i] expected=${exp} got=${got}"
done

# All counters should be zero
bad_counters=$(echo "$good_out" | grep -E 'mismatched=[1-9]|leftover=[1-9]|UVM_ERROR=[1-9]|UVM_FATAL=[1-9]' || true)
[ -z "$bad_counters" ] \
  && ok  "good: no non-zero failure counters" \
  || fail "good: unexpected non-zero counters: ${bad_counters}"

# ---------- NEGATIVE fixture: one segment with mismatched=1 and UVM_ERROR=1 ----------
neg_raw="$(mktemp)"
make_segment dotprod_random_test 499 1 0 1 0 >> "$neg_raw"

neg_out="$(normalize_uvm "$neg_raw")"

neg_line=$(echo "$neg_out" | grep '^TEST dotprod_random_test' || true)
[ -n "$neg_line" ] \
  && ok  "neg: TEST line present" \
  || fail "neg: no TEST line for dotprod_random_test"

echo "$neg_line" | grep -q 'mismatched=1' \
  && ok  "neg: mismatched=1 propagated" \
  || fail "neg: mismatched=1 not found in: ${neg_line}"

echo "$neg_line" | grep -q 'UVM_ERROR=1' \
  && ok  "neg: UVM_ERROR=1 propagated" \
  || fail "neg: UVM_ERROR=1 not found in: ${neg_line}"

# Confirm checker's reject regex fires on the negative output
echo "$neg_line" | grep -qE 'mismatched=[1-9]|leftover=[1-9]|UVM_ERROR=[1-9]|UVM_FATAL=[1-9]' \
  && ok  "neg: checker reject regex matches bad line" \
  || fail "neg: checker reject regex should fire but did not"

# ---------- Cross-check: good output satisfies checker contract ----------
# Check 1: contains 'TEST '
echo "$good_out" | grep -q 'TEST ' \
  && ok  "checker-compat: good output contains 'TEST '" \
  || fail "checker-compat: 'TEST ' missing from good output"

# Check 2: no reject-pattern lines in good output
bad=$(echo "$good_out" | grep -E 'mismatched=[1-9]|leftover=[1-9]|UVM_ERROR=[1-9]|UVM_FATAL=[1-9]' || true)
[ -z "$bad" ] \
  && ok  "checker-compat: no reject-pattern lines in good output" \
  || fail "checker-compat: reject-pattern hit in good output: ${bad}"

# ---------- MULTI-SEGMENT negative: only segment 4 (dotprod_bf16_test) is dirty ----------
# 7 segments: only seg4 has mismatched=1/UVM_ERROR=1; the other 6 are clean.
# Proves no cross-segment contamination.
multi_raw="$(mktemp)"
make_segment dotprod_random_test       500 0 0 0 0 >> "$multi_raw"
make_segment dotprod_backpressure_test 200 0 0 0 0 >> "$multi_raw"
make_segment dotprod_corner_test       100 0 0 0 0 >> "$multi_raw"
make_segment dotprod_bf16_test         300 1 0 1 0 >> "$multi_raw"   # dirty: mismatched=1 UVM_ERROR=1
make_segment dotprod_bf16_corner_test   50 0 0 0 0 >> "$multi_raw"
make_segment dotprod_nvfp4_test        250 0 0 0 0 >> "$multi_raw"
make_segment dotprod_nvfp4_corner_test  75 0 0 0 0 >> "$multi_raw"

multi_out="$(normalize_uvm "$multi_raw")"

# seg4 (dotprod_bf16_test) must carry mismatched=1 and UVM_ERROR=1
seg4_line=$(echo "$multi_out" | grep '^TEST dotprod_bf16_test ' || true)
[ -n "$seg4_line" ] \
  && ok  "multi-seg: seg4 TEST line present" \
  || fail "multi-seg: seg4 TEST line missing"
echo "$seg4_line" | grep -q 'mismatched=1' \
  && ok  "multi-seg: seg4 mismatched=1 propagated" \
  || fail "multi-seg: seg4 mismatched=1 not found in: ${seg4_line}"
echo "$seg4_line" | grep -q 'UVM_ERROR=1' \
  && ok  "multi-seg: seg4 UVM_ERROR=1 propagated" \
  || fail "multi-seg: seg4 UVM_ERROR=1 not found in: ${seg4_line}"

# The other 6 must be clean (mismatched=0 UVM_ERROR=0) - no cross-segment bleed
clean_tests=(
  dotprod_random_test
  dotprod_backpressure_test
  dotprod_corner_test
  dotprod_bf16_corner_test
  dotprod_nvfp4_test
  dotprod_nvfp4_corner_test
)
for tname in "${clean_tests[@]}"; do
  tline=$(echo "$multi_out" | grep "^TEST ${tname} " || true)
  if [ -z "$tline" ]; then
    fail "multi-seg: ${tname} TEST line missing"
  elif echo "$tline" | grep -qE 'mismatched=[1-9]|UVM_ERROR=[1-9]'; then
    fail "multi-seg: cross-segment bleed into ${tname}: ${tline}"
  else
    ok  "multi-seg: ${tname} is clean (no bleed)"
  fi
done

# ---------- Cleanup ----------
rm -f "$good_raw" "$neg_raw" "$multi_raw"

echo "---"
[ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "${fails} FAILED"; exit 1; }
