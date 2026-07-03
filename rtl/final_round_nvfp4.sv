`ifndef FINAL_ROUND_NVFP4_SV
`define FINAL_ROUND_NVFP4_SV
import dotprod_pkg::*;

// NVFP4 final normalize: convert exact pre-round result (inner_sum * scale) to
// IEEE binary32, or emit canonical QNaN when scale is NaN.
// inner_sum units are 0.25, so actual value = M * 2^e2 where
//   M = inner_sum * scale_sig  (signed int)
//   e2 = scale_exp - 2         (-2 converts 0.25 units to integer)
// |M| <= 518400 < 2^19, so msb <= 18 < 23 -- shift is always left, always exact.
// Mirrors dotprod_ref_nvfp4 in ref/dotprod_ref_nvfp4.svh.
module final_round_nvfp4 (
  input  logic signed [NVFP4_INNER_W-1:0] inner_sum,
  input  logic [7:0]                       scale_sig,
  input  logic signed [6:0]                scale_exp,
  input  logic                             scale_is_nan,
  output logic [FP32_W-1:0]               result,
  output dotprod_status_t                  status
);
  logic signed [31:0] M;
  logic signed [7:0]  e2;
  logic               sign_bit;
  logic [31:0]        mag;
  int                 msb;
  int                 exp_biased;
  logic [23:0]        frac;

  always_comb begin
    M          = '0;
    e2         = '0;
    sign_bit   = 1'b0;
    mag        = '0;
    msb        = 0;
    exp_biased = 0;
    frac       = '0;
    result     = '0;
    status     = '0;

`ifdef BUG_ROUND
    // BUG: drop the NaN bypass -- compute numeric path even when scale_is_nan.
    // Falls through to the else branch unconditionally; falsifies final-round TB.
    if (1'b0) begin
      result         = FP32_QNAN;
      status.invalid = 1'b1;
      status.is_nan  = 1'b1;
    end else begin
`else
    if (scale_is_nan) begin
      result         = FP32_QNAN;
      status.invalid = 1'b1;
      status.is_nan  = 1'b1;
    end else begin
`endif
      M  = 32'(signed'(inner_sum)) * 32'(signed'({1'b0, scale_sig}));
      e2 = 8'(signed'(scale_exp)) - 8'sd2;
      if (M != '0) begin
        sign_bit   = M[31];
        mag        = sign_bit ? (~M + 32'd1) : M;
        for (int i = 0; i < 32; i++) begin
          if (mag[i]) msb = i;
        end
        exp_biased = msb + int'(e2) + 127;
        // msb <= 18 always (|M| < 2^19), so first branch is always taken -- exact.
        if (msb <= 23) frac = mag << (23 - msb);
        else           frac = 'x; // unreachable: |M| < 2^24 => msb <= 18 < 23 for the valid NVFP4 domain
        result = {sign_bit, exp_biased[7:0], frac[22:0]};
      end
      // M == 0: result stays '0 = 32'h0000_0000
    end
  end
endmodule
`endif
