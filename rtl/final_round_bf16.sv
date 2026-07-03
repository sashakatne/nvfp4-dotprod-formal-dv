`ifndef FINAL_ROUND_BF16_SV
`define FINAL_ROUND_BF16_SV
import dotprod_pkg::*;

// BF16 final rounder: convert the exact 56-bit fixed-point accumulator (LSB
// weight 2^-30) to IEEE binary32 with round-nearest-ties-to-even, or pass the
// special outcome through when special_valid is set.
//
// The constrained exponent window bounds |sum| well below the FP32 overflow
// and underflow thresholds, so the numeric path is always an FP32 normal (no
// denormal, no Inf). Infinity/NaN reach the output only via the special bypass.
// This mirrors ref_round_bf16_acc_to_fp32 in ref/dotprod_ref_bf16.svh.
module final_round_bf16 (
  input  logic signed [ACC_BF16_W-1:0] sum,
  input  logic                         special_valid,
  input  logic [FP32_W-1:0]            special_result,
  input  dotprod_status_t              special_status,
  output logic [FP32_W-1:0]            result,
  output dotprod_status_t              status
);
  logic                       sign;
  logic [ACC_BF16_W-1:0]      mag;
  logic [ACC_BF16_W-1:0]      shifted;
  logic [ACC_BF16_W-1:0]      low_mask;
  logic [ACC_BF16_W-1:0]      remainder;
  logic [ACC_BF16_W-1:0]      half;
  logic [24:0]                sig_ext;   // 1 guard + 24 significand bits
  logic [7:0]                 exp_bits;
  logic                       round_up;
  logic [FP32_W-1:0]          numeric_result;
  int                         msb;
  int                         shift;
  int                         exp_biased;

  always_comb begin
    // ---- numeric normalize + RNE round (identical to the golden) ----
    sign       = 1'b0;
    mag        = '0;
    shifted    = '0;
    low_mask   = '0;
    remainder  = '0;
    half       = '0;
    sig_ext    = '0;
    exp_bits   = '0;
    round_up   = 1'b0;
    msb        = 0;
    shift      = 0;
    exp_biased = 0;

    if (sum == '0) begin
      numeric_result = '0;
    end else begin
      sign = sum[ACC_BF16_W-1];
      mag  = sign ? (~sum + ACC_BF16_W'(1)) : sum;

      for (int i = 0; i < ACC_BF16_W; i++) begin
        if (mag[i]) msb = i;
      end

      exp_biased = msb - BF16_ACC_FRAC_BITS + 127;

      if (msb <= 23) begin
        // Value fits exactly in the significand: shift up, no rounding.
        shifted = mag << (23 - msb);
        sig_ext = {1'b0, shifted[23:0]};
      end else begin
        shift   = msb - 23;
        shifted = mag >> shift;
        sig_ext = {1'b0, shifted[23:0]};

        low_mask  = (ACC_BF16_W'(1) << shift) - ACC_BF16_W'(1);
        remainder = mag & low_mask;
        half      = ACC_BF16_W'(1) << (shift - 1);
        round_up  = (remainder > half) || ((remainder == half) && sig_ext[0]);
`ifdef BUG_INJECTION
        // BUG: truncate instead of round-nearest-even. Any input whose exact
        // sum has a fractional part above the round threshold now mismatches
        // dotprod_ref_bf16, falsifying the top AG proof.
        round_up = 1'b0;
`endif
        if (round_up) sig_ext = sig_ext + 25'd1;

        if (sig_ext[24]) begin
          // Rounding carried into a new binade.
          sig_ext    = sig_ext >> 1;
          exp_biased = exp_biased + 1;
        end
      end

      exp_bits       = exp_biased[7:0];
      numeric_result = {sign, exp_bits, sig_ext[22:0]};
    end

    // ---- special bypass mux ----
    if (special_valid) begin
      result = special_result;
      status = special_status;
    end else begin
      result = numeric_result;
      status = '0;             // numeric result: finite, valid, not saturated
    end
  end
endmodule
`endif
