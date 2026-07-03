# Verification Plan: INT8 Dot-Product Unit (Milestone 1)

**Project:** `nvfp4-dotprod-formal-dv`
**Milestone:** M1 - INT8 exact dot-product
**Methodology:** VC Formal FPV (primary) + Questa directed sim (smoke)
**Author:** Sasha Katne
**Date:** 2026-06-30

---

## 1. Purpose

Prove that `dotprod_top` computes the exact INT8 8-lane dot-product as specified
by the golden reference `dotprod_ref`, for every possible input. Demonstrate that
the `BUG_INJECTION` mutation is caught by the same property set.

---

## 2. Scope

### In scope (M1)

- `dotprod_top` with `mode = FMT_INT8`, all 8 lanes.
- FPV equivalence between DUT output and `dotprod_ref` golden function.
- Cover properties: reachability of positive results, negative results, and the
  structurally-unreachable saturation path.
- Directed simulation smoke (6 cases) via Questa with code coverage save.
- Bug-injection regression: `BUG_INJECTION` variant expected to falsify.

### Out of scope (M1)

- BF16 and NVFP4 format paths (deferred to M3/M4).
- Full UVM constrained-random environment (deferred to M2).
- Functional coverage collection (deferred to M2).
- Lane-level standalone proofs (separate `fpv_run_lane_*.tcl` scripts; M1 proves
  the full combinational top directly, which converges without blackboxing for
  INT8).
- Assume-guarantee decomposition (needed for BF16/NVFP4 multiplier complexity;
  not required here).

---

## 3. Conventions

- **Tool:** Synopsys VC Formal, invoked as `vcf -f <script>.tcl`.
- **Clock/reset:** The DUT is purely combinational. Scripts set `clock -none;
  reset -none`.
- **Assertion style:** Immediate assertions in `always_comb` inside `dotprod_top_sva`.
- **Bind:** `bind_dotprod_top_sva.sva` binds `dotprod_top_sva` to `dotprod_top`
  without modifying RTL source.
- **Sim tool:** Siemens Questa. Run via `vsim -c -do run.do`.
- **Coverage:** Code coverage saved to `dotprod_int8.ucdb` by `run.do`.
- **Naming:** properties prefixed `a_` (assert), `am_` (assume), `c_` (cover),
  matching house FV_AHB2APB convention.

---

## 4. Property catalog

| ID  | Name                     | Type   | Module              | Intent                                                               |
|-----|--------------------------|--------|---------------------|----------------------------------------------------------------------|
| P1  | `a_result_matches_ref`   | assert | `dotprod_top_sva`   | DUT result and sat must match `dotprod_ref(a, b, ref_sat)` exactly  |
| P2  | `am_int8_mode`           | assume | `dotprod_top_sva`   | Constrain `mode == FMT_INT8`; blocks BF16/NVFP4 paths               |
| C1  | `c_int8_sat_unreachable` | cover  | `dotprod_top_sva`   | Attempts to reach `sat == 1`; expected UNREACHABLE (see section 5)  |
| C2  | `c_positive_result`      | cover  | `dotprod_top_sva`   | Reaches `result > 0`; expected REACHABLE                            |
| C3  | `c_negative_result`      | cover  | `dotprod_top_sva`   | Reaches `result < 0`; expected REACHABLE                            |

### Property text (from `formal/RTL/dotprod_top_sva.sva`)

```systemverilog
always_comb begin
  ref_r = dotprod_ref(a, b, ref_sat);
  am_int8_mode: assume (mode == FMT_INT8);
  a_result_matches_ref: assert ((result == ref_r) && (sat == ref_sat));
  c_int8_sat_unreachable: cover (sat == 1'b1);
  c_positive_result:      cover (result > 0);
  c_negative_result:      cover (result < 0);
end
```

---

## 5. Assume analysis

`am_int8_mode` restricts `mode` to `FMT_INT8 = 2'd0`. The `mode` port drives no
logic in the M1 RTL (the `^{mode}` sink is present only to suppress lint); the
assume is included for correctness at the formal level so the proof is scoped to
the stated operating condition and remains valid when BF16/NVFP4 paths are added.

**Vacuity check:** The assume does not trivially block all states - the 8x8=64
pairs of vector inputs are still fully unconstrained, exercising `2^128` distinct
input combinations for the DUT.

---

## 6. Cover analysis

**C1 - `c_int8_sat_unreachable`:**

The maximum absolute 8-lane INT8 sum is 8 * 128 * 128 = 131072, which fits in
19 signed bits. The output width is 32 bits. Because ACC_W = 24 < INT8_OUT_W = 32,
`sat_cast` sign-extends the 24-bit accumulator to 32 bits - and that sign-extended
value always lies within the 32-bit signed range. Saturation can never fire.

This cover is intentionally expected to be UNREACHABLE. It documents the dormant
saturation path and proves it stays dormant for all INT8 inputs. An UNREACHABLE
result here is a correct outcome, not a bug.

**C2 and C3** are sanity covers. They must both be REACHABLE to demonstrate the
proof is not vacuously passing due to overconstrained assumptions.

---

## 7. Bug-injection scenario

### Setup

Compile with `+define+BUG_INJECTION` using `formal/run/fpv_run_top_buginjected.tcl`.
The mutation in `final_round.sv` XORs the LSB of the correct result with 1:

```systemverilog
result = good ^ 32'sd1;
```

This corrupts the result for every input, including zero (0 XOR 1 = 1).

### Expected falsification

- **Property falsified:** `a_result_matches_ref` (P1).
- **Counterexample:** the tool produces a concrete input assignment where
  `result != dotprod_ref(a, b, ref_sat)`.
- **`sat` matching:** `sat` is unaffected by the bug; its mismatch occurs only
  for inputs where the correct result would trigger saturation (structurally
  unreachable for INT8, per C1). So P1 falsifies on the `result` sub-expression.

The tool must report this property as FALSIFIED (not PROVEN) to confirm the proof
infrastructure catches the injected defect.

---

## 8. Pass criteria

### FPV clean run (`fpv_run_top.tcl`)

| Script             | Property                 | Expected outcome  |
|--------------------|--------------------------|-------------------|
| `fpv_run_top.tcl`  | `a_result_matches_ref`   | PROVEN            |
| `fpv_run_top.tcl`  | `am_int8_mode` (assume)  | Active            |
| `fpv_run_top.tcl`  | `c_int8_sat_unreachable` | UNREACHABLE       |
| `fpv_run_top.tcl`  | `c_positive_result`      | REACHABLE         |
| `fpv_run_top.tcl`  | `c_negative_result`      | REACHABLE         |

### FPV bug-injection run (`fpv_run_top_buginjected.tcl`)

| Script                        | Property               | Expected outcome |
|-------------------------------|------------------------|------------------|
| `fpv_run_top_buginjected.tcl` | `a_result_matches_ref` | FALSIFIED        |

### Directed sim (`sim/run.do`)

| Test                        | Cases | Expected outcome                       |
|-----------------------------|-------|----------------------------------------|
| `dotprod_int8_directed_tb`  | 6     | `DOTPROD_INT8_DIRECTED PASS (6 cases)` |

---

## 9. Directed sim test cases

| Case       | Description                                    | Expected result |
|-----------|------------------------------------------------|-----------------|
| zeros      | All a=0, b=0                                   | 0, no sat       |
| min*max    | All a=-128, b=127; sum = 8*(-128*127) = -130048| -130048, no sat |
| max*max    | All a=127, b=127; sum = 8*(127*127) = 129032   | 129032, no sat  |
| cancel     | Alternating +100, -100 times b=1; sum = 0      | 0, no sat       |
| single     | Lane 3: a=50, b=2; rest zero                   | 100, no sat     |
| ramp       | All a=1, b=i; sum = 0+1+...+7 = 28             | 28, no sat      |

---

## 10. Results tables

Executed with VC Formal V-2023.12-SP2-3 and Questa 2021.3_1 on 2026-06-30. Raw logs, transcripts, and coverage outputs are generated artifacts.

### FPV clean run results

| Property                 | Status | Depth | Notes |
|--------------------------|--------|-------|-------|
| `a_result_matches_ref`   | proven | -     | Bit-exact vs `dotprod_ref`, all INT8 inputs |
| `c_int8_sat_unreachable` | uncoverable | - | Intended dormant path (sum needs 19b, output 32b) |
| `c_positive_result`      | covered | 0    | Vacuity check passed |
| `c_negative_result`      | covered | 0    | Vacuity check passed |
| `am_int8_mode`           | constrained | - | Scopes proof to INT8 |

Found: 1 assertion (1 proven); 3 covers (2 covered, 1 uncoverable); 1 constraint.
Engine 11.86s wall, 250 MB peak.

### FPV bug-injection run results

| Property               | Status    | Counterexample | Notes |
|------------------------|-----------|----------------|-------|
| `a_result_matches_ref` | falsified | yes (depth=0)  | LSB corruption detected |

Confirms the proof is non-vacuous and detects a single-LSB datapath fault.

### Directed sim results

Banner: `DOTPROD_INT8_DIRECTED PASS (6 cases)`, Errors: 0. All 6 cases matched
`dotprod_ref` (scoreboard `$fatal`s on mismatch; run reached `$finish` clean).

| Case       | Expected result | Expected sat | Match golden |
|-----------|-----------------|--------------|--------------|
| zeros      | 0               | 0 | yes |
| min*max    | -130048         | 0 | yes |
| max*max    | 129032          | 0 | yes |
| cancel     | 0               | 0 | yes |
| single     | 100             | 0 | yes |
| ramp       | 28              | 0 | yes |

Coverage: DUT statement 100% (all RTL modules); toggle 73-95%; total-by-instance
62.24% (directed smoke; CRV closure deferred to M2). See `doc/FinalReport.md` §5.

---

## 11. Risk log

| Risk | Mitigation |
|------|-----------|
| Formal tool version mismatch | `filelist` pins relative include paths; no absolute paths |
| `sat_cast` width sign-extension corner | Covered by `min*max` and `max*max` directed cases |
| BUG_INJECTION accidentally left on for clean run | Scripts are separate TCL files with distinct `analyze` commands |
