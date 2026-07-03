# M2 Final Report - Sequential INT8 Dot-Product + Full UVM Environment

**Author:** Sasha Katne
**Date:** 2026-06-30
**Tools:** Questa 2021.3_1 (UVM-1.1d), VC Formal V-2023.12-SP2-3

---

## 1. Summary

M2 wraps the M1-proven INT8 dot-product core in a 2-stage pipeline with a ready/valid handshake and global-stall backpressure. A full UVM environment was built from scratch: two agents (input and output), a scoreboard with a golden reference model, and a functional coverage subscriber. Three UVM tests ran with the configured tools - 1504 total transactions across random, backpressure-stressed, and directed-corner scenarios, with zero mismatches and zero scoreboard leftovers. Merged code coverage hit 100% statements, 100% branches, and 92.91% total. Three SVA protocol properties were proven clean in VC Formal with non-vacuous witnesses; both cover properties were reached. A bug-injected run falsified `p_hold_stable` at depth 4, confirming the property catches the stall-path mutation.

---

## 2. UVM Regression Results

| Test | Items | Matched | Mismatched | Leftover | UVM_ERROR | UVM_FATAL |
|------|-------|---------|------------|----------|-----------|-----------|
| dotprod_random_test | 500 | 500 | 0 | 0 | 0 | 0 |
| dotprod_backpressure_test | 1000 | 1000 | 0 | 0 | 0 | 0 |
| dotprod_corner_test | 4 | 4 | 0 | 0 | 0 | 0 |

All tests passed. The scoreboard consumed every predicted transaction with no residue and no comparison failures.

---

## 3. Code Coverage (dotprod_seq)

Merged from three UCDB files (`dotprod_seq.ucdb`, `dotprod_backpressure_test.ucdb`, `dotprod_corner_test.ucdb`) using `vcover merge`.

| Metric | Result |
|--------|--------|
| Statements | 100% |
| Branches | 100% |
| Expressions | 75% |
| Total | 92.91% |

The Expressions metric is 75% (3/4 terms covered). The uncovered term is `in_ready_0` in the expression `in_valid & in_ready`. The FEC `in_ready_0` target (the case where `in_valid` is 0 while `in_ready` is also 0) had zero hits across all runs. This means the pipeline stall always kept `in_ready` deasserted only when `in_valid` was also active - the scenario where the producer holds `in_valid=0` during an active stall was never exercised. This is a low-priority closure gap; adding a directed sequence that holds `in_valid` low during an ongoing stall would close it.

---

## 4. Functional Coverage

Coverage merged across all three tests.

| Covergroup | Coverage | Bins Hit | Total Bins |
|------------|----------|----------|------------|
| cg_value | 93.33% | 30 | 35 |
| cg_proto | 100% | 6 | 6 |
| **Overall (covergroup metric)** | **96.66%** | - | 2 groups |
| **Overall (bin metric)** | **87.80%** | 36 | 41 |

### cg_value Detail

- `cp_a`: 100% (all per-lane A value classes hit)
- `cp_b`: 100% (all per-lane B value classes hit)
- `x_ab` cross: 80% (5 bins ZERO)

The 5 uncovered cross bins all involve pairing a max-positive or max-negative lane-A value with a zero lane-B value, or vice versa:

| Uncovered Bin |
|---------------|
| `<maxp, maxn>` |
| `<zero, maxn>` |
| `<zero, maxp>` |
| `<maxn, zero>` |
| `<maxp, zero>` |

With 504 total random and corner transactions (500 random + 4 corner), these extreme cross combinations were not hit by chance. The corner test's 4 directed vectors covered zero-all and max-all but not mixed extreme-A with zero-B. Adding 4-8 directed corner vectors targeting these exact cross bins would close the gap.

### cg_proto Detail

`cg_proto` has two coverpoints: `cp_in` on `{in_valid, in_ready}` (bins: `accept`, `in_stall`, `idle`) and `cp_out` on `{out_valid, out_ready}` (bins: `drain`, `backpressure`, `no_out`). All 6 bins were hit, confirming the testbench exercised every protocol state on both the input and output ports.

---

## 5. Protocol FPV Results

**Clean run** (VC Formal V-2023.12-SP2-3, `fpv_run_seq.tcl`):

| Property / Cover | Type | Result | Depth / Note |
|------------------|------|--------|--------------|
| p_hold_stable | Assert | Proven | Non-vacuous |
| p_no_out_at_reset | Assert | Proven | Non-vacuous |
| p_stall_blocks_ready | Assert | Proven | Non-vacuous |
| c_accept | Cover | Covered | Depth 1 |
| c_backpressure | Cover | Covered | Depth 3 |
| Engine wall time | - | ~16s | - |

Assertions found: 3, proven: 3. Covers found: 2, covered: 2.

---

## 6. Bug-Injection Result

**Bug-injected run** (`fpv_run_seq_buginjected.tcl`, compiled with `+define+BUG_INJECTION`):

| Property | Result |
|----------|--------|
| p_hold_stable | **Falsified** (depth 4) |
| p_no_out_at_reset | Proven |
| p_stall_blocks_ready | Proven |

The bug drops `out_valid` to 0 in the stall `else` branch instead of holding it. VC Formal found a 4-cycle counterexample: valid output present, consumer applies backpressure, and `out_valid` drops on the next cycle. P2 and P3 are unaffected because neither property depends on the stall-path register update. The falsification confirms P1 provides real detection coverage for the stall control logic.

---

## 7. Evidence References

| Artifact | Path |
|----------|------|
| Random test transcript | `verif/sim/transcripts/sim_dotprod_random_test.log` |
| Backpressure test transcript | `verif/sim/transcripts/sim_dotprod_backpressure_test.log` |
| Corner test transcript | `verif/sim/transcripts/sim_dotprod_corner_test.log` |
| Coverage summary | `verif/sim/coverage/coverage_summary.txt` |
| Coverage details | `verif/sim/coverage/coverage_merged.txt` |
| FPV clean log | `formal/run/logs/fpv_seq.log` |
| FPV bug-injected log | `formal/run/logs/fpv_seq_buginjected.log` |

---

## 8. Reproduction Commands

```bash
# UVM simulation
cd verif/sim

# dotprod_random_test (default test in run.do)
vsim -c -do run.do

# dotprod_backpressure_test
vsim -c tb_opt -coverage -L mtiUvm "+UVM_TESTNAME=dotprod_backpressure_test" \
     -do "set NoQuitOnFinish 1; onbreak {resume}; run -all; coverage save dotprod_backpressure_test.ucdb; quit -f"

# dotprod_corner_test
vsim -c tb_opt -coverage -L mtiUvm "+UVM_TESTNAME=dotprod_corner_test" \
     -do "set NoQuitOnFinish 1; onbreak {resume}; run -all; coverage save dotprod_corner_test.ucdb; quit -f"

# Merge coverage databases
vcover merge merged.ucdb dotprod_seq.ucdb dotprod_backpressure_test.ucdb dotprod_corner_test.ucdb

# Coverage reports
vcover report -summary merged.ucdb
vcover report -details merged.ucdb

# Protocol FPV - clean run
cd formal/run
vcf -batch -f fpv_run_seq.tcl

# Protocol FPV - bug-injected run
vcf -batch -f fpv_run_seq_buginjected.tcl
```
