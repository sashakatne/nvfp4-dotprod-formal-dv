# Design Specification - M3: BF16 Dot-Product Tier

**Author:** Sasha Katne

## 1. Overview

M1 proved a combinational INT8 dot-product core, and M2 wrapped it in a
ready/valid streaming pipeline with a full UVM environment. M3 adds a second
numeric format, BF16 (bfloat16), to the same design without disturbing the
proven INT8 arithmetic.

BF16 mode computes an 8-lane dot-product of bfloat16 operands and returns an
IEEE binary32 (FP32) result. The accumulation is **exact** within a constrained
exponent window, so there is no intermediate rounding; a single round-nearest
ties-to-even (RNE) step converts the exact fixed-point sum to FP32. Special
values (NaN, +/-Inf, +/-0) follow IEEE-754 ordering, and subnormal inputs are
flushed to zero (FTZ).

The design principle is **extend, don't fork**. The INT8 datapath modules
(`front_end_int8`, `mul_lane`, `align_to_fixed`, `exact_acc_tree`,
`final_round`) are reused unchanged. Shared operand ports widen from 8 to 16
bits; INT8 consumes only the low byte. A parallel BF16 datapath runs alongside,
and a mode mux selects the final result and status.

## 2. Numeric Contract

### 2.1 Operand format (BF16)

Bfloat16 is a 16-bit float: 1 sign bit, 8 exponent bits (bias 127), 7 mantissa
bits with an implicit leading 1 for normals.

| Field | Bits | Meaning |
|-------|------|---------|
| sign  | [15]    | operand sign |
| exp   | [14:7]  | biased exponent |
| mant  | [6:0]   | stored mantissa (hidden 1 for normals) |

Decode rules (`front_end_bf16`):
- `exp == 0`: zero. Subnormals (`exp==0, mant!=0`) are **flushed to zero** (FTZ),
  preserving sign.
- `exp == 255, mant == 0`: infinity (signed).
- `exp == 255, mant != 0`: NaN.
- otherwise: normal, significand `{1, mant}`, unbiased power `q = exp - 134`
  (the `-134` folds in the bias 127 and the 7-bit mantissa scale).

### 2.2 Constrained exponent window

M3 constrains normal operands to stored exponent `E in [119, 134]`
(`q in [-15, 0]`). This bounds every lane product magnitude so the 8-lane sum
is representable exactly in a fixed-point accumulator and cannot overflow the
FP32 normal range. The window is the load-bearing assumption of the formal
proofs and the constrained-random UVM stimulus.

Derived accumulator width: `ACC_BF16_W = 56` bits, with LSB weight `2^-30`
(`BF16_ACC_FRAC_BITS = 30`). Product significands are 8x8 -> 16 bits; the
in-window shift range plus 8-lane headroom fit in 56 signed bits exactly.

### 2.3 Lane product (`mul_lane_bf16`)

Produces a `bf16_product_t` following IEEE special ordering:
- NaN operand, or `0 * Inf` -> NaN product, `invalid = 1`.
- Inf times finite-nonzero or Inf -> signed Inf.
- zero times finite -> signed zero.
- finite normal x normal -> `p_sign = a.sign ^ b.sign`, `Q = a.q + b.q`,
  `P = a.sig * b.sig` (exact 16-bit significand product).

### 2.4 Accumulation and special resolution

Finite products align into the 56-bit fixed-point scale (`align_bf16`), shifted
by `q + 30` and two's-complement negated by sign, then summed exactly by the
reused `exact_acc_tree` at width 56. Special products bypass the numeric
accumulator: `special_case_bf16` reduces the per-lane products to a single IEEE
outcome with this priority ladder (identical to the golden `dotprod_ref_bf16`):

1. any NaN product, or both +Inf and -Inf present -> canonical QNaN, `invalid`.
2. only +Inf present -> +Inf.
3. only -Inf present -> -Inf.
4. no special product -> defer to the numeric datapath.

### 2.5 Final round (`final_round_bf16`)

When `special_valid` is set, the IEEE special result and status pass through
unchanged. Otherwise the exact 56-bit sum is converted to FP32 by:
- leading-one search to find the binade,
- biased exponent `= msb - 30 + 127`,
- 24-bit significand extraction with guard/round/sticky,
- round-nearest ties-to-even (`remainder > half`, or `remainder == half` and
  the kept LSB is odd),
- carry-out renormalization if rounding overflows the significand.

The constrained window guarantees every numeric result is a finite FP32 normal
(no denormal, no overflow to Inf); infinity/NaN reach the output only through
the special bypass.

### 2.6 Output and status

The result is a 32-bit IEEE binary32 bit-pattern; the canonical quiet NaN is
exactly `0x7FC00000` and comparisons are full 32-bit matches. Status is a packed
`dotprod_status_t`:

| Field | Meaning |
|-------|---------|
| `sat`     | INT8 saturation (always 0 in BF16) |
| `invalid` | IEEE invalid-operation flag |
| `is_nan`  | result is canonical QNaN |
| `is_inf`  | result is +/-Inf |

## 3. Module Interfaces

| Module | Function |
|--------|----------|
| `front_end_bf16`   | raw BF16 -> `bf16_decoded_t` (FTZ) |
| `mul_lane_bf16`    | two BF16 operands -> `bf16_product_t` |
| `align_bf16`       | products -> signed 56-bit fixed-point contributions |
| `exact_acc_tree#(56)` | exact 8-lane sum (reused, width-parameterized) |
| `special_case_bf16`| products -> `special_valid` / result / status |
| `final_round_bf16` | 56-bit sum + special -> FP32 result + status |

## 4. Unified Top (`dotprod_top`)

Operand ports widen to `logic [15:0] a/b [N_LANES]`; result stays 32 bits; a
`dotprod_status_t status` output is added, with `sat` retained as a
compatibility alias of `status.sat`. Both datapaths run in parallel; a
`mode`-driven mux selects the outputs. The INT8 path is fed from `a[i][7:0]`
and `b[i][7:0]`, so the proven INT8 logic is bit-identical to M1/M2. The
sequential wrapper `dotprod_seq` mirrors this structure behind the unchanged
2-cycle ready/valid handshake.

## 5. Parameters and Types (`dotprod_pkg`)

```
BF16_W=16  BF16_SIG_W=8  BF16_PROD_W=16  ACC_BF16_W=56  FP32_W=32
BF16_EXP_LO=119  BF16_EXP_HI=134  BF16_ACC_FRAC_BITS=30  FP32_QNAN=0x7FC00000
```

Types: `dotprod_status_t`, `bf16_decoded_t`, `bf16_product_t`,
`bf16_preround_t` (the pre-round `{acc, special_valid, special_result,
special_status}` handoff used by the assume-guarantee top proof).

## 6. INT8 Preservation

INT8 arithmetic modules are untouched. The INT8 FPV equivalence proof is
re-run on the widened top with arbitrary high-byte values and still proves,
directly demonstrating the high byte cannot influence the INT8 result. The M2
UVM INT8 tests (random, backpressure, corner) continue to pass with zero
mismatches.
