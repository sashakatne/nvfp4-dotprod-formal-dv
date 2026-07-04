# M3 Final Report - BF16 Dot-Product Tier

**Author:** Sasha Katne
**Date:** 2026-07-02
**Tools:** Questa 2021.3_1 (UVM), VC Formal V-2023.12-SP2-3

---

> Consolidated tool evidence for all milestones is committed under the M5 snapshot (formal/run/logs/, verif/sim/transcripts/, verif/sim/coverage/); this report cites summarized results.

## 1. Summary

M3 adds a BF16 dot-product tier to the INT8 design without changing the proven
INT8 arithmetic. BF16 mode multiplies eight bfloat16 lane pairs, accumulates
them exactly in a 56-bit fixed-point accumulator within a constrained exponent
window (`E in [119,134]`), resolves IEEE special values (NaN, +/-Inf, +/-0,
`0*Inf`, Inf-minus-Inf), flushes subnormal inputs to zero, and rounds once to
IEEE binary32 with round-nearest ties-to-even.

The top-level BF16 equivalence is proven by a four-way assume-guarantee
decomposition, after a monolithic proof was found inconclusive (the barrel-shift
aligner and the RNE rounder each appeared on both sides of the equivalence
miter). Standalone proofs discharge the lane multiplier, the per-lane aligner,
and the rounder; the top proof then blackboxes the lane, assumes its guarantee,
and proves only the linear pre-round reduction plus the special ladder. Full
equivalence follows by transitivity.

All formal proofs are clean; every bug-injected mutation falsifies its target
property. The UVM environment was extended to drive BF16 stimulus and dispatch
to the BF16 golden; all five tests pass with zero mismatches. Merged coverage is
93.41%. The INT8 regression guard (widened top proof and INT8 UVM tests) remains
green.

---

## 2. Formal Verification Results

All runs on VC Formal V-2023.12-SP2-3. Raw formal logs are generated artifacts and are not checked in.

### 2.1 BF16 proofs (clean)

| Proof | Log | Result |
|-------|-----|--------|
| Lane (`mul_lane_bf16` == `ref_mul_bf16`) | `fpv_run_lane_bf16.log` | 21 assertions proven, 6 covers covered |
| Align (`align_bf16` lane == `ref_align_bf16_lane`) | `fpv_run_align_bf16.log` | 8/8 lane assertions proven, 4 covers covered |
| Round (`final_round_bf16` == golden / bypass) | `fpv_run_round_bf16.log` | 2 assertions proven, 4 covers covered |
| Special ladder (`special_case_bf16`) | `fpv_run_special_bf16.log` | 5 assertions proven, 5 covers covered |
| Top AG (pre-round reduction) | `fpv_run_bf16_top.log` | 4 assertions proven, 8 covers covered |

Top AG assertions proven: `a_acc_is_lane_sum` (accumulator-tree linearity, <1s),
and `a_special_valid/result/status_matches_ref` (special ladder, ~32s). Blackbox
applied: `mul_lane_bf16` (8 instances). The overflow-to-Inf cover is structurally
unreachable inside the window and is not asserted (documented in the plan).

### 2.2 Bug-injection (mutation) results

Each mutation falsifies the property owned by the mutated logic, at depth 0
unless noted.

| Mutation | Log | Falsified property |
|----------|-----|--------------------|
| front_end FTZ removed (`BUG_INJECTION`) | `fpv_run_lane_bf16_buginjected.log` | lane `a_product_matches_ref`, `a_decode_zero_ftz` (11 assertion lines) |
| align off-by-one (`BUG_ALIGN`) | `fpv_run_align_bf16_buginjected.log` | `a_align_lane` (all 8 lanes) |
| round truncate (`BUG_INJECTION`) | `fpv_run_round_bf16_buginjected.log` | `a_numeric_round` |
| special Inf-minus-Inf dropped (`BUG_SPECIAL`) | `fpv_run_bf16_top_buginjected.log` | top `a_special_result/status_matches_ref` |

### 2.3 INT8 regression guard

| Proof | Log | Result |
|-------|-----|--------|
| INT8 top (widened) | `fpv_run_top.log` | `a_result_matches_ref` proven with arbitrary high bytes |
| INT8 top bug-injected | `fpv_run_top_buginjected.log` | `a_result_matches_ref` falsified |
| Sequential protocol | `fpv_run_seq.log` | 4 protocol assertions proven non-vacuous, 2 covers covered |
| Sequential bug-injected | `fpv_run_seq_buginjected.log` | `p_hold_stable` falsified at depth 4 |

---

## 3. UVM Regression Results

Transcript: `verif/sim/transcripts/m3_uvm_regression.log`. The scoreboard
dispatches by mode to `dotprod_ref` (INT8) or `dotprod_ref_bf16` (BF16).

| Test | Items | Matched | Mismatched | Leftover | UVM_ERROR | UVM_FATAL |
|------|-------|---------|------------|----------|-----------|-----------|
| dotprod_random_test (INT8) | 500 | 500 | 0 | 0 | 0 | 0 |
| dotprod_backpressure_test (INT8) | 1000 | 1000 | 0 | 0 | 0 | 0 |
| dotprod_corner_test (INT8) | 4 | 4 | 0 | 0 | 0 | 0 |
| dotprod_bf16_test (BF16) | 500 | 500 | 0 | 0 | 0 | 0 |
| dotprod_bf16_corner_test (BF16) | 8 | 8 | 0 | 0 | 0 | 0 |

Every predicted transaction was consumed with no residue and no comparison
failure across both formats.

---

## 4. Coverage

Merged from five UCDBs (`vcover merge`). Summary in
`verif/sim/coverage/coverage_summary_m3.txt`.

| Metric | Result |
|--------|--------|
| Statements | 100% |
| Branches | 100% |
| Covergroups | 98.66% |
| Covergroup bins | 93.54% (58/62) |
| Expressions | 75% |
| Total (filtered view) | 93.41% |

The four uncovered covergroup bins and the one uncovered expression term are the
low-frequency INT8 protocol corner carried over from M2 (producer holding
`in_valid=0` during an active stall) plus BF16 operand-class bins not hit by the
random seed. These are closure gaps, not failures; directed sequences would
close them.

---

## 5. Assume-Guarantee Method Note

The top proof is the milestone's formal centerpiece and the M4 NVFP4 rehearsal.
The key lesson: **do not place the same nonlinear function on both sides of an
equivalence miter.** The monolithic proof (assert `result ==
dotprod_ref_bf16`) and a two-level variant (also blackbox the rounder, but the
golden still calls `ref_round` internally) both went inconclusive. The working
decomposition asserts equivalence at the pre-round boundary
(`dotprod_ref_bf16_preround`), keeping both the barrel shifter and the rounder
out of the top miter; they are discharged by separate standalone proofs and
composed by transitivity. A diagnostic align proof (8 lanes proven in 0s)
confirmed the shifter is trivial in isolation, which localized the bottleneck to
the reconciliation of two shifters rather than the shift itself.

---

## 6. Reproduction

```bash
# Formal (from formal/run)
vcf -batch -f fpv_run_lane_bf16.tcl
vcf -batch -f fpv_run_align_bf16.tcl
vcf -batch -f fpv_run_round_bf16.tcl
vcf -batch -f fpv_run_special_bf16.tcl
vcf -batch -f fpv_run_bf16_top.tcl
vcf -batch -f fpv_run_bf16_top_buginjected.tcl
# INT8 regression + sequential
vcf -batch -f fpv_run_top.tcl
vcf -batch -f fpv_run_seq.tcl

# Directed sims (from sim)
vsim -c -do run.do

# UVM regression (from verif/sim)
vsim -c -do run.do
```
