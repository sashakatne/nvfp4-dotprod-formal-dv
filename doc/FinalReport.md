# Final Report: INT8 Dot-Product Formal Verification (Milestone 1)

**Project:** `nvfp4-dotprod-formal-dv`
**Milestone:** M1 - INT8 exact dot-product
**Author:** Sasha Katne
**Date:** 2026-06-30
**Status:** Complete.

**Toolchain:**
- Synopsys VC Formal V-2023.12-SP2-3
- Siemens Questa 2021.3_1

---

## 1. Overview

This report summarizes the M1 verification results for `dotprod_top` in INT8 mode.
The verification strategy uses two complementary methods:

- **VC Formal FPV** (primary): exhaustive equivalence proof between the DUT and
  `dotprod_ref` over all INT8 input combinations (130 input bits, bit-level model).
- **Questa directed sim** (smoke): 6 targeted cases exercising zeros, extremes,
  cancellation, single-lane, and ramp inputs, checked against the same golden.

The property source of truth is `doc/VerificationPlan.md`. The golden reference
source of truth is `ref/dotprod_ref.svh` (single SV function, shared by both
formal and sim flows).

The DUV elaborated as pure combinational logic: VC Formal reported 0 registers,
0 latches, 387 comb-logic operators. Because the RTL has no functional clock,
the FPV flow declares a named virtual clock (`vclk`) and no reset.

---

## 2. FPV results: clean run

Command: `cd formal/run && vcf -batch -f fpv_run_top.tcl`.
Generated log: `formal/run/logs/fpv_top.log`.

### 2.1 Assertion results

| Property               | Expected outcome | Actual outcome | Time | Notes |
|------------------------|-----------------|---------------|------|-------|
| `a_result_matches_ref` | PROVEN          | **proven**    | 00:00:00 | Bit-exact vs `dotprod_ref` across all INT8 inputs |

Summary: Assertion found = 1, proven = 1.

### 2.2 Cover results

| Cover                    | Expected outcome | Actual outcome | Notes |
|--------------------------|-----------------|---------------|-------|
| `c_int8_sat_unreachable` | UNREACHABLE     | **uncoverable** | Structural: max INT8 sum 131072 needs 19 signed bits; output is 32b, so saturation cannot fire |
| `c_positive_result`      | REACHABLE       | **covered** (depth=0) | Vacuity check: assume does not over-constrain |
| `c_negative_result`      | REACHABLE       | **covered** (depth=0) | Vacuity check: assume does not over-constrain |

Summary: Cover found = 3, covered = 2, uncoverable = 1. Constraint (`am_int8_mode`) = 1, constrained.

The `uncoverable` result on `c_int8_sat_unreachable` is the intended dormant-path
outcome, not a defect. The two reachable covers confirm the `am_int8_mode` assume
did not vacuously satisfy the assertion.

### 2.3 Convergence notes

Bit-level model: 6150 gates, 130 inputs, 0 registers, 1 constraint. The proof
converged immediately (assertion proven in < 1s engine time). Full run: total
19.25s wall, formal engine 11.86s wall, peak 250 MB (engine). No case-splitting,
blackboxing, or abstraction was required for the INT8 datapath.

---

## 3. FPV results: bug-injection run

Command: `cd formal/run && vcf -batch -f fpv_run_top_buginjected.tcl`
(`+define+BUG_INJECTION` passed through `read_file -vcs`).
Generated log: `formal/run/logs/fpv_top_buginjected.log`.

### 3.1 Injection description

The `BUG_INJECTION` define activates a mutation in `final_round.sv` that XORs
the LSB of the correct result with 1 (`result = good ^ 32'sd1`). This corrupts
the output for every input, including the all-zero vector (0 XOR 1 = 1 != 0).

### 3.2 Expected vs actual detection

| Property               | Expected outcome | Actual outcome | Time |
|------------------------|-----------------|---------------|------|
| `a_result_matches_ref` | FALSIFIED       | **falsified** (depth=0) | 00:00:01 |

Summary: Assertion found = 1, falsified = 1. The covers behaved identically to
the clean run (2 covered, 1 uncoverable), confirming only the equivalence
assertion is sensitive to the injected bug.

### 3.3 Interpretation

The clean run proves and the mutated run falsifies the same property. This
demonstrates the equivalence proof has teeth: it is not vacuously passing, and
it detects a single-LSB datapath corruption.

---

## 4. Directed simulation results

Command: `cd sim && vsim -c -do run.do`.
Generated transcript: `sim/transcripts/dotprod_int8_directed.log`.

### 4.1 Pass summary

| Testbench                    | Cases | Expected banner                              | Actual outcome |
|-----------------------------|-------|----------------------------------------------|----------------|
| `dotprod_int8_directed_tb`  | 6     | `DOTPROD_INT8_DIRECTED PASS (6 cases)`       | **PASS, Errors: 0** |

The banner `DOTPROD_INT8_DIRECTED PASS (6 cases)` printed with 0 errors and 0
warnings at simulation. Compile-time warnings were limited to cosmetic
`svinputport` port-kind defaulting (`var` vs `wire`) on input array ports, which
is harmless.

### 4.2 Per-case results

All 6 cases passed (the scoreboard `$fatal`s on any mismatch against
`dotprod_ref`; the run reached `$finish` with 0 errors). Expected values:

| Case    | Input description            | Expected result | Expected sat |
|--------|------------------------------|-----------------|--------------|
| zeros   | All a=0, b=0                 | 0               | 0 |
| min*max | All a=-128, b=127            | -130048         | 0 |
| max*max | All a=127, b=127             | 129032          | 0 |
| cancel  | Alternating +100/-100, b=1   | 0               | 0 |
| single  | Lane 3: a=50, b=2; rest zero | 100             | 0 |
| ramp    | All a=1, b=i (0..7)          | 28              | 0 |

---

## 5. Code coverage

Command: `cd sim && vsim -c -do run.do` (instruments via `vopt +cover=sbfec+dotprod_top`,
saves `dotprod_int8.ucdb`). Generated report: `sim/coverage/coverage_summary.txt`.

### 5.1 DUT statement coverage (the correctness-relevant metric)

Every DUT RTL module reached 100% statement coverage with the 6 directed cases:

| Instance (DUT)        | Statements | Coverage |
|-----------------------|-----------|----------|
| `dut` (dotprod_top)   | 1/1       | 100.00%  |
| `dut/al` (align_to_fixed) | 8/8   | 100.00%  |
| `dut/ac` (exact_acc_tree) | 7/7   | 100.00%  |
| `dut/fr` (final_round)    | 2/2   | 100.00%  |
| `dut/g_lane[*]/ml` (mul_lane, x8) | 1/1 each | 100.00% |

### 5.2 Aggregate coverage

| Metric     | M1 target | Actual (total, filtered view) | Assessment |
|-----------|-----------|-------------------------------|------------|
| Total by instance | - | 62.24% | Expected for 6 directed vectors |
| DUT statement | > 90% | 100% | Met |
| Toggle (DUT lanes) | > 70% | 73-95% per lane | Met |
| Toggle (top/acc/round) | > 70% | 73-77% | Met |
| TB branch/condition | - | 66.66% / 33.33% | Low - directed only, see note |

### 5.3 Honest coverage note

DUT statement coverage is complete (100%). Toggle coverage is 73-95% because 6
directed vectors do not exercise every bit of the 32-bit output and wide
accumulator. Branch/condition coverage in the testbench and package is low
(33-66%) for two legitimate reasons:

1. The `sat_cast` saturation branches are structurally unreachable for INT8
   (proven `uncoverable` in FPV section 2.2), so those branches cannot be hit
   by any stimulus.
2. This is a directed smoke test, not a coverage-closure run. Broad functional
   and code coverage closure via constrained-random is scoped for the M2 UVM
   environment.

The formal proof, not simulation coverage, is the primary correctness argument
for M1: it is exhaustive over the entire INT8 input space.

---

## 6. Property-to-bug traceability

| Seeded bug              | Detection method          | Property / check              | Evidence |
|-------------------------|--------------------------|-------------------------------|---------|
| LSB corruption (M1 bug) | FPV falsification        | `a_result_matches_ref`        | Section 3, `fpv_top_buginjected.log` |
| (clean regression)      | Directed sim scoreboard   | `check()` vs `dotprod_ref`, 6 cases | Section 4, sim transcript |

---

## 7. Open items (post-M1)

| Item | Milestone | Description |
|------|----------|-------------|
| UVM constrained-random env | M2 | Full functional + code coverage via CRV; drive toggle/branch closure |
| BF16 front-end + Kulisch acc | M3 | Float path, NaN/Inf special-value properties |
| NVFP4 E2M1/E4M3 + assume-guarantee | M4 | Block-scaled format, blackbox top proof |
| Full regression + report | M5 | Merge coverage, final evidence sweep |

---

## 8. Run commands (exact, as executed with the configured tools)

```bash
# FPV clean run (from formal/run)
vcf -batch -f fpv_run_top.tcl -output_log_file run_top.log

# FPV bug-injection run (from formal/run)
vcf -batch -f fpv_run_top_buginjected.tcl -output_log_file run_top_bug.log

# Directed sim + coverage save (from sim)
vsim -c -do 'do run.do; quit -f'

# Coverage report (after sim)
vcover report dotprod_int8.ucdb
```
