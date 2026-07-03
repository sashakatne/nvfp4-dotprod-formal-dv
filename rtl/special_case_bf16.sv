`ifndef SPECIAL_CASE_BF16_SV
`define SPECIAL_CASE_BF16_SV
import dotprod_pkg::*;

// BF16 special-value resolver.
//
// Reduces the per-lane products to a single IEEE-style special outcome,
// mirroring the priority ladder in dotprod_ref_bf16:
//   1. any NaN product, or both +Inf and -Inf present -> canonical QNaN, invalid
//   2. only +Inf present                              -> +Inf
//   3. only -Inf present                              -> -Inf
//   4. no special product                             -> special_valid=0
//
// When special_valid=0 the numeric accumulator/rounder owns the result.
// Special outcomes bypass the numeric datapath entirely; special_status.sat
// is always 0 (BF16 does not saturate).
module special_case_bf16 (
  input  bf16_product_t     prod [N_LANES],
  output logic              special_valid,
  output logic [FP32_W-1:0] special_result,
  output dotprod_status_t   special_status
);
  localparam logic [FP32_W-1:0] FP32_POS_INF = 32'h7F80_0000;
  localparam logic [FP32_W-1:0] FP32_NEG_INF = 32'hFF80_0000;

  logic any_nan;      // some lane produced a NaN (NaN operand or 0*Inf)
  logic saw_pos_inf;  // some lane produced +Inf
  logic saw_neg_inf;  // some lane produced -Inf

  always_comb begin
    any_nan     = 1'b0;
    saw_pos_inf = 1'b0;
    saw_neg_inf = 1'b0;

    foreach (prod[i]) begin
      if (prod[i].is_nan) begin
        any_nan = 1'b1;
      end else if (prod[i].is_inf) begin
        if (prod[i].p_sign) saw_neg_inf = 1'b1;
        else                saw_pos_inf = 1'b1;
      end
    end

    special_result = '0;
    special_status = '0;

    // Every BF16 NaN product is an invalid operation (NaN operand or 0*Inf),
    // and Inf-minus-Inf is invalid too; match dotprod_ref_bf16 exactly by
    // asserting invalid whenever the NaN outcome is taken.
`ifdef BUG_SPECIAL
    // BUG: drop the Inf-minus-Inf case from the NaN condition, so +Inf and -Inf
    // together wrongly fall through to the single-Inf branch instead of QNaN.
    // In-cone for the top AG proof; falsifies a_special_result_matches_ref.
    if (any_nan) begin
`else
    if (any_nan || (saw_pos_inf && saw_neg_inf)) begin
`endif
      special_valid          = 1'b1;
      special_result         = FP32_QNAN;
      special_status.is_nan  = 1'b1;
      special_status.invalid = 1'b1;
    end else if (saw_pos_inf || saw_neg_inf) begin
      special_valid         = 1'b1;
      special_result        = saw_neg_inf ? FP32_NEG_INF : FP32_POS_INF;
      special_status.is_inf = 1'b1;
    end else begin
      special_valid = 1'b0;
    end
  end
endmodule
`endif
