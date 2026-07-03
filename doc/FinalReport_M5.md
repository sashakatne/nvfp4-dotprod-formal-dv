# Final Report: nvfp4-dotprod-formal-dv (Milestone 5 - Unified Sign-Off)

**Project:** `nvfp4-dotprod-formal-dv`
**Milestone:** M5 - full regression, coverage closure, unified cross-tier sign-off
**Author:** Sasha Katne
**Date:** 2026-07-03
**Status:** Complete.

**Toolchain:**
- Synopsys VC Formal V-2023.12-SP2-3
- Siemens Questa 2024.2

**Evidence:** Summary tables are preserved below. Raw logs and coverage reports are generated artifacts; only the waiver file is checked in.

---

## 1. Project Overview

This document is the whole-project sign-off for `nvfp4-dotprod-formal-dv`. It covers the complete verification record across three numeric tiers and five milestones.

**Tier arc:**

- **INT8** (M1/M2): An 8-lane exact integer dot-product, purely combinational (M1) and then pipelined with a ready/valid streaming interface and global-stall backpressure (M2).
- **BF16** (M3): A bfloat16 front-end feeding a 56-bit exact fixed-point accumulator (constrained exponent window E in [119,134]) with IEEE special-value handling and a single RNE rounding step.
- **NVFP4** (M4/M5): NVIDIA Blackwell block-scaled FP4. Each 8-lane vector packs 16 E2M1 elements sharing one UE4M3 (unsigned FP8) block scale per operand; the result is FP32. The product factors as `(sA*sB)*sum(ai*bi)`: the inner sum over E2M1 x E2M1 products is exact in 13-bit fixed point, and the full result is exactly representable in FP32, so the final stage only normalizes.

**Single-golden-reference philosophy:** `ref/dotprod_ref.svh` (INT8), `ref/dotprod_ref_bf16.svh` (BF16), and `ref/dotprod_ref_nvfp4.svh` (NVFP4) are shared between the FPV assertion module and the UVM scoreboard. There is no model drift between the two verification methods.

**M5 scope:** M4 left the NVFP4 final normalization stage covered only by directed simulation. M5 adds `fpv_run_round_nvfp4` and its bug-injected counterpart, completing formal stage-by-stage coverage for all three tiers. Merged UVM coverage closes to 100.00% (reachable). A full 18-proof / 7-test regression confirms every prior result is still green.

---

## 2. Unified Formal Results

All runs on VC Formal V-2023.12-SP2-3. Raw logs are generated artifacts and are not checked in.

### 2.1 Clean proofs (11 proof jobs)

| Proof job | Tier | Assertions proven | Covers covered | Uncoverable | Log |
|-----------|------|------------------|----------------|-------------|-----|
| `fpv_run_top` | INT8 | 1 | 2 | 1 | `fpv_run_top.log` |
| `fpv_run_seq` | INT8 | 4 | 2 | 0 | `fpv_run_seq.log` |
| `fpv_run_lane_bf16` | BF16 | 21 | 6 | 0 | `fpv_run_lane_bf16.log` |
| `fpv_run_align_bf16` | BF16 | 8 | 4 | 0 | `fpv_run_align_bf16.log` |
| `fpv_run_round_bf16` | BF16 | 2 | 4 | 0 | `fpv_run_round_bf16.log` |
| `fpv_run_special_bf16` | BF16 | 5 | 5 | 0 | `fpv_run_special_bf16.log` |
| `fpv_run_bf16_top` | BF16 | 4 | 8 | 0 | `fpv_run_bf16_top.log` |
| `fpv_run_lane_nvfp4` | NVFP4 | 5 | 37 | 0 | `fpv_run_lane_nvfp4.log` |
| `fpv_run_scale_nvfp4` | NVFP4 | 3 | 5 | 0 | `fpv_run_scale_nvfp4.log` |
| `fpv_run_round_nvfp4` *(NEW M5)* | NVFP4 | 2 | 5 | 0 | `fpv_run_round_nvfp4.log` |
| `fpv_run_nvfp4_top` | NVFP4 | 20 | 5 | 1 | `fpv_run_nvfp4_top.log` |

**Uncoverable results are structural, not defects:**

- `c_int8_sat_unreachable` (`fpv_run_top`): the maximum INT8 8-lane sum is 8 x 128 x 128 = 131 072, which requires 19 signed bits; the 32-bit output cannot saturate.
- `c_max_scale` (`fpv_run_nvfp4_top`): `scale_sig == 0xFF` is unreachable because the maximum product of two E2M1 significands is 225 (< 256).

### 2.2 Bug-injected proofs (7 proof jobs)

Each bug-injected variant falsifies at least one property, confirming the proof suite has teeth.

| Proof job | Tier | Assertions falsified | Assertions proven | Log |
|-----------|------|---------------------|-------------------|-----|
| `fpv_run_top_buginjected` | INT8 | 1 (`a_result_matches_ref`) | 0 | `fpv_run_top_buginjected.log` |
| `fpv_run_seq_buginjected` | INT8 | 1 (`p_hold_stable`) | 3 | `fpv_run_seq_buginjected.log` |
| `fpv_run_bf16_top_buginjected` | BF16 | 2 | 2 | `fpv_run_bf16_top_buginjected.log` |
| `fpv_run_lane_nvfp4_buginjected` | NVFP4 | 3 | 2 | `fpv_run_lane_nvfp4_buginjected.log` |
| `fpv_run_scale_nvfp4_buginjected` | NVFP4 | 1 (`a_exp`) | 2 | `fpv_run_scale_nvfp4_buginjected.log` |
| `fpv_run_round_nvfp4_buginjected` *(NEW M5)* | NVFP4 | 1 (`a_nan_bypass`) | 1 (`a_numeric_round`) | `fpv_run_round_nvfp4_buginjected.log` |
| `fpv_run_nvfp4_top_buginjected` | NVFP4 | 3 | 17 | `fpv_run_nvfp4_top_buginjected.log` |

The `fpv_run_round_nvfp4_buginjected` result is consistent with the injected fault: the mutation disables the NaN bypass path, which drops `a_nan_bypass`; the numeric rounding path is unaffected, so `a_numeric_round` still proves.

### 2.3 UVM regression

Transcript: `verif/sim/transcripts/m5_uvm_regression.log`. The scoreboard dispatches by mode to the appropriate golden reference function.

| Test | Items | Matched | Mismatched | Leftover | UVM_ERROR | UVM_FATAL |
|------|-------|---------|------------|----------|-----------|-----------|
| `dotprod_random_test` (INT8) | 500 | 500 | 0 | 0 | 0 | 0 |
| `dotprod_backpressure_test` (INT8) | 1000 | 1000 | 0 | 0 | 0 | 0 |
| `dotprod_corner_test` (INT8) | 8 | 8 | 0 | 0 | 0 | 0 |
| `dotprod_bf16_test` (BF16) | 500 | 500 | 0 | 0 | 0 | 0 |
| `dotprod_bf16_corner_test` (BF16) | 8 | 8 | 0 | 0 | 0 | 0 |
| `dotprod_nvfp4_test` (NVFP4) | 500 | 500 | 0 | 0 | 0 | 0 |
| `dotprod_nvfp4_corner_test` (NVFP4) | 8 | 8 | 0 | 0 | 0 | 0 |

M5 extended `dotprod_corner_test` from 4 to 8 items by adding four asymmetric-extreme INT8 corners. All 2 524 transactions across the seven tests matched with zero residue and zero errors.

---

## 3. Methodology Arc

### M1 - Monolithic FPV, INT8 combinational (2026-06-30)

The INT8 core is purely combinational (0 registers). FPV elaborates the 8-lane multiplier tree, adder network, and accumulator as a bit-level model (6 150 gates, 130 inputs). A single equivalence assertion `a_result_matches_ref` is proven exhaustively against `dotprod_ref` with a named virtual clock (`vclk`) and no reset. The proof converges in under 1 second of engine time with no decomposition.

### M2 - Sequential pipeline + protocol FPV + UVM (2026-06-30)

`dotprod_seq` wraps the M1 core in a 2-cycle ready/valid pipeline with global-stall backpressure. M2 shifts the formal target from arithmetic equivalence to protocol properties (`p_hold_stable`, `p_no_out_at_reset`, `p_stall_blocks_ready`) proven with a real clock and reset. A full UVM constrained-random environment adds a latency-insensitive scoreboard, a value covergroup (`cg_value`) tracking per-lane sign classes and cross bins, and a protocol covergroup (`cg_proto`).

### M3 - BF16: four-way assume-guarantee (2026-07-02)

BF16 introduces a barrel shifter (alignment) and an RNE rounder - both are nonlinear. A monolithic top proof proved inconclusive: the tool was elaborating the same nonlinear function on both sides of the equivalence miter simultaneously. The solution is a four-way assume-guarantee decomposition: lane, align, and round are each proven standalone against the golden; `fpv_run_bf16_top` blackboxes the lane, assumes the lane guarantee, and proves only the linear pre-round reduction and the special-value ladder. Full equivalence follows by transitivity.

**Lesson M3:** Never place the same nonlinear function on both sides of a formal equivalence miter.

### M4 - NVFP4: pure-DUT-net assume-guarantee (2026-07-02)

The NVFP4 inner product factors cleanly, so the M3 AG structure carries over. A new complication surfaced: a golden function call inside an assertion body is expensive for the engine to elaborate, even when its result is assumed equal elsewhere. A transitivity variant that summed `ref_mul_nvfp4(...)` directly in the assertion stalled. The working form (`fpv_run_nvfp4_top`) asserts only over DUT nets: accumulator linearity (`a_inner_is_lane_sum`), 16 per-lane alignment assertions (`a_align_lane`), and scale fields. No golden multiply appears in the miter; full equivalence follows by transitivity outside the tool.

**Lesson M4:** Keep golden function calls out of the miter body, not just off the left-hand side.

### M5 - Final normalization proof + coverage closure (2026-07-03)

M4 left the NVFP4 final normalization stage (`final_round_nvfp4`) covered only by directed simulation. M5 adds `fpv_run_round_nvfp4`: two assertions (`a_numeric_round`, `a_nan_bypass`) that prove the normalizer directly against the NVFP4 golden reference, with no blackboxing or assume wrapper - the same structure as the working BF16 rounder proof. Task 2's brief notes that this is the intended shape: the golden call is the reference, not a cost inside the miter.

With `fpv_run_round_nvfp4` proven, every datapath stage across all three tiers has a standalone formal proof. The bug-injected counterpart confirms the assertions are sensitive to faults in the NaN bypass path.

Merged coverage closes to 100.00% after four changes: adding a B-side UE4M3 scale coverpoint, reclassifying -0 E2M1 to zero, closing four INT8 corner bins in `cg_value.x_ab` (25/25 bins), and pinning `n_items` to 500.

---

## 4. Coverage

Merged from seven UCDBs (`merged_excl.ucdb`). Summary: `verif/sim/coverage/coverage_summary_m5.txt`.

| Metric | Result |
|--------|--------|
| Statements | 100% (28/28) |
| Branches | 100% (6/6) |
| Expressions | 100% (4/4) |
| Covergroups | 100% (8/8) |
| Covergroup bins | 100% (127/127) |
| **Total** | **100.00%** |

> The counts above are the M5 sign-off snapshot. The post-review hardening pass
> (§6b) added covergroups and crosses; the current merged total is 100.00% with
> 206/206 covergroup bins.

### Waiver

One FEC (feasibility) leg is structurally unreachable and waived:

| Location | Metric | Reason code | Rationale |
|----------|--------|-------------|-----------|
| `dotprod_seq.sv:143` — `in_ready_0` FEC leg | Branch | EUR | This line is inside `else if (!stall)`. By construction `in_ready == ~stall`, so `in_ready` is always 1 when this branch executes; the false leg is unreachable by any reachable input sequence. |

Waiver record: `verif/sim/coverage_waivers.do`.

---

## 5. Bug-Injection / Traceability Matrix

| Tier | Seeded fault | Catching property | Proof job | Outcome |
|------|-------------|-------------------|-----------|---------|
| INT8 | LSB corruption in `final_round` (XOR output with 1) | `a_result_matches_ref` | `fpv_run_top_buginjected` | falsified depth 0 |
| INT8 | `out_valid <= 1'b0` in stall branch (`dotprod_seq`) | `p_hold_stable` | `fpv_run_seq_buginjected` | falsified depth 4 |
| BF16 | BF16 top equivalence mutation | 2 BF16 top AG assertions | `fpv_run_bf16_top_buginjected` | 2 falsified |
| NVFP4 | E2M1 decode: value 6.0 mapped to 8 (`BUG_INJECTION`) | 3 lane assertions (incl. `a_product_matches_ref`, `a_decode_matches_ref`) | `fpv_run_lane_nvfp4_buginjected` | 3 falsified |
| NVFP4 | UE4M3 exponent bias: `k = exp - 9` (`BUG_SCALE`) | `a_exp` | `fpv_run_scale_nvfp4_buginjected` | 1 falsified |
| NVFP4 | NaN bypass disabled in `final_round_nvfp4` | `a_nan_bypass` | `fpv_run_round_nvfp4_buginjected` | 1 falsified; `a_numeric_round` unaffected |
| NVFP4 | NaN detect threshold 0x7E (`BUG_NAN`) | `a_scale_nan_ref` + 2 scale-field assertions | `fpv_run_nvfp4_top_buginjected` | 3 falsified |

Every seeded fault is caught by at least one formal assertion. No mutation escapes the suite.

---

## 6. Reproduction Commands

```bash
# INT8 formal (from formal/run)
vcf -batch -f fpv_run_top.tcl
vcf -batch -f fpv_run_top_buginjected.tcl
vcf -batch -f fpv_run_seq.tcl
vcf -batch -f fpv_run_seq_buginjected.tcl

# BF16 formal (from formal/run)
vcf -batch -f fpv_run_lane_bf16.tcl
vcf -batch -f fpv_run_align_bf16.tcl
vcf -batch -f fpv_run_round_bf16.tcl
vcf -batch -f fpv_run_special_bf16.tcl
vcf -batch -f fpv_run_bf16_top.tcl
vcf -batch -f fpv_run_bf16_top_buginjected.tcl

# NVFP4 formal (from formal/run)
vcf -batch -f fpv_run_lane_nvfp4.tcl
vcf -batch -f fpv_run_lane_nvfp4_buginjected.tcl
vcf -batch -f fpv_run_scale_nvfp4.tcl
vcf -batch -f fpv_run_scale_nvfp4_buginjected.tcl
vcf -batch -f fpv_run_round_nvfp4.tcl
vcf -batch -f fpv_run_round_nvfp4_buginjected.tcl
vcf -batch -f fpv_run_nvfp4_top.tcl
vcf -batch -f fpv_run_nvfp4_top_buginjected.tcl

# UVM regression (from verif/sim)
vsim -c -do run.do
```

Expected outcome: all formal proof jobs report no falsified assertions in the clean variants and at least one falsified assertion in each bug-injected variant; all 7 UVM tests report `mismatched=0 leftover=0 UVM_ERROR=0 UVM_FATAL=0`; merged coverage reports 100.00%. (The suite grew to 22 jobs in the post-review hardening pass; see §6b.)

---

## 6b. Post-Review Hardening (pre-public)

A full pre-public code review of all milestones drove a hardening pass. No
critical bug was found in the shipped RTL, but several verification-strength and
scope-honesty gaps were closed. All changes were re-verified on the farm
(Synopsys VC Formal + Questa 2024.2).

**BF16 full-range guard (design change).** The BF16 tier previously assumed
operands lay in the `[119,134]` exponent window; a legal out-of-window operand
(e.g. `256.0`) produced a silently-wrong result. `front_end_bf16` now raises an
`is_oor` flag for out-of-window normals and `mul_lane_bf16` folds it into an
invalid-operation QNaN via the existing special ladder. The golden reference
mirrors this, so the BF16 lane and top proofs now drop the operand-window
`assume` and prove equivalence over the **full** BF16 input space. A dedicated
`BUG_OOR` mutation confirms the guard has formal teeth.

**Formal matrix.** 22 jobs total: 11 clean (all proven; BF16 now full-range) and
11 bug-injected (each falsifies its target). Each seeded fault now has its own
dedicated `+define+` (`BUG_INT8_ROUND`, `BUG_FTZ`, `BUG_BF16_TRUNC`, `BUG_E2M1`,
`BUG_SEQ_DROP`, `BUG_OOR`, plus the pre-existing `BUG_ALIGN`/`BUG_SPECIAL`/
`BUG_NAN`/`BUG_SCALE`/`BUG_ROUND`), replacing the shared `BUG_INJECTION` define
so each injected run activates exactly one mutation.

**UVM / coverage.** Stimulus and coverage gaps were closed: the BF16 random
sequence now reaches all 16 in-window exponents (was 6); the NVFP4 element pool
now drives `-0.5` and `-1.5` (previously a mislabeled `0xD`); a mislabeled
out-of-window `0x7F7F` corner was corrected to the true in-window `0x437F` and a
genuine out-of-range corner was added; BF16 operand-pair and NVFP4 scale-pair
crosses were added; the NVFP4 `-0` sign-mix classification and the
result-class mode attribution (in-flight mode queue) were fixed; independent
hand-computed anchors were added to the directed corners. Merged coverage is
**100.00%** (206/206 covergroup bins; branches, expressions, statements 100%).

| Test | Items | Matched | Mismatched | Leftover |
|------|-------|---------|------------|----------|
| `dotprod_random_test` (INT8) | 500 | 500 | 0 | 0 |
| `dotprod_backpressure_test` (INT8) | 1000 | 1000 | 0 | 0 |
| `dotprod_corner_test` (INT8) | 9 | 9 | 0 | 0 |
| `dotprod_bf16_test` (BF16) | 500 | 500 | 0 | 0 |
| `dotprod_bf16_corner_test` (BF16) | 10 | 10 | 0 | 0 |
| `dotprod_nvfp4_test` (NVFP4) | 500 | 500 | 0 | 0 |
| `dotprod_nvfp4_corner_test` (NVFP4) | 8 | 8 | 0 | 0 |

---

## 7. Appendix

Per-milestone final reports with design decisions, property catalogs, and summarized tool-generated evidence:

- [`doc/FinalReport.md`](FinalReport.md) - M1: INT8 combinational FPV (monolithic exhaustive), directed sim, bug injection
- [`doc/FinalReport_M2.md`](FinalReport_M2.md) - M2: sequential ready/valid pipeline, protocol FPV, full UVM environment
- [`doc/FinalReport_M3.md`](FinalReport_M3.md) - M3: BF16 tier, four-way assume-guarantee, UVM BF16 regression
- [`doc/FinalReport_M4.md`](FinalReport_M4.md) - M4: NVFP4 tier, pure-DUT-net assume-guarantee, UVM NVFP4 regression
