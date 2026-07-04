# Design: Committed Evidence Bundle (M5 snapshot)

**Date:** 2026-07-03
**Status:** Approved (design), pending implementation plan
**Author:** Sasha Katne (with Claude)

## Problem

The repo commits RTL, formal SVA/scripts, UVM source, and summarized reports, but
no simulation or formal artifacts. `.gitignore` drops all EDA outputs and the
README `Artifact Policy` documents this as intentional. The stated rationale is
reproducibility: anyone with VC Formal + Questa can regenerate everything.

Two gaps make this a trust problem for a public/showcase repo:

1. **No provenance.** A reader cannot distinguish "ran 22 formal jobs, all green"
   from a plausible-looking hand-typed results table. The verification evidence
   *is* the deliverable here, and none of it is inspectable.
2. **Dangling citations.** The reports name specific files by path
   (`fpv_run_top.log`, `RC_SUMMARY_m5.txt`, `coverage_summary_m5.txt`,
   `m5_uvm_regression.log`, per-job `.log`s) that exist nowhere — not in git,
   and not on the working machine (the farm `/tmp/*` snapshots are transient).
   Every citation resolves to a missing file.

Public CI is not a viable provenance path: VC Formal and Questa are license-gated
commercial tools that cannot run in public GitHub Actions. A curated, committed
evidence snapshot is the strongest provenance signal available for this repo.

## Goals

- Convert every dangling report citation into a real, inspectable, diff-able file.
- Keep the repo clean: no UCDBs, waveforms, `daidir/`, `csrc/`, or `simv*`.
- Make the curation itself reproducible and auditable (no hand-editing doubt).
- Fix the doc-honesty inconsistencies surfaced while scoping this work.

## Non-goals

- Backfilling per-milestone (M2/M3/M4) evidence. The M5 sweep re-proves every
  prior result and is the authoritative current state; historical reports get a
  one-line pointer to the M5 snapshot instead of their own log files.
- Committing raw/full logs or any binary databases.
- Changing any RTL, SVA, formal tcl, or UVM source. This is evidence + docs only.

## Decisions (locked during brainstorming)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Granularity | Curated tails + full summaries | High signal, small footprint; keeps hard-to-fake markers |
| Layout | In-place, un-ignore exact cited files | Every existing path citation resolves with zero path edits |
| Scope | M5 final sweep only | Authoritative whole-project regression; re-proves all tiers |
| Capture | Committed capture script | Curation is in git = reproducible + auditable |
| Doc fixes | Folded into same change | One coherent honesty pass |
| Pre-commit checks | Full semantic self-check | Fail loud if any tail is empty/malformed/wrong-signed |

## Architecture

### File set (in-place)

Committed under the exact paths the reports already cite:

```
formal/run/logs/fpv_run_top.log                       # INT8 clean
formal/run/logs/fpv_run_top_buginjected.log           # INT8 bug
formal/run/logs/fpv_run_seq.log                       # INT8 seq clean
formal/run/logs/fpv_run_seq_buginjected.log           # INT8 seq bug
formal/run/logs/fpv_run_lane_bf16.log                 # BF16 ...
formal/run/logs/fpv_run_lane_bf16_buginjected.log
formal/run/logs/fpv_run_lane_bf16_oor_buginjected.log
formal/run/logs/fpv_run_align_bf16.log
formal/run/logs/fpv_run_align_bf16_buginjected.log
formal/run/logs/fpv_run_round_bf16.log
formal/run/logs/fpv_run_round_bf16_buginjected.log
formal/run/logs/fpv_run_special_bf16.log
formal/run/logs/fpv_run_bf16_top.log
formal/run/logs/fpv_run_bf16_top_buginjected.log
formal/run/logs/fpv_run_lane_nvfp4.log                # NVFP4 ...
formal/run/logs/fpv_run_lane_nvfp4_buginjected.log
formal/run/logs/fpv_run_scale_nvfp4.log
formal/run/logs/fpv_run_scale_nvfp4_buginjected.log
formal/run/logs/fpv_run_round_nvfp4.log
formal/run/logs/fpv_run_round_nvfp4_buginjected.log
formal/run/logs/fpv_run_nvfp4_top.log
formal/run/logs/fpv_run_nvfp4_top_buginjected.log
formal/run/logs/RC_SUMMARY_m5.txt                     # aggregate roll-up (full)
verif/sim/transcripts/m5_uvm_regression.log           # UVM tail
verif/sim/coverage/coverage_summary_m5.txt            # coverage summary (full)
```

That is 22 formal job tails + 1 formal roll-up + 1 UVM transcript tail +
1 coverage summary = **25 committed text files**, all KB-scale.

Note the 22 formal jobs = 11 clean + 11 bug-injected. The BF16 tier has an extra
bug-injected variant (`lane_bf16_oor_buginjected`), which is why BF16 shows more
bug logs than clean; the clean/bug split is still 11/11 overall.

### .gitignore change

Flip the affected dirs from "ignore whole directory" to "ignore contents but
force-track the curated files":

```gitignore
# Curated evidence is force-tracked; raw databases/logs stay ignored.
formal/run/logs/*
!formal/run/logs/fpv_run_*.log
!formal/run/logs/RC_SUMMARY_m5.txt

verif/sim/transcripts/*
!verif/sim/transcripts/m5_uvm_regression.log

verif/sim/coverage/*
!verif/sim/coverage/coverage_summary_m5.txt
```

Everything else stays ignored: `*.ucdb`, `merged_excl.ucdb`, `*.wlf`, `*.fsdb`,
`*.daidir/`, `csrc/`, `simv*`, `fml_*/`, `vcst_rtdb*`, etc. The existing global
`*.ucdb` / `*.wlf` patterns already protect against binaries slipping through the
`!` negations, but the pre-commit check verifies this explicitly.

### Capture script (provenance keystone)

`formal/run/capture_evidence.sh` (committed, run on farm from `formal/run`):

- Loops the 22 tcls via `vcf -batch -f <tcl>`, capturing full stdout to a temp
  file per job.
- For each job, extracts a **deterministic tail** into `logs/<job>.log`:
  - VC Formal tool-version banner line (hard-to-fake marker).
  - Run timestamp.
  - Model statistics (gate count, input count) where present.
  - The per-assertion status table (assertion name -> proven/falsified).
  - Summary lines: counts of proven / falsified / covered, engine time.
- Greps the 22 tails' summary lines into `logs/RC_SUMMARY_m5.txt`.

`verif/sim/capture_evidence.sh` (committed, run on farm from `verif/sim`):

- Runs `vsim -c -do run.do` (7 UVM tests), extracts the `report_phase` summary
  plus per-test `mismatched / leftover / UVM_ERROR / UVM_FATAL` lines into
  `transcripts/m5_uvm_regression.log`.
- Runs the coverage merge + waiver view
  (`vsim -c -viewcov merged.ucdb -do "do coverage_waivers.do; coverage save
  merged_excl.ucdb; quit -f"` then `vcover report merged_excl.ucdb`) and writes
  the summary metrics to `coverage/coverage_summary_m5.txt`.

Extraction is line-anchored (grep/awk on VC Formal's stable summary format), never
hand-edited. Because the script is committed, a skeptic re-runs it and byte-
compares the regenerated tails.

**Design rule:** keep the hard-to-fake markers (tool-version string, gate/input
counts, per-assertion rows). These are what make a short tail trustworthy.

## Doc reconciliation (folded into same change)

Three real inconsistencies found during scoping, all fixed here:

1. `doc/FinalReport_M5.md:29` — "A full 18-proof / 7-test regression" is stale;
   change to "22-job (11 clean + 11 bug-injected) / 7-test regression". Lines
   65, 200, 220 already say 22.
2. `doc/FinalReport_M5.md` §6 Reproduction Commands — the BF16 block lists only
   `lane_bf16`, `align_bf16`, `round_bf16`, `special_bf16`, `bf16_top`,
   `bf16_top_buginjected` (missing four bug-injected: `lane_bf16_buginjected`,
   `lane_bf16_oor_buginjected`, `align_bf16_buginjected`,
   `round_bf16_buginjected`). Add them so the enumerated commands total 22.
3. Artifact-policy wording — `README.md` `Artifact Policy` and
   `doc/FinalReport_M5.md:13` currently say raw logs are not checked in. Reword
   to: curated proof/coverage summaries ARE checked in under `formal/run/logs/`
   and `verif/sim/coverage/`; raw databases, waveforms, and full logs remain
   generated artifacts. Add one line pointing readers at the evidence files and
   the capture script.

Historical M2/M3/M4 reports: add a single line noting consolidated evidence lives
in the M5 snapshot. No per-milestone backfill.

## Verification / pre-commit self-check

A committed checker (`formal/run/check_evidence.sh` or inline in capture) asserts
before commit, failing loud on any violation:

- Every committed formal tail contains a tool-version string and a non-empty
  assertion table.
- Every clean job tail shows 0 falsified assertions.
- Every bug-injected job tail shows >= 1 falsified assertion.
- `m5_uvm_regression.log` shows `mismatched=0` and `leftover=0` for all 7 tests,
  `UVM_ERROR=0 UVM_FATAL=0`.
- `coverage_summary_m5.txt` shows `100.00%`.
- No binary/UCDB/waveform file is staged (git diff --cached name-only scan).
- Total evidence footprint is in KBs (sanity bound, e.g. < 512 KB).

## Commit plan

**Single commit.** Evidence files, capture/check scripts, `.gitignore` change,
and all doc fixes land together in one commit:

```
docs(evidence): commit curated M5 formal+UVM+coverage proof snapshot

- Force-track 22 formal proof tails + RC_SUMMARY + UVM transcript + coverage
  summary at the paths the reports cite; keep UCDB/waveform/scratch ignored.
- Add committed capture + check scripts (auditable, reproducible curation).
- Reconcile docs: 18->22 proof count, complete the §6 reproduction list,
  reword artifact policy to reflect curated evidence is now tracked.
```

## Risks / open considerations

- **Farm output format drift.** If the installed VC Formal version formats its
  summary differently than the extractor expects, the tail could be empty — the
  pre-commit check catches this (non-empty assertion table assertion).
- **Coverage view reproducibility.** The `-viewcov` + waiver flow must match the
  documented mechanics (reason code `EUR`, no `-scope`+`-srcfile` combo). Already
  captured in project memory; reused verbatim.
- **Footprint creep.** Bounded by curated tails + the size self-check.
