# Design Spec: INT8 Dot-Product Unit (Milestone 1)

**Project:** `nvfp4-dotprod-formal-dv`
**Milestone:** M1 - INT8 exact dot-product
**Author:** Sasha Katne
**Date:** 2026-06-30

See `doc/architecture_dut.svg` for the datapath block diagram.

---

## 1. Purpose

`dotprod_top` computes an 8-lane signed integer dot-product, defined as:

```
result = saturate_32( sum_{i=0}^{7} a[i] * b[i] )
```

where all operands are 8-bit two's-complement signed integers. M1 wires the INT8
datapath only; BF16 and NVFP4 front-ends are deferred to M3 and M4.

---

## 2. Parameters (from `dotprod_pkg.sv`)

| Parameter    | Value | Meaning                                      |
|-------------|-------|----------------------------------------------|
| `N_LANES`   | 8     | Number of vector lanes                       |
| `INT8_W`    | 8     | Operand width in bits (signed)               |
| `PROD_W`    | 16    | Per-lane product width (exact 8x8 signed)    |
| `ACC_W`     | 24    | Accumulator width                            |
| `INT8_OUT_W`| 32    | Output width (saturating)                    |

The `fmt_e` enum defines three format codes: `FMT_INT8 = 2'd0`, `FMT_BF16 = 2'd1`,
`FMT_NVFP4 = 2'd2`. M1 constrains the design to `FMT_INT8` via a formal assume.

---

## 3. ACC_W sizing math

The worst-case signed product of two INT8 values is (-128) * (-128) = 16384,
which is exact in 16 bits. The worst-case 8-lane accumulation is:

```
8 * (-128) * (-128) = 131072
```

131072 in binary is 18 bits unsigned, so the signed representation needs 18 bits
of magnitude plus a sign bit = **19 signed bits minimum**. ACC_W = 24 provides
5 bits of headroom. No intermediate overflow is possible.

Because ACC_W (24) is less than INT8_OUT_W (32), the `sat_cast` function
sign-extends the 24-bit accumulator to 32 bits before comparing. The 8-lane
INT8 sum always fits in 19 signed bits, well below the 32-bit saturation
boundary, so **saturation is structurally unreachable** for any single-shot
INT8 dot-product. The `c_int8_sat_unreachable` cover property in the SVA
documents this intentional dormant path.

---

## 4. Exact-accumulate contract

No rounding occurs before the final saturating cast. Integer addition is
associative, so the result is unique regardless of addition order. The
accumulator tree computes:

1. Level 0: 8 products of 16 bits, sign-extended to 24 bits (no rounding).
2. Level 1: 4 pairwise sums at 24 bits.
3. Level 2: 2 sums of the Level-1 pairs.
4. Level 3: 1 final sum.
5. Single saturating cast to 32 bits.

This is the same computation performed by `dotprod_ref` (the golden reference),
which is proven equivalent by the FPV assertion `a_result_matches_ref`.

---

## 5. Module table

| Module              | File                      | Role                                                  |
|--------------------|---------------------------|-------------------------------------------------------|
| `dotprod_pkg`      | `rtl/dotprod_pkg.sv`      | Parameters, `fmt_e` enum, `sat_cast`, includes `dotprod_ref` |
| `front_end_int8`   | `rtl/front_end_int8.sv`   | Pass-through: wires `a_in`/`b_in` to `a_op`/`b_op`  |
| `mul_lane`         | `rtl/mul_lane.sv`         | Signed 8x8 exact multiply -> 16-bit product           |
| `align_to_fixed`   | `rtl/align_to_fixed.sv`   | Sign-extends each 16-bit product to ACC_W (24 bits)  |
| `exact_acc_tree`   | `rtl/exact_acc_tree.sv`   | Balanced 4->2->1 adder tree, all 24-bit exact        |
| `final_round`      | `rtl/final_round.sv`      | Saturating cast via `sat_cast`; `BUG_INJECTION` guard|
| `dotprod_top`      | `rtl/dotprod_top.sv`      | Combinational top: mode port, generate loop, wiring  |

All modules are purely combinational (`always_comb` or `assign`). No clock or
reset is present in M1.

---

## 6. Golden reference (`dotprod_ref`)

```
function automatic logic signed [INT8_OUT_W-1:0] dotprod_ref(
    input logic signed [INT8_W-1:0] a [N_LANES],
    input logic signed [INT8_W-1:0] b [N_LANES],
    output logic sat);
```

Defined in `ref/dotprod_ref.svh`, included into `dotprod_pkg`. The function
accumulates in ACC_W with zero intermediate rounding, then calls `sat_cast` once.
It is the **single source of truth** - consumed identically by:

1. The FPV assertion in `formal/RTL/dotprod_top_sva.sva`.
2. The directed sim scoreboard in `sim/tb/dotprod_int8_directed_tb.sv`.

There is no separate C model or Python model for M1; the SV function is exact
integer arithmetic and needs no approximation.

---

## 7. Top-level port list

| Port     | Direction | Width          | Description                              |
|---------|-----------|----------------|------------------------------------------|
| `mode`  | input     | `fmt_e` (2 bits)| Format select (M1: must be `FMT_INT8`) |
| `a`     | input     | 8 x 8 bits signed | Vector A operands                     |
| `b`     | input     | 8 x 8 bits signed | Vector B operands                     |
| `result`| output    | 32 bits signed | Saturated dot-product result             |
| `sat`   | output    | 1 bit          | Asserts when saturation occurs           |

---

## 8. Bug injection

`final_round.sv` contains a guarded mutation region:

```systemverilog
`ifdef BUG_INJECTION
  // corrupts LSB of result for every input, including zero (0^1=1)
`endif
```

The `BUG_INJECTION` variant is compiled by `formal/run/fpv_run_top_buginjected.tcl`
using `+define+BUG_INJECTION`. The FPV assertion `a_result_matches_ref` is
expected to falsify and produce a counterexample. See `doc/VerificationPlan.md`
for the expected failure analysis.

---

## 9. Deferred scope (post-M1)

- BF16 front-end, Kulisch accumulator, special-value path (M3).
- NVFP4 E2M1/E4M3 front-end, block-16 path, assume-guarantee top proof (M4).
- Full UVM environment with functional and code coverage (M2).
- Populated final report with summarized tool-generated evidence (M5).
