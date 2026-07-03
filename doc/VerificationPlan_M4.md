# Verification Plan - M4: NVFP4 Dot-Product Tier

**Author:** Sasha Katne

## 1. Scope

### In Scope
- NVFP4 numeric equivalence against the golden `dotprod_ref_nvfp4`
- Block-16 E2M1 elements + UE4M3 block scale, packed into existing ports
- Exact inner accumulation; UE4M3 NaN handling; FP32 output
- Assume-guarantee formal decomposition of the top proof
- Unified INT8/BF16/NVFP4 top and sequential wrapper
- INT8/BF16 regression guard on the widened design
- NVFP4 bug-injection mutation testing
- UVM NVFP4 constrained-random and directed-corner regression

### Out of Scope
- Outer per-tensor FP32 scale (two-level microscaling)
- SM-specific physical nibble layouts (a clean logical layout is defined)
- NVFP4 Inf/denormal output (structurally impossible in-format)

## 2. Formal Strategy: Assume-Guarantee Decomposition

The top NVFP4 equivalence is proven by blackboxing the element multiplier and
composing standalone proofs, applying and extending the M3 lesson.

| Proof | Establishes |
|-------|-------------|
| Lane (`mul_lane_nvfp4_sva`) | element decode + `aᵢ·bᵢ` == `ref_mul_nvfp4`, near-exhaustive |
| Scale (`scale_mul_nvfp4_sva`) | `sA·sB` significand/exp + NaN == golden |
| Top (`dotprod_nvfp4_sva`) | linear pre-round reduction == golden pre-round |
| Final round (`final_round_nvfp4`) | proven by directed sim vs golden (exact, no rounding) |

**Top proof mechanics.** `mul_lane_nvfp4` is blackboxed
(`set_blackbox -designs {mul_lane_nvfp4}` before `read_file`). The bound SVA
assumes each blackbox product equals `ref_mul_nvfp4`, assumes `mode == FMT_NVFP4`,
and asserts at the pre-round boundary:
- `a_inner_is_lane_sum`: `nvfp4_inner_sum == Σ nvfp4_wide[i]` (accumulator-tree
  linearity, pure DUT nets).
- `a_align_lane` (per lane): `nvfp4_wide[i] == sign_ext(nvfp4_prod[i].prod)`
  (align correctness, pure DUT nets).
- `a_scale_sig/exp/nan_ref`: DUT scale outputs == golden pre-round scale fields.

**Why pure-DUT assertions.** A monolithic `nvfp4_inner_sum == golden inner_sum`
assertion, and even a transitivity variant that summed
`ref_mul_nvfp4(...)` in the assertion, both STALLED — a golden function call
inside an assertion is expensive for the engine to elaborate even when its result
is assumed equal. Asserting only over DUT nets (`a_inner_is_lane_sum`,
`a_align_lane`) removes all golden multiply/unpack elaboration from the miter; the
proof then converges immediately (20 assertions in seconds). The full
`result == dotprod_ref_nvfp4` follows by transitivity outside the tool:
`a_inner_is_lane_sum` + `a_align_lane` + the lane guarantee give
`nvfp4_inner_sum == Σ sign_ext(ref_mul_nvfp4(...)) == golden inner_sum`, since the
DUT unpack and the golden unpack use identical indexing; the scale fields match
directly; and the standalone final-round proof closes the FP32 encode. This
soundness chain was independently reviewed.

## 3. Bug-Injection Mutation Testing

Each guarded fault is caught by the proof owning the mutated logic; default builds
define none of these and stay clean (byte-identical default paths).

| Define | Mutation | Falsified |
|--------|----------|-----------|
| `BUG_INJECTION` (front_end) | E2M1 6.0 → int 8 not 12 | lane `a_product_matches_ref`, `a_decode_matches_ref` |
| `BUG_SCALE` (scale) | UE4M3 `k = exp-9` (off-by-one) | scale `a_exp` |
| `BUG_NAN` (scale) | NaN detect `0x7E` not `0x7F` | scale `a_nan` + top `a_scale_nan_ref` |
| `BUG_ALIGN` (align) | product shifted ×2 | top `a_align_lane` |
| `BUG_ROUND` (round) | drop NaN bypass | final-round TB |

## 4. Sequential Protocol FPV

`dotprod_seq_sva` (format-agnostic) proves under the widened datapath:
`p_hold_stable` (result + all status fields stable under backpressure),
`p_no_out_at_reset`, `p_stall_blocks_ready`, `p_sat_alias`; covers
`c_backpressure`, `c_accept`. Bug-injected `p_hold_stable` falsifies.

## 5. UVM Environment (extended from M2/M3)

- **Transaction**: `pack_nvfp4` static helper packs 16 E2M1 nibbles + UE4M3 scale
  into the a/b arrays per the shared layout. INT8/BF16 constraints unchanged.
- **Sequences**: `dotprod_nvfp4_seq` (constrained-random over E2M1 value classes
  + UE4M3 scale classes) and `dotprod_nvfp4_corner_seq` (all-zero block, single
  outlier, max scale 0x7E, min scale, mixed sign, NaN scale 0x7F).
- **Scoreboard**: dispatches `FMT_NVFP4 → dotprod_ref_nvfp4`; never duplicates DUT
  math.
- **Coverage**: `cg_nvfp4_element` (zero/subnormal/small/large/max/neg),
  `cg_nvfp4_scale` (zero/subnormal/normal/max/nan), `cg_nvfp4_block`
  (all-zero, sign-mix), `cg_nvfp4_result` (zero/normal/nan).
- **Tests**: `dotprod_nvfp4_test`, `dotprod_nvfp4_corner_test` (7 tests total).

## 6. Pass Criteria

- All clean FPV assertions proven; covers covered or documented uncoverable.
- Every bug-injected proof falsifies its target property.
- INT8/BF16 regression: widened top/sequential proofs proven; bug-injected
  falsify. M2/M3 UVM tests still pass.
- UVM: every test `mismatched=0 leftover=0`, `UVM_ERROR=0 UVM_FATAL=0`; merged
  coverage reported.

Actual results are recorded in `FinalReport_M4.md` from tool-generated evidence only.
