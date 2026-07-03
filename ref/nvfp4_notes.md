# NVFP4 Golden Reference Notes

Verified: 2026-07-02

## E2M1 element format

4-bit format: sign[3], exp[2:1], mantissa[0]. The exponent field EE has no bias
(values 0-3 map directly). The magnitude lookup table:

| {EE, M} | mag_int (units 0.5) | real value |
|---------|---------------------|------------|
| 000     | 0                   | 0.0        |
| 001     | 1                   | 0.5        |
| 010     | 2                   | 1.0        |
| 011     | 3                   | 1.5        |
| 100     | 4                   | 2.0        |
| 101     | 6                   | 3.0        |
| 110     | 8                   | 4.0        |
| 111     | 12                  | 6.0        |

Products of two E2M1 values are computed as mag_a * mag_b with sign XOR. The
result is in units of 0.25 (since 0.5 * 0.5 = 0.25). Max single product:
12 * 12 = 144 units, fits in a signed 9-bit integer.

## UE4M3 scale format

8-bit unsigned: unsigned[7] (always 0 for valid), exp[6:3], mant[2:0]. Bias = 7.
Only NaN is 0x7F (all exponent and mantissa bits set). No Inf encoding. No subnormal
implies zero (exp=0, mant=0); subnormal non-zero: sig={0,mant}, k=-9.
Normal: sig={1,mant}, k=exp-10. Max finite value is 0x7E = exp=15 (0xF), mant=6 →
sig={1,110}=14, k=15-10=5 → 14*2^5 = 448.0. Only 0x7F (exp=15, mant=7) is NaN; all
other exp=15 patterns are finite. So exp=15 is NOT reserved for NaN except the single
0x7F encoding (this is the E4M3FN "finite" variant). Max finite = 448.0 per OCP OFP8.

## Block-16 structure

Each NVFP4 vector covers 16 E2M1 elements packed into 4 16-bit words (4 elements
per word, LSNibble = element 0 of the word) plus a 5th word whose low byte holds
the UE4M3 block scale. Port packing:
- element k: v[k/4][4*(k%4) +: 4]
- scale: v[4][7:0]

## Dot-product factoring

The block dot-product is (sA * sB) * sum_i(a_i * b_i) where sA, sB are UE4M3
scale factors. This factors the scale out of the sum, so the inner sum is computed
exactly in a 13-bit signed integer (max |inner_sum| = 16 * 144 = 2304 < 2^12),
then multiplied by scale_sig (8-bit, max 15*15=225) to give M (max |M| = 2304*225
= 518400 < 2^20 < 2^24 - fits exactly in FP32 mantissa). The final value is
M * 2^(scale_exp - 2).

## FP32 exactness

Because |M| < 2^24, the FP32 encoding is exact (no rounding needed). The golden
function computes: find msb of |M|, set exp_biased = msb + e2 + 127, shift
mantissa, pack sign/exp/frac directly. The comment "exact, no rounding since <2^24"
in the code refers to this property.

## References

- OCP Microscaling Formats (MX) Specification v1.0
- OCP Open Floating-Point (OFP8) Formats Specification Rev 1.0
- NVIDIA CUDA C Programming Guide, Math API (mma.sync NVFP4 section)
- NVIDIA PTX ISA 9.x (wmma/mma NVFP4 operations)
- NVIDIA Transformer Engine documentation (FP8/FP4 tensor core usage)
- arXiv:2509.25149 (block floating-point dot-product analysis)
