#!/usr/bin/env bash
# uvm_normalize.sh - sourced library; no top-level set -e; side-effect-free when sourced.
#
# Provides: normalize_uvm <raw_uvm_log>
#
# Reads the combined multi-segment raw vsim output (one segment per UVM test invocation)
# and prints exactly one normalized line per test of the form:
#   TEST <name> matched=<n> mismatched=<n> leftover=<n> UVM_ERROR=<n> UVM_FATAL=<n>
#
# Test-name detection: the most recent +UVM_TESTNAME=<name> echo or "Running test <name>"
# line before each SCOREBOARD line is used as the segment's test name.
#
# If a segment has no SCOREBOARD line, emits matched=NA mismatched=NA leftover=NA
# so humans see the gap rather than a false pass.
#
# Implemented in awk (POSIX/gawk compatible) - no interpreter dependencies beyond bash+awk.
# Safe under set -euo pipefail when sourced: awk exit is guarded with || true.

normalize_uvm() {
  local raw_log="${1:?normalize_uvm requires a raw log path}"

  awk '
  BEGIN {
    # Canonical test order
    n = 7
    order[0] = "dotprod_random_test"
    order[1] = "dotprod_backpressure_test"
    order[2] = "dotprod_corner_test"
    order[3] = "dotprod_bf16_test"
    order[4] = "dotprod_bf16_corner_test"
    order[5] = "dotprod_nvfp4_test"
    order[6] = "dotprod_nvfp4_corner_test"

    current    = ""
    in_summary = 0
  }

  # Helper: strip leading/trailing whitespace from a string.
  # (defined via gsub inline below)

  # Detect new segment: +UVM_TESTNAME=<name>
  /\+UVM_TESTNAME=/ {
    line = $0
    sub(/.*\+UVM_TESTNAME=/, "", line)   # drop everything up to and including the marker
    sub(/[[:space:]].*$/, "", line)       # trim trailing tokens
    name = line
    if (name != "") {
      _init_test(name)
      current    = name
      in_summary = 0
    }
    next
  }

  # Detect new segment: "Running test <name>" (strip trailing ... or whitespace)
  /Running test / {
    line = $0
    sub(/.*Running test[[:space:]]+/, "", line)
    sub(/[\.[:space:]].*$/, "", line)
    name = line
    if (name != "") {
      _init_test(name)
      current    = name
      in_summary = 0
    }
    next
  }

  # UVM Report Summary block starts
  /UVM Report Summary/ { in_summary = 1 }

  # Skip lines before any test name is seen
  current == "" { next }

  # SCOREBOARD line: grab matched/mismatched/leftover by splitting into tokens.
  # Field-based extraction avoids the greedy-match pitfall where "mismatched="
  # contains "matched=" as a suffix, causing sub(/.*matched=/) to overshoot.
  /SCOREBOARD/ && /matched=/ {
    nf = split($0, tokens, " ")
    for (ti = 1; ti <= nf; ti++) {
      tok = tokens[ti]
      if (tok ~ /^matched=[0-9]/) {
        sub(/^matched=/, "", tok); matched[current] = tok
      } else if (tok ~ /^mismatched=[0-9]/) {
        sub(/^mismatched=/, "", tok); mismatched[current] = tok
      } else if (tok ~ /^leftover=[0-9]/) {
        sub(/^leftover=/, "", tok); leftover[current] = tok
      }
    }
    next
  }

  # UVM_ERROR from the report summary block (colon-separated format)
  in_summary && /UVM_ERROR[[:space:]]*:/ {
    v = $0
    sub(/.*UVM_ERROR[[:space:]]*:[[:space:]]*/, "", v)
    sub(/[^0-9].*$/, "", v)
    if (v ~ /^[0-9]+$/) uvm_error[current] = v
  }

  # UVM_FATAL from the report summary block (colon-separated format)
  in_summary && /UVM_FATAL[[:space:]]*:/ {
    v = $0
    sub(/.*UVM_FATAL[[:space:]]*:[[:space:]]*/, "", v)
    sub(/[^0-9].*$/, "", v)
    if (v ~ /^[0-9]+$/) uvm_fatal[current] = v
  }

  END {
    for (i = 0; i < n; i++) {
      nm = order[i]
      if (nm in matched) {
        printf "TEST %s matched=%s mismatched=%s leftover=%s UVM_ERROR=%s UVM_FATAL=%s\n",
          nm, matched[nm], mismatched[nm], leftover[nm],
          uvm_error[nm], uvm_fatal[nm]
      }
    }
  }

  function _init_test(nm) {
    if (!(nm in matched)) {
      matched[nm]    = "NA"
      mismatched[nm] = "NA"
      leftover[nm]   = "NA"
      uvm_error[nm]  = "NA"
      uvm_fatal[nm]  = "NA"
    }
  }
  ' "$raw_log" || true
}
