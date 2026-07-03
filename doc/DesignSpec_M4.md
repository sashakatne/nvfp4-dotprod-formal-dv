# Design Specification - M4: NVFP4 Dot-Product Tier

**Author:** Sasha Katne

## 1. Overview

M1 proved a combinational INT8 dot-product core, M2 wrapped it in a sequential
UVM-verified pipeline, and M3 added the BF16 float tier with an assume-guarantee
top proof. M4 adds NVFP4 (NVIDIA's Blackwell-era block-scaled FP4) as the third
numeric tier, verified formally.

An NVFP4 vector is one block of 16 E2M1 elements sharing one UE4M3 (unsigned FP8)
block scale. The dot-product of two blocks A and B factors exactly:

```
result = Σᵢ (aᵢ·sA)(bᵢ·sB) = (sA · sB) · Σᵢ (aᵢ · bᵢ),   i = 0..15
```

The per-block scales factor out of the inner sum. The inner sum is over
E2M1×E2M1 products, which are all multiples of 0.25 with bounded magnitude, so it
is computed exactly in fixed point. A single UE4M3×UE4M3 scale multiply and one
FP32 normalize produce the result. Within the format the entire result is exactly
representable in FP32, so the "rounder" only normalizes an exact integer and never
discards a bit.

The design principle continues from M2/M3: extend, don't fork. INT8 (M1) and BF16
(M3) datapaths are untouched. NVFP4 is a parallel datapath selected by `mode`,
packed into the existing 16-bit x 8-lane operand ports.

## 2. Format Facts (authoritative)

Confirmed 2026-07-02 against the OCP MX v1.0 / OFP8 specs, NVIDIA CUDA Math API,
PTX ISA 9.x, Transformer Engine docs, and arXiv:2509.25149, with adversarial
cross-checking. Sources are catalogued in `ref/nvfp4_notes.md`.

### 2.1 E2M1 element (4-bit)

Bit layout `S[3] E[2:1] M[0]`, exponent bias 1. All 16 patterns are finite (no
Inf, no NaN). Magnitudes are all multiples of 0.5: `{0, 0.5, 1, 1.5, 2, 3, 4, 6}`.
`0x8` is -0.0, arithmetically equal to +0.0.

### 2.2 UE4M3 block scale (8-bit)

Unsigned E4M3FN: sign bit structurally 0, 4 exponent bits (bias 7), 3 mantissa
bits. Max finite 448.0 (`0x7E`). Exactly one NaN pattern: `0x7F`. No Inf.

### 2.3 Block structure

Block size is 16 elements per scale. The outer per-tensor FP32 scale (two-level
microscaling) is applied in the software epilogue, not inside the inner MMA, and
is out of scope for M4.

## 3. Numeric Contract

### 3.1 Element decode (`front_end_nvfp4`)

Decode each 4-bit element to a signed integer in units of 0.5 (an exact integer):
magnitudes `{0,1,2,3,4,6,8,12}` for the eight `{E,M}` codes, sign from `x[3]`.
`-0` decodes to integer 0.

### 3.2 Element product (`mul_lane_nvfp4`)

`prodᵢ = aᵢ_int × bᵢ_int`, an exact signed integer in units of 0.25, magnitude
≤ 12×12 = 144 (9-bit signed `nvfp4_product_t.prod`). A tiny finite relation
proved near-exhaustively.

### 3.3 Exact inner sum (`align_nvfp4` + `exact_acc_tree#(N=16)`)

Sum of 16 products in units of 0.25. Worst case |sum| = 16×144 = 2304, i.e. 576.0.
Exact in signed 13-bit (`NVFP4_INNER_W=13`, Q10.2). No rounding. `align_nvfp4`
sign-extends each 9-bit product into a 13-bit lane; the reused `exact_acc_tree`
(now lane-count parameterized, N=16) sums them.

### 3.4 Scale multiply and final normalize

`scale_mul_nvfp4` decodes both UE4M3 scales into an integer significand and a
power-of-two weight (`value = sig × 2^k`, `k = exp-10` normal / `-9` subnormal),
forms `scale_sig = sigA × sigB` (exact, ≤ 225) and `scale_exp = kA + kB` (range
[-18,10]), and flags NaN if either scale is `0x7F`.

`final_round_nvfp4` forms the exact signed integer `M = inner_sum × scale_sig`
(|M| ≤ 518400 < 2²⁴) with net weight `scale_exp - 2`, and encodes `M × 2^(scale_exp-2)`
to FP32 by leading-one normalize. Because |M| < 2²⁴ the result is exact (the
right-shift branch is unreachable). Overflow-to-Inf is structurally impossible for
in-format inputs. A NaN scale bypasses to canonical FP32 QNaN `0x7FC00000`.

### 3.5 Output and status

FP32 (IEEE binary32) result on the shared 32-bit port. Status reuses
`dotprod_status_t`: `is_nan`/`invalid` set only by a NaN block scale; `is_inf`
and `sat` always 0 for NVFP4.

## 4. Datapath and Port Packing

NVFP4 packs into the existing `logic [15:0] a/b [N_LANES=8]` (128 bits/vector).
Defined logical layout: element k at `a[k/4][4*(k%4) +: 4]`, UE4M3 scale at
`a[4][7:0]`. INT8/BF16 bit usage is unchanged. The golden unpack helper
(`ref_unpack_nvfp4`), the RTL unpack, and the UVM packer (`pack_nvfp4`) share this
layout.

The NVFP4 datapath: `nvfp4_unpack → 16× mul_lane_nvfp4 (blackboxed in top proof)
→ align_nvfp4 → exact_acc_tree#(16) → scale_mul_nvfp4 → final_round_nvfp4`. A
`mode` mux selects NVFP4 outputs; INT8/BF16 paths are untouched. The sequential
wrapper `dotprod_seq` mirrors this behind the unchanged 2-cycle handshake, keyed
on the staged `mode_s1`.

## 5. Parameters and Types (`dotprod_pkg`)

```
NVFP4_BLOCK=16  E2M1_W=4  UE4M3_W=8  NVFP4_INNER_W=13  UE4M3_NAN=8'h7F
```

Types: `e2m1_decoded_t {sign, mag_int[3:0]}`, `nvfp4_product_t {prod signed[8:0]}`,
`nvfp4_preround_t {inner_sum signed[12:0], scale_sig[7:0], scale_exp signed[6:0],
scale_is_nan}`. `exact_acc_tree` gains `parameter int N = N_LANES`; the default
keeps INT8/BF16 instances a bit-identical balanced pairwise tree.

## 6. INT8/BF16 Preservation

INT8 and BF16 arithmetic modules are untouched. The INT8 top FPV, BF16 top AG,
and sequential protocol proofs are re-run on the widened design and still prove;
the M2/M3 UVM tests still pass with zero mismatches. `exact_acc_tree`'s
generalization to N lanes preserves the proven N=8 structure (verified by
re-running the BF16 `a_acc_is_lane_sum` assertion).
