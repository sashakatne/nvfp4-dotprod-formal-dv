# Verification Plan - M3: BF16 Dot-Product Tier

**Author:** Sasha Katne

## 1. Scope

### In Scope
- BF16 numeric equivalence against the golden `dotprod_ref_bf16`
- Constrained exponent window `E in [119, 134]` (exact accumulation)
- IEEE special-value handling: NaN, +/-Inf, +/-0, `0*Inf`, Inf-minus-Inf
- FTZ of subnormal inputs
- RNE rounding of the exact 56-bit sum to FP32
- Assume-guarantee (AG) formal decomposition of the top proof
- Unified INT8/BF16 top and sequential wrapper
- INT8 regression guard on the widened design
- BF16 bug-injection mutation testing
- UVM BF16 constrained-random and directed-corner regression

### Out of Scope
- NVFP4 mode (M4)
- Output denormals and overflow-to-Inf from numeric sums (structurally
  unreachable inside the window)
- Operands outside the exponent window (excluded by assumption)
- Timing closure and synthesis

## 2. Formal Strategy: Assume-Guarantee Decomposition

The top-level BF16 equivalence (`dotprod_top` result == `dotprod_ref_bf16`)
does not close as a single monolithic proof: the data-dependent barrel-shift
aligner and the RNE rounder each appear on both sides of the equivalence miter
and exhaust the engine (observed inconclusive). The proof is decomposed into
four converging pieces, composed by transitivity:

| # | Proof | Guarantee established |
|---|-------|-----------------------|
| 1 | Lane (`mul_lane_bf16_sva`)   | `mul_lane_bf16 == ref_mul_bf16` under the window |
| 2 | Align (`align_bf16_sva`)     | `align_bf16` lane == `ref_align_bf16_lane` |
| 3 | Round (`final_round_bf16_sva`) | `final_round_bf16 == ref_round` / special bypass |
| 4 | Top (`dotprod_bf16_sva`)     | linear pre-round reduction == golden pre-round |

**Top proof mechanics.** `mul_lane_bf16` is blackboxed
(`set_blackbox -designs {mul_lane_bf16}` before `read_file`). The bound SVA
assumes each blackbox product equals `ref_mul_bf16`, assumes operands are in the
window, and asserts the DUT's pre-round outputs equal the golden pre-round
reduction (`dotprod_ref_bf16_preround`):

- `a_acc_is_lane_sum`: `sum_bf16 == sum_i wide_bf16[i]` (accumulator-tree
  linearity; the DUT's own aligned lanes feed both sides so the shifter cancels
  structurally).
- `a_special_valid/result/status_matches_ref`: the special ladder.

The full rounded-result equivalence follows outside the tool by transitivity of
proofs 1-4. This structure also rehearses the M4 NVFP4 blackbox proof.

**Special-value properties** (`dotprod_bf16_special_sva`) prove the IEEE
priority ladder for `special_case_bf16` standalone over all product
combinations.

**Environment.** Combinational proofs use a named virtual clock
(`create_clock -name vclk`); the sequential proof uses a real `create_clock clk`
plus `create_reset rst_n -sense low`.

## 3. Bug-Injection Mutation Testing

Each guarded fault is caught by the proof that owns the mutated logic:

| Define | Mutation | Falsified property |
|--------|----------|--------------------|
| `BUG_INJECTION` (front_end) | subnormal treated as normal (no FTZ) | lane `a_product_matches_ref`, `a_decode_zero_ftz` |
| `BUG_ALIGN` (align)         | off-by-one alignment shift          | align `a_align_lane` (all 8 lanes) |
| `BUG_INJECTION` (final_round) | truncate instead of RNE           | round `a_numeric_round` |
| `BUG_SPECIAL` (special)     | dropped Inf-minus-Inf case          | top `a_special_result/status_matches_ref` |
| `BUG_INJECTION` (seq)       | drop held output under stall        | seq `p_hold_stable` |

Default builds define none of these and remain clean.

## 4. Sequential Protocol FPV

`dotprod_seq_sva` (bound to `dotprod_seq`) proves, under the widened datapath:
- `p_hold_stable`: `result` and **all status fields** stable under backpressure.
- `p_no_out_at_reset`: no spurious output the cycle reset releases.
- `p_stall_blocks_ready`: stall implies not ready.
- `p_sat_alias`: `sat == status.sat`.
Covers: `c_backpressure`, `c_accept`.

## 5. UVM Environment (extended from M2)

The M2 layered environment is extended, not forked:
- **Interface / transaction**: operands widen to 16 bits (`logic`), result to
  32 bits plus `dotprod_status_t`. INT8 uses the sign-extended low byte.
- **Sequences**: INT8 random/corner preserved; new `dotprod_bf16_seq`
  (constrained-random from a curated operand pool that hits the window and
  special ladder) and `dotprod_bf16_corner_seq` (directed NaN, +/-Inf,
  Inf-minus-Inf, `0*Inf`, FTZ, cancellation, max in-window).
- **Scoreboard**: dispatches by `mode` to the committed goldens
  (`dotprod_ref` / `dotprod_ref_bf16`); never duplicates DUT math. Compares
  result and all status fields.
- **Coverage**: INT8 `cg_value` preserved; new `cg_bf16_operand`
  (zero/subnormal/small/large/max-window/Inf/NaN) and `cg_bf16_result`
  (zero/normal/NaN/+Inf/-Inf); protocol `cg_proto` unchanged.
- **Tests**: `dotprod_bf16_test`, `dotprod_bf16_corner_test` added.

## 6. Pass Criteria

- All clean FPV assertions proven (covers covered or documented uncoverable).
- Every bug-injected proof falsifies its target property at a reported depth.
- INT8 regression: widened top proof proven; bug-injected still falsifies.
- UVM: every test reports `mismatched=0 leftover=0`, `UVM_ERROR=0`,
  `UVM_FATAL=0`.
- Merged functional + code coverage reported.

Actual results are recorded in `FinalReport_M3.md` from tool-generated evidence only.
