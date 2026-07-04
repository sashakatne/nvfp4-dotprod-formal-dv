# Committed Evidence Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Commit curated, auditable text evidence for the M5 verification sweep so the reports' cited log/coverage files exist and prove the runs actually happened.

**Architecture:** Two committed capture scripts run the 22 formal jobs + 7 UVM tests on the farm and extract deterministic summary tails (with a machine-readable `EVIDENCE_VERDICT:` line above each real tool table). A committed checker validates the tails locally against fixtures and on the farm against real output. `.gitignore` flips to force-track exactly the cited files. Docs are reconciled where genuinely stale. Everything lands in one commit.

**Tech Stack:** bash (`set -euo pipefail`), grep/awk, Synopsys VC Formal (`vcf`), Siemens Questa (`vsim`/`vcover`), git. Farm access: `ssh katnemo` (mo.ece.pdx.edu).

## Global Constraints

- **No RTL/SVA/UVM/tcl source changes.** Evidence, scripts, `.gitignore`, and docs only. Copy the list of 22 tcl job names verbatim; do not rename or add jobs.
- **No binaries tracked.** Never stage `*.ucdb`, `*.wlf`, `*.fsdb`, `*.vpd`, `*.daidir/`, `csrc/`, `simv*`. Force-track only the 25 named text files.
- **Curated tails keep hard-to-fake markers:** tool-version banner line, run timestamp, model gate/input counts (where the tool prints them), and the full per-assertion status table. Never hand-edit a tail.
- **Farm tool versions are authoritative** and must appear verbatim in tails: Synopsys VC Formal + Questa 2024.2 (do not invent version strings; capture whatever the farm prints).
- **Single commit** at the end containing all changes.
- **Preserve deliberate report layering:** `FinalReport_M5.md` §2 tables are the historical 18-job sign-off snapshot (11 clean + 7 bug); §6b documents growth to 22. Do NOT rewrite the §2 tables. Fix only genuinely-stale text (line 29) and the incomplete §6 command list.
- **The 25 committed files** (exact paths):
  - `formal/run/logs/RC_SUMMARY_m5.txt`
  - `formal/run/logs/<job>.log` for each of the 22 jobs (11 clean + 11 bug-injected, list in Task 2)
  - `verif/sim/transcripts/m5_uvm_regression.log`
  - `verif/sim/coverage/coverage_summary_m5.txt`

---

## File Structure

**New files (committed):**
- `formal/run/capture_evidence.sh` — runs 22 formal jobs, writes curated tails + `RC_SUMMARY_m5.txt`.
- `formal/run/check_evidence.sh` — validates all committed evidence (parses `EVIDENCE_VERDICT:` lines + structural checks). Runs locally against fixtures and on farm against real tails.
- `verif/sim/capture_evidence.sh` — runs 7 UVM tests + coverage view, writes `m5_uvm_regression.log` + `coverage_summary_m5.txt`.
- `formal/run/tests/fixtures/` — small synthetic sample logs (clean, bug, malformed, empty-table) used to TDD `check_evidence.sh` without the farm.
- `formal/run/tests/test_check_evidence.sh` — local test harness driving `check_evidence.sh` over fixtures.

**Modified files:**
- `.gitignore` — flip 3 dir rules to force-track curated files.
- `doc/FinalReport_M5.md` — line 29 count fix; §6 command-list completion; §1 evidence-note line.
- `README.md` — Artifact Policy reword + evidence pointer.
- `doc/FinalReport_M2.md`, `doc/FinalReport_M3.md`, `doc/FinalReport_M4.md` — one-line "consolidated evidence in M5 snapshot" note each.

**Evidence files** (generated on farm, force-tracked): the 25 files listed in Global Constraints.

---

## The 22 formal jobs (verbatim tcl basenames)

Clean (11): `fpv_run_top`, `fpv_run_seq`, `fpv_run_lane_bf16`, `fpv_run_align_bf16`, `fpv_run_round_bf16`, `fpv_run_special_bf16`, `fpv_run_bf16_top`, `fpv_run_lane_nvfp4`, `fpv_run_scale_nvfp4`, `fpv_run_round_nvfp4`, `fpv_run_nvfp4_top`.

Bug-injected (11): `fpv_run_top_buginjected`, `fpv_run_seq_buginjected`, `fpv_run_lane_bf16_buginjected`, `fpv_run_lane_bf16_oor_buginjected`, `fpv_run_align_bf16_buginjected`, `fpv_run_round_bf16_buginjected`, `fpv_run_bf16_top_buginjected`, `fpv_run_lane_nvfp4_buginjected`, `fpv_run_scale_nvfp4_buginjected`, `fpv_run_round_nvfp4_buginjected`, `fpv_run_nvfp4_top_buginjected`.

`special_bf16` has no bug variant; `lane_bf16` has two (`_buginjected` + `_oor_buginjected`). Net 11/11.

---

### Task 1: Evidence contract + checker (TDD against fixtures, no farm needed)

Build the validator first so the capture scripts have a spec to satisfy. The checker parses a stable `EVIDENCE_VERDICT:` line that capture will emit; this task defines that contract and tests it against synthetic fixtures.

**Files:**
- Create: `formal/run/check_evidence.sh`
- Create: `formal/run/tests/test_check_evidence.sh`
- Create: `formal/run/tests/fixtures/clean_good.log`
- Create: `formal/run/tests/fixtures/bug_good.log`
- Create: `formal/run/tests/fixtures/clean_bad_falsified.log`
- Create: `formal/run/tests/fixtures/empty_table.log`

**Interfaces:**
- Produces: `check_evidence.sh <logs_dir> <uvm_log> <cov_summary>` — exit 0 iff all checks pass, non-zero + stderr message on first failure.
- Contract line format (one per formal tail, emitted by capture in Task 2/3):
  `EVIDENCE_VERDICT: job=<name> kind=<clean|bug> proven=<int> falsified=<int> covered=<int>`
- Checker rules: `kind=clean` requires `falsified=0`; `kind=bug` requires `falsified>=1`; every tail must contain a line matching `Tool version` (case-insensitive `version`) AND at least one assertion-table row (a line containing `proven` or `falsified` other than the verdict line).

- [ ] **Step 1: Write the fixtures**

`formal/run/tests/fixtures/clean_good.log`:
```
Synopsys VC Formal Version V-2023.12-SP2-3
Run: 2026-07-03 10:00:00
Model: gates=6150 inputs=130
Assertion                         Status
a_result_matches_ref              proven
EVIDENCE_VERDICT: job=fpv_run_top kind=clean proven=1 falsified=0 covered=2
```

`formal/run/tests/fixtures/bug_good.log`:
```
Synopsys VC Formal Version V-2023.12-SP2-3
Run: 2026-07-03 10:01:00
Model: gates=6150 inputs=130
Assertion                         Status
a_result_matches_ref              falsified
EVIDENCE_VERDICT: job=fpv_run_top_buginjected kind=bug proven=0 falsified=1 covered=2
```

`formal/run/tests/fixtures/clean_bad_falsified.log` (a clean job that wrongly shows a falsified assertion — must be rejected):
```
Synopsys VC Formal Version V-2023.12-SP2-3
Run: 2026-07-03 10:02:00
Model: gates=6150 inputs=130
Assertion                         Status
a_result_matches_ref              falsified
EVIDENCE_VERDICT: job=fpv_run_top kind=clean proven=0 falsified=1 covered=2
```

`formal/run/tests/fixtures/empty_table.log` (verdict present but no real assertion rows — must be rejected):
```
Synopsys VC Formal Version V-2023.12-SP2-3
Run: 2026-07-03 10:03:00
Model: gates=6150 inputs=130
EVIDENCE_VERDICT: job=fpv_run_seq kind=clean proven=4 falsified=0 covered=2
```

- [ ] **Step 2: Write the failing test harness**

`formal/run/tests/test_check_evidence.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
checker="${here}/../check_evidence.sh"
fix="${here}/fixtures"
fails=0
pass_case() { # dir should pass
  if bash "$checker" "$1" "$2" "$3" >/dev/null 2>&1; then echo "ok  $4"; else echo "FAIL(expected pass) $4"; fails=$((fails+1)); fi
}
fail_case() { # dir should fail
  if bash "$checker" "$1" "$2" "$3" >/dev/null 2>&1; then echo "FAIL(expected fail) $4"; fails=$((fails+1)); else echo "ok  $4"; fi
}

# Build a good UVM + coverage fixture on the fly
tmp="$(mktemp -d)"
printf 'UVM report summary\n%s\n' \
  'TEST dotprod_random_test items=500 matched=500 mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0' > "${tmp}/uvm_good.log"
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

echo "---"; [ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash formal/run/tests/test_check_evidence.sh`
Expected: FAIL — `check_evidence.sh` does not exist yet, every case errors (harness prints FAIL/exit 1).

- [ ] **Step 4: Write minimal checker to pass**

`formal/run/check_evidence.sh`:
```bash
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
  case "$kind" in
    clean) [ "$fals" = "0" ] || err "$f: clean job has falsified=$fals (expected 0)";;
    bug)   [ "${fals:-0}" -ge 1 ] || err "$f: bug job has falsified=$fals (expected >=1)";;
    *)     err "$f: bad kind='$kind'";;
  esac
done

# UVM: no mismatch/leftover/errors on any TEST line
grep -q 'TEST ' "$uvm_log" || err "uvm log has no TEST lines"
grep -E 'mismatched=[1-9]|leftover=[1-9]|UVM_ERROR=[1-9]|UVM_FATAL=[1-9]' "$uvm_log" \
  && err "uvm log shows a mismatch/leftover/error"

# Coverage: must state 100.00%
grep -q '100.00%' "$cov_summary" || err "coverage summary is not 100.00%"

echo "check_evidence: OK (${#tails[@]} formal tails, uvm clean, coverage 100.00%)"
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash formal/run/tests/test_check_evidence.sh`
Expected: `ALL PASS` (5 cases: all-good passes; clean-falsified, empty-table, coverage-not-100, uvm-mismatch all correctly rejected).

- [ ] **Step 6: Make scripts executable and commit-stage locally (no commit yet)**

Run: `chmod +x formal/run/check_evidence.sh formal/run/tests/test_check_evidence.sh`
Do NOT commit yet — the single commit happens in Task 6. Leave changes in the working tree.

---

### Task 2: Formal capture script

**Files:**
- Create: `formal/run/capture_evidence.sh`

**Interfaces:**
- Consumes: the 22 tcl files in `formal/run/` (run via `vcf -batch -f <job>.tcl`).
- Produces: `formal/run/logs/<job>.log` (curated tail + `EVIDENCE_VERDICT:` line) for all 22 jobs, and `formal/run/logs/RC_SUMMARY_m5.txt`. Verdict line format matches Task 1's contract exactly.

- [ ] **Step 1: Write the capture script**

`formal/run/capture_evidence.sh`:
```bash
#!/usr/bin/env bash
# Run the 22 formal jobs and write curated, auditable tails.
# Run from formal/run on the farm (vcf on PATH).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p logs
raw_dir="$(mktemp -d)"

clean_jobs=(fpv_run_top fpv_run_seq fpv_run_lane_bf16 fpv_run_align_bf16 \
  fpv_run_round_bf16 fpv_run_special_bf16 fpv_run_bf16_top fpv_run_lane_nvfp4 \
  fpv_run_scale_nvfp4 fpv_run_round_nvfp4 fpv_run_nvfp4_top)
bug_jobs=(fpv_run_top_buginjected fpv_run_seq_buginjected \
  fpv_run_lane_bf16_buginjected fpv_run_lane_bf16_oor_buginjected \
  fpv_run_align_bf16_buginjected fpv_run_round_bf16_buginjected \
  fpv_run_bf16_top_buginjected fpv_run_lane_nvfp4_buginjected \
  fpv_run_scale_nvfp4_buginjected fpv_run_round_nvfp4_buginjected \
  fpv_run_nvfp4_top_buginjected)

capture_one() {
  local job="$1" kind="$2" raw="${raw_dir}/$1.raw" out="logs/$1.log"
  echo "RUN ${job} (${kind})"
  vcf -batch -f "${job}.tcl" >"$raw" 2>&1 || true   # falsified jobs return nonzero; verdict is derived from log

  # Deterministic tail: version banner + timestamp + model stats + assertion table.
  {
    grep -m1 -i 'version' "$raw" || echo "Tool version: (not printed)"
    grep -m1 -iE 'date|run' "$raw" || true
    grep -m1 -iE 'gate|input' "$raw" || true
    echo "----- assertion status -----"
    grep -iE 'proven|falsified|covered|unreachable' "$raw" | grep -viE 'EVIDENCE_VERDICT' || true
  } > "$out"

  # Machine-readable verdict derived from the raw log.
  local proven falsified covered
  proven=$(grep -icE '\bproven\b' "$raw" || true)
  falsified=$(grep -icE '\bfalsified\b' "$raw" || true)
  covered=$(grep -icE '\bcovered\b' "$raw" || true)
  echo "EVIDENCE_VERDICT: job=${job} kind=${kind} proven=${proven} falsified=${falsified} covered=${covered}" >> "$out"
}

for j in "${clean_jobs[@]}"; do capture_one "$j" clean; done
for j in "${bug_jobs[@]}";  do capture_one "$j" bug;   done

# Roll-up summary from the verdict lines.
{
  echo "M5 formal regression roll-up  (generated by capture_evidence.sh)"
  grep -h '^EVIDENCE_VERDICT:' logs/*.log | sort
} > logs/RC_SUMMARY_m5.txt

echo "capture_evidence: wrote $(ls logs/*.log | wc -l) tails + RC_SUMMARY_m5.txt"
```

- [ ] **Step 2: Shell-parse sanity check (local, no farm)**

Run: `bash -n formal/run/capture_evidence.sh && echo "syntax ok"`
Expected: `syntax ok` (no farm run locally; `vcf` absent, so full execution is deferred to Task 5).

- [ ] **Step 3: Make executable**

Run: `chmod +x formal/run/capture_evidence.sh`
Expected: no output, exit 0. No commit yet.

---

### Task 3: UVM + coverage capture script

**Files:**
- Create: `verif/sim/capture_evidence.sh`

**Interfaces:**
- Consumes: `verif/sim/run.do` (7 UVM tests), `verif/sim/coverage_waivers.do`, merged `merged.ucdb`.
- Produces: `verif/sim/transcripts/m5_uvm_regression.log` (per-test summary lines the checker parses) and `verif/sim/coverage/coverage_summary_m5.txt` (contains `100.00%`).

- [ ] **Step 1: Write the capture script**

`verif/sim/capture_evidence.sh`:
```bash
#!/usr/bin/env bash
# Run the 7 UVM tests + coverage view and write curated evidence.
# Run from verif/sim on the farm (vsim/vcover on PATH).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p transcripts coverage
raw="$(mktemp -d)"

echo "RUN uvm regression"
vsim -c -do run.do >"${raw}/uvm.raw" 2>&1 || true

# Keep the per-test summary lines + UVM report tail (the load-bearing evidence).
{
  grep -m1 -iE 'questa|version' "${raw}/uvm.raw" || echo "Tool version: (not printed)"
  echo "----- per-test summary -----"
  grep -iE 'items=|matched=|mismatched=|leftover=|UVM_ERROR|UVM_FATAL|TEST ' "${raw}/uvm.raw" || true
  echo "----- UVM report summary -----"
  awk '/UVM Report Summary/{p=1} p' "${raw}/uvm.raw" || true
} > transcripts/m5_uvm_regression.log

echo "RUN coverage view + waivers"
vsim -c -viewcov merged.ucdb \
  -do "do coverage_waivers.do; coverage save merged_excl.ucdb; quit -f" \
  >"${raw}/covview.raw" 2>&1 || true
vcover report merged_excl.ucdb >"${raw}/covreport.raw" 2>&1 || true

{
  grep -m1 -iE 'questa|version' "${raw}/covreport.raw" || echo "Tool version: (not printed)"
  echo "----- merged coverage summary (merged_excl.ucdb) -----"
  grep -iE 'coverage|statement|branch|expression|covergroup|total' "${raw}/covreport.raw" || true
} > coverage/coverage_summary_m5.txt

echo "capture_evidence(uvm): wrote transcripts/m5_uvm_regression.log + coverage/coverage_summary_m5.txt"
```

- [ ] **Step 2: Shell-parse sanity check**

Run: `bash -n verif/sim/capture_evidence.sh && echo "syntax ok"`
Expected: `syntax ok`.

- [ ] **Step 3: Make executable**

Run: `chmod +x verif/sim/capture_evidence.sh`
Expected: no output, exit 0. No commit yet.

---

### Task 4: `.gitignore` force-track rules

**Files:**
- Modify: `.gitignore`

**Interfaces:**
- Produces: git tracks exactly the 25 curated files; all binaries/scratch remain ignored.

- [ ] **Step 1: Edit `.gitignore`**

Replace the three bare directory-ignore lines (`sim/coverage/`, `verif/sim/coverage/`, `verif/sim/transcripts/`, and add a `formal/run/logs` block) with force-track rules. Add this block after the existing "# Simulation artifacts" / "# Formal artifacts" sections:
```gitignore
# --- Curated evidence: ignore raw dirs but force-track the committed tails ---
formal/run/logs/*
!formal/run/logs/fpv_run_*.log
!formal/run/logs/RC_SUMMARY_m5.txt

verif/sim/transcripts/*
!verif/sim/transcripts/m5_uvm_regression.log

verif/sim/coverage/*
!verif/sim/coverage/coverage_summary_m5.txt
```
Remove the now-superseded bare lines `verif/sim/coverage/` and `verif/sim/transcripts/` and `formal/run/logs/` if present (the `dir/*` + `!` form replaces them). Leave `sim/coverage/` and `sim/transcripts/` ignored (no committed evidence there).

- [ ] **Step 2: Verify ignore logic with a dummy binary + dummy tail (local)**

Run:
```bash
mkdir -p formal/run/logs verif/sim/transcripts verif/sim/coverage
touch formal/run/logs/fpv_run_top.log formal/run/logs/merged.ucdb
git check-ignore formal/run/logs/merged.ucdb && echo "ucdb correctly ignored"
git check-ignore formal/run/logs/fpv_run_top.log && echo "TAIL WRONGLY IGNORED" || echo "tail correctly tracked"
rm -f formal/run/logs/merged.ucdb
```
Expected: `ucdb correctly ignored` then `tail correctly tracked`. (Keep the empty `fpv_run_top.log` placeholder removed too, or overwrite in Task 5.)

Run: `rm -f formal/run/logs/fpv_run_top.log`
Expected: cleanup, exit 0. No commit yet.

---

### Task 5: Farm run — generate real evidence

This task cannot be validated locally; it runs on `ssh katnemo`. The capture scripts + checker are already written and tested (Tasks 1-3), so this task only executes and validates.

**Files:**
- Produces (on farm, then copied back): the 25 evidence files.

- [ ] **Step 1: Sync working tree to farm**

From repo root:
```bash
rsync -az --exclude '.git' ./ katnemo:/tmp/nvfp4_evidence_run/
```
Expected: rsync completes, exit 0.

- [ ] **Step 2: Run formal capture on farm**

```bash
ssh katnemo 'cd /tmp/nvfp4_evidence_run/formal/run && bash capture_evidence.sh'
```
Expected: `capture_evidence: wrote 22 tails + RC_SUMMARY_m5.txt`. If a job produces an empty tail (tool version format mismatch), inspect the raw and adjust the grep anchors in `capture_evidence.sh`, re-run.

- [ ] **Step 3: Run UVM + coverage capture on farm**

```bash
ssh katnemo 'cd /tmp/nvfp4_evidence_run/verif/sim && bash capture_evidence.sh'
```
Expected: `capture_evidence(uvm): wrote ...`.

- [ ] **Step 4: Run the checker on the farm against REAL tails**

```bash
ssh katnemo 'cd /tmp/nvfp4_evidence_run && bash formal/run/check_evidence.sh formal/run/logs verif/sim/transcripts/m5_uvm_regression.log verif/sim/coverage/coverage_summary_m5.txt'
```
Expected: `check_evidence: OK (22 formal tails, uvm clean, coverage 100.00%)`.
If it fails: the failure is real evidence of a capture-format problem (or, alarmingly, a genuine regression). Fix the capture anchors and re-run; do NOT hand-edit tails.

- [ ] **Step 5: Copy the 25 evidence files back**

```bash
rsync -az katnemo:/tmp/nvfp4_evidence_run/formal/run/logs/ formal/run/logs/
rsync -az katnemo:/tmp/nvfp4_evidence_run/verif/sim/transcripts/ verif/sim/transcripts/
rsync -az katnemo:/tmp/nvfp4_evidence_run/verif/sim/coverage/ verif/sim/coverage/
```
Expected: 22 `.log` + `RC_SUMMARY_m5.txt` in `formal/run/logs/`, `m5_uvm_regression.log`, `coverage_summary_m5.txt` present locally.

- [ ] **Step 6: Run checker + tests locally against the real evidence**

Run:
```bash
bash formal/run/tests/test_check_evidence.sh
bash formal/run/check_evidence.sh formal/run/logs verif/sim/transcripts/m5_uvm_regression.log verif/sim/coverage/coverage_summary_m5.txt
```
Expected: `ALL PASS` then `check_evidence: OK (22 formal tails, uvm clean, coverage 100.00%)`.

---

### Task 6: Doc reconciliation + single commit

**Files:**
- Modify: `doc/FinalReport_M5.md` (line 29; §6 command list; one evidence-note line)
- Modify: `README.md` (Artifact Policy + evidence pointer)
- Modify: `doc/FinalReport_M2.md`, `doc/FinalReport_M3.md`, `doc/FinalReport_M4.md` (one line each)

**Interfaces:**
- Produces: reports whose citations all resolve; single commit containing scripts + evidence + gitignore + docs.

- [ ] **Step 1: Fix the stale count on `doc/FinalReport_M5.md` line 29**

Change `A full 18-proof / 7-test regression` to `A full 22-job (11 clean + 11 bug-injected) / 7-test regression`. Do NOT touch the §2.1/§2.2 tables or their "(11 proof jobs)"/"(7 proof jobs)" headers — those are the deliberate historical snapshot documented by §6b.

- [ ] **Step 2: Complete the §6 reproduction command list**

In the BF16 formal block of §6 (currently 6 commands ending at `fpv_run_bf16_top_buginjected.tcl`), insert the four missing bug-injected commands so the block reads:
```bash
# BF16 formal (from formal/run)
vcf -batch -f fpv_run_lane_bf16.tcl
vcf -batch -f fpv_run_lane_bf16_buginjected.tcl
vcf -batch -f fpv_run_lane_bf16_oor_buginjected.tcl
vcf -batch -f fpv_run_align_bf16.tcl
vcf -batch -f fpv_run_align_bf16_buginjected.tcl
vcf -batch -f fpv_run_round_bf16.tcl
vcf -batch -f fpv_run_round_bf16_buginjected.tcl
vcf -batch -f fpv_run_special_bf16.tcl
vcf -batch -f fpv_run_bf16_top.tcl
vcf -batch -f fpv_run_bf16_top_buginjected.tcl
```
Verify the whole §6 block now enumerates 22 `vcf` lines: `grep -c 'vcf -batch' doc/FinalReport_M5.md` should be `22`.

- [ ] **Step 3: Add evidence-location note to `doc/FinalReport_M5.md` §1**

After the existing line 13 "Evidence:" sentence, append: `Curated proof tails, the UVM transcript, and the coverage summary are committed under formal/run/logs/, verif/sim/transcripts/, and verif/sim/coverage/; regenerate them with formal/run/capture_evidence.sh and verif/sim/capture_evidence.sh, and validate with formal/run/check_evidence.sh.`

- [ ] **Step 4: Reword README Artifact Policy**

In `README.md` change the Artifact Policy so it distinguishes curated (tracked) from raw (ignored):
```markdown
## Artifact Policy

Curated, human-readable proof and coverage summaries ARE checked in as
verification evidence:

- Formal proof tails: [`formal/run/logs/`](formal/run/logs) (22 jobs + `RC_SUMMARY_m5.txt`)
- UVM regression transcript: [`verif/sim/transcripts/m5_uvm_regression.log`](verif/sim/transcripts/m5_uvm_regression.log)
- Merged coverage summary: [`verif/sim/coverage/coverage_summary_m5.txt`](verif/sim/coverage/coverage_summary_m5.txt)

Regenerate with `formal/run/capture_evidence.sh` and `verif/sim/capture_evidence.sh`;
validate with `formal/run/check_evidence.sh`.

Raw/binary EDA outputs remain generated artifacts and are NOT tracked: formal
run databases and full logs, UCDB coverage databases, waveforms, and local tool
scratch directories.
```
Also update the earlier README line (~117) "Raw logs, transcripts, UCDBs, and coverage reports are generated artifacts and are intentionally ignored." to "Raw databases, waveforms, UCDBs, and full logs are generated artifacts and are intentionally ignored; curated proof/coverage summaries are tracked (see Artifact Policy)."

- [ ] **Step 5: Add one-line evidence note to M2/M3/M4 reports**

Append to the intro/evidence area of each of `doc/FinalReport_M2.md`, `doc/FinalReport_M3.md`, `doc/FinalReport_M4.md`:
`> Consolidated tool evidence for all milestones is committed under the M5 snapshot (formal/run/logs/, verif/sim/transcripts/, verif/sim/coverage/); this report cites summarized results.`

- [ ] **Step 6: Final pre-commit validation**

Run:
```bash
bash formal/run/tests/test_check_evidence.sh
bash formal/run/check_evidence.sh formal/run/logs verif/sim/transcripts/m5_uvm_regression.log verif/sim/coverage/coverage_summary_m5.txt
git add -A
git status --porcelain | grep -E '\.(ucdb|wlf|fsdb|vpd)$' && echo "BINARY STAGED - ABORT" && exit 1 || echo "no binaries staged"
du -sk $(git diff --cached --name-only | grep -E 'logs/|transcripts/|coverage/') | awk '{s+=$1} END{print s" KB evidence"; if (s>512) print "WARN: evidence >512KB"}'
```
Expected: `ALL PASS`, `check_evidence: OK ...`, `no binaries staged`, evidence total well under 512 KB.

- [ ] **Step 7: Single commit**

```bash
git commit -m "docs(evidence): commit curated M5 formal+UVM+coverage proof snapshot

- Force-track 22 formal proof tails + RC_SUMMARY + UVM transcript + coverage
  summary at the paths the reports cite; keep UCDB/waveform/scratch ignored.
- Add committed capture + check scripts (auditable, reproducible curation)
  with a local fixture test suite for the checker.
- Reconcile docs: 18->22 proof count on the M5 scope line, complete the
  section 6 reproduction list, reword the artifact policy to reflect that
  curated evidence is now tracked; note consolidated evidence in M2-M4."
```
Expected: one commit created. Verify: `git show --stat HEAD | head -40` lists the 25 evidence files + 5 scripts/fixtures + 5 doc files + `.gitignore`.

---

## Self-Review

**1. Spec coverage:**
- Curated tails + full summaries → Tasks 2, 3 (curated tails; RC_SUMMARY + coverage summary full). ✓
- In-place, un-ignore exact files → Task 4. ✓
- M5 sweep only → Task 5 (22 jobs + 7 tests); M2-M4 get pointer note (Task 6 Step 5). ✓
- Committed capture script → Tasks 2, 3. ✓
- Full pre-commit self-check → Task 1 (checker) + Task 6 Step 6. ✓
- Doc fixes folded in → Task 6. ✓
- Single commit → Task 6 Step 7. ✓
- Hard-to-fake markers preserved → capture scripts keep version/timestamp/gate lines + real assertion table; checker enforces version marker + non-empty table. ✓

**2. Placeholder scan:** No TBD/TODO. Every code step shows full content. Farm-format risk is handled by "inspect raw + adjust anchors" instructions, not left as a placeholder.

**3. Type/name consistency:** `EVIDENCE_VERDICT:` line format identical in Task 1 (contract + fixtures), Task 2 (emitter). `check_evidence.sh` signature `(<logs_dir> <uvm_log> <cov_summary>)` identical in Tasks 1, 5, 6. Job lists in Task 2 match the verbatim list and the 22-count in Task 6 Step 2. Coverage token `100.00%` consistent between checker (Task 1 Step 4), UVM/coverage capture (Task 3), and validation (Task 5/6).

**Note on scope discipline:** The §2.2 table (7 bug jobs) and §2.1 (11 clean) headers are intentionally NOT modified — verified against §6b which documents the 18→22 growth as a post-review addendum. Rewriting them would destroy the report's deliberate historical layering and exceed the spec's "fix genuinely-stale text" intent.
