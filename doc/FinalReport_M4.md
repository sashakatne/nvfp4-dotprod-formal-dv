# M4 Final Report - NVFP4 Dot-Product Tier

**Author:** Sasha Katne
**Date:** 2026-07-02
**Tools:** Questa 2021.3_1 (UVM), VC Formal V-2023.12-SP2-3

---

> Consolidated tool evidence for all milestones is committed under the M5 snapshot (formal/run/logs/, verif/sim/transcripts/, verif/sim/coverage/); this report cites summarized results.

## 1. Summary

M4 adds NVFP4 (NVIDIA's Blackwell block-scaled FP4) as the third numeric tier
without changing the proven INT8/BF16 arithmetic. NVFP4 mode multiplies a block
of 16 E2M1 elements per operand, sharing one UE4M3 block scale, and returns FP32.
The dot-product factors as `(sA·sB)·Σ(aᵢ·bᵢ)`; the inner sum over E2M1×E2M1
products is exact in 13-bit fixed point, and the full result is exactly
representable in FP32 (significand < 2²⁴), so the final stage only normalizes.

The top-level NVFP4 equivalence is proven by an assume-guarantee decomposition:
the element multiplier is blackboxed, its output assumed equal to the golden, and
the DUT's pre-round outputs are asserted equal to the golden pre-round reduction
using pure-DUT-net assertions. All formal proofs are clean; every bug-injected
mutation falsifies its target. The UVM environment was extended to drive NVFP4
stimulus and dispatch to the NVFP4 golden; all seven tests pass with zero
mismatches. Merged coverage is 93.58%. The INT8/BF16 regression (widened top,
sequential, and BF16 AG proofs, plus the M2/M3 UVM tests) remains green.

---

## 2. Formal Verification Results

All runs on VC Formal V-2023.12-SP2-3. Raw formal logs are generated artifacts and are not checked in.

### 2.1 NVFP4 proofs (clean)

| Proof | Log | Result |
|-------|-----|--------|
| Lane (`mul_lane_nvfp4` == `ref_mul_nvfp4`) | `fpv_run_lane_nvfp4.log` | decode + product proven (near-exhaustive over 256 combos), covers covered |
| Scale (`scale_mul_nvfp4`) | `fpv_run_scale_nvfp4.log` | 3 assertions proven (a_nan/a_sig/a_exp), 5 covers covered |
| Top AG (pre-round boundary) | `fpv_run_nvfp4_top.log` | 20 assertions proven (a_inner_is_lane_sum, 16× a_align_lane, 3× a_scale_*), 0 falsified; 5 covers covered, 1 uncoverable (`c_max_scale`: `scale_sig == 0xFF` unreachable since max `sigA·sigB = 225`) |

The top AG proof blackboxes `mul_lane_nvfp4`, assumes each product equals
`ref_mul_nvfp4`, and asserts only over DUT nets (accumulator linearity + per-lane
align + scale fields). Full result equivalence follows by transitivity with the
lane and final-round proofs (soundness independently reviewed).

### 2.2 Bug-injection (mutation) results

| Mutation | Log | Falsified |
|----------|-----|-----------|
| E2M1 6.0→8 (`BUG_INJECTION`) | `fpv_run_lane_nvfp4_buginjected.log` | lane `a_product_matches_ref`, `a_decode_matches_ref` |
| UE4M3 `k=exp-9` (`BUG_SCALE`) | `fpv_run_scale_nvfp4_buginjected.log` | scale `a_exp` |
| NaN detect 0x7E (`BUG_NAN`) | `fpv_run_nvfp4_top_buginjected.log` | top `a_scale_nan_ref` (+ scale-field cascade) |

### 2.3 INT8/BF16 regression guard

| Proof | Result |
|-------|--------|
| INT8 top (widened) | proven; bug-injected falsified |
| Sequential protocol | 4 assertions proven non-vacuous, 2 covers; bug falsified at depth 4 |
| BF16 top AG | 4 assertions proven; bug-injected falsified |

The `exact_acc_tree` generalization to N lanes preserved the proven N=8 structure
(confirmed by BF16 `a_acc_is_lane_sum` still proving).

---

## 3. UVM Regression Results

Transcript: `verif/sim/transcripts/m4_uvm_regression.log`. The scoreboard
dispatches by mode to `dotprod_ref` / `dotprod_ref_bf16` / `dotprod_ref_nvfp4`.

| Test | Items | Matched | Mismatched | Leftover | UVM_ERROR | UVM_FATAL |
|------|-------|---------|------------|----------|-----------|-----------|
| dotprod_random_test (INT8) | 500 | 500 | 0 | 0 | 0 | 0 |
| dotprod_backpressure_test (INT8) | 1000 | 1000 | 0 | 0 | 0 | 0 |
| dotprod_corner_test (INT8) | 4 | 4 | 0 | 0 | 0 | 0 |
| dotprod_bf16_test (BF16) | 500 | 500 | 0 | 0 | 0 | 0 |
| dotprod_bf16_corner_test (BF16) | 8 | 8 | 0 | 0 | 0 | 0 |
| dotprod_nvfp4_test (NVFP4) | 500 | 500 | 0 | 0 | 0 | 0 |
| dotprod_nvfp4_corner_test (NVFP4) | 8 | 8 | 0 | 0 | 0 | 0 |

Every predicted transaction was consumed with no residue and no comparison
failure across all three formats.

---

## 4. Coverage

Merged from seven UCDBs. Summary in `verif/sim/coverage/coverage_summary_m4.txt`.

| Metric | Result |
|--------|--------|
| Statements | 100% |
| Branches | 100% |
| Covergroups | 99.33% |
| Covergroup bins | 96.72% (118/122) |
| Expressions | 75% |
| Total (filtered view) | 93.58% |

The four uncovered covergroup bins and the one uncovered expression term are the
low-frequency INT8 protocol corner carried from M2 (producer holding `in_valid=0`
during an active stall) plus a few operand-class bins not hit by the random seed.
These are closure gaps, not failures.

---

## 5. Assume-Guarantee Method Note

The NVFP4 top proof extended the M3 lesson with a new refinement. M3 taught: keep
the same nonlinear function off both sides of the equivalence miter. M4 added: a
golden **function call inside an assertion** is itself expensive for the engine to
elaborate, even when its result is assumed equal. A monolithic
`inner_sum == golden inner_sum` assertion, and a transitivity variant that summed
`ref_mul_nvfp4(...)` in the assertion, both stalled. The working form asserts only
over DUT nets — accumulator linearity (`a_inner_is_lane_sum`) and per-lane
alignment (`a_align_lane`) — so no golden multiply or unpack is elaborated in the
miter. The proof then converges in seconds (20 assertions), and full equivalence
follows by transitivity outside the tool. Two other issues surfaced only on the
licensed tool run and would not appear in local static review: a formal filelist missing
the `rtl` include directory (which silently corrupted the golden reference), and a
UVM compile list missing the NVFP4 RTL. Both are recorded for future tiers.

---

## 6. Reproduction

```bash
# NVFP4 formal (from formal/run)
vcf -batch -f fpv_run_lane_nvfp4.tcl
vcf -batch -f fpv_run_scale_nvfp4.tcl
vcf -batch -f fpv_run_nvfp4_top.tcl
vcf -batch -f fpv_run_nvfp4_top_buginjected.tcl

# Directed sims (from sim) and UVM regression (from verif/sim)
vsim -c -do run.do
```
