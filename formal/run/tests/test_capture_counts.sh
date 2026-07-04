#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
helper="${here}/../evidence_counts.sh"
# shellcheck source=../evidence_counts.sh
source "$helper"

fails=0
ok()   { echo "ok  $1"; }
fail() { echo "FAIL $1"; fails=$((fails+1)); }

# ---------- CLEAN fixture ----------
# Real VC Formal format with Summary Results block.
# Column header contains "Proven Falsified Covered" and there's a legend "Falsified : 0".
# Parser must read the Summary block, not count lines.
# Expected: proven=2, falsified=0, covered=0
clean_raw="$(mktemp)"
cat > "$clean_raw" << 'EOF'
Synopsys VC Formal Version V-2023.12-SP2-3
Date: 2026-07-03 10:00:00
      Name                                    Type    Status    Proven Falsified Covered
      dotprod_top.a_result_matches_ref         assert  proven
      dotprod_top.a_nan_bypass                 assert  proven
      dotprod_top.c_int8_sat_unreachable       cover   unreachable
Falsified : 0
  Summary Results
   Property Summary: FPV
     - # found        : 2
     - # proven       : 2
     - # found        : 1
     - # uncoverable  : 1
     - # found        : 1
EOF

read -r p f c < <(derive_verdict_counts "$clean_raw")

[ "$p" -eq 2 ]  && ok  "clean: proven=2"     || fail "clean: proven expected 2, got ${p}"
[ "$f" -eq 0 ]  && ok  "clean: falsified=0"  || fail "clean: falsified expected 0, got ${f}"
[ "$c" -eq 0 ]  && ok  "clean: covered=0"    || fail "clean: covered expected 0, got ${c}"
# The critical assertion: summary legend line "Falsified : 0" must not corrupt the count.
[ "$f" -eq 0 ]  && ok  "clean: 'Falsified : 0' legend did not corrupt count" \
                || fail "clean: legend line corrupted falsified (BUG: raw-line counting)"

# ---------- BUG fixture ----------
# One assert falsified, one proven.  Summary legend "Falsified : 1" must not double-count.
# Expected: proven=1, falsified=1
bug_raw="$(mktemp)"
cat > "$bug_raw" << 'EOF'
Synopsys VC Formal Version V-2023.12-SP2-3
Date: 2026-07-03 10:01:00
      Name                                    Type    Status
      dotprod_top.a_result_matches_ref         assert  falsified
      dotprod_top.a_nan_bypass                 assert  proven
Falsified : 1
  Summary Results
   Property Summary: FPV
     - # found        : 2
     - # proven       : 1
     - # falsified    : 1
     - # found        : 1
EOF

read -r p f c < <(derive_verdict_counts "$bug_raw")

[ "$f" -ge 1 ]  && ok  "bug: falsified>=1"   || fail "bug: falsified expected >=1, got ${f}"
[ "$p" -ge 1 ]  && ok  "bug: proven>=1"      || fail "bug: proven expected >=1, got ${p}"

rm -f "$clean_raw" "$bug_raw"

# ---------- REAL LOG fixtures (authoritative regression pins) ----------
# These are captured from actual VC Formal farm runs and must match exactly.
fix_real="${here}/fixtures/real"

check_real() {
  local log="$1" exp_p="$2" exp_f="$3" exp_c="$4" label="$5"
  local p f c
  read -r p f c < <(derive_verdict_counts "${fix_real}/${log}")
  [ "$p" -eq "$exp_p" ] && ok  "${label}: proven=${exp_p}"     || fail "${label}: proven expected ${exp_p}, got ${p}"
  [ "$f" -eq "$exp_f" ] && ok  "${label}: falsified=${exp_f}"  || fail "${label}: falsified expected ${exp_f}, got ${f}"
  [ "$c" -eq "$exp_c" ] && ok  "${label}: covered=${exp_c}"    || fail "${label}: covered expected ${exp_c}, got ${c}"
}

check_real real_clean_int8.log        1  0  2  "real_clean_int8"
check_real real_bug_int8.log          0  1  2  "real_bug_int8"
check_real real_clean_lane_bf16.log  24  0 13  "real_clean_lane_bf16"

echo "---"
[ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "${fails} FAILED"; exit 1; }
