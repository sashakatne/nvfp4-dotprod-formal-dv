#!/usr/bin/env bash
# Sourced helper: derive formal verdict counts from the VC Formal Summary Results block.
# Usage: source evidence_counts.sh
#        read -r proven falsified covered < <(derive_verdict_counts <rawfile>)
#
# Parses the authoritative "Summary Results" section that VC Formal prints at the end of
# report_fv -list output, extracting the exact integer from lines of the form:
#   - # proven       : N
#   - # falsified    : N
#   - # covered      : N
# "# uncoverable" is intentionally excluded.  If multiple matches exist, take the last
# one (report_fv -list summary is printed last and is authoritative).

derive_verdict_counts() {
  local rawfile="$1"

  local proven falsified covered
  proven=$(grep -aoE '#[[:space:]]*proven[[:space:]]*:[[:space:]]*[0-9]+' \
             "$rawfile" 2>/dev/null || true)
  proven=$(echo "$proven" | tail -1 | grep -oE '[0-9]+$' || true)

  falsified=$(grep -aoE '#[[:space:]]*falsified[[:space:]]*:[[:space:]]*[0-9]+' \
               "$rawfile" 2>/dev/null || true)
  falsified=$(echo "$falsified" | tail -1 | grep -oE '[0-9]+$' || true)

  covered=$(grep -aoE '#[[:space:]]*covered[[:space:]]*:[[:space:]]*[0-9]+' \
              "$rawfile" 2>/dev/null || true)
  covered=$(echo "$covered" | tail -1 | grep -oE '[0-9]+$' || true)

  echo "${proven:-0} ${falsified:-0} ${covered:-0}"
}
