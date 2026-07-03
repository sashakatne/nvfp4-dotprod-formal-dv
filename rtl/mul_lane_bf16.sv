`ifndef MUL_LANE_BF16_SV
`define MUL_LANE_BF16_SV
import dotprod_pkg::*;

module mul_lane_bf16 (
  input  logic [BF16_W-1:0] a,
  input  logic [BF16_W-1:0] b,
  output bf16_product_t     product
);
  bf16_decoded_t da;
  bf16_decoded_t db;

  front_end_bf16 fe_a (.x(a), .d(da));
  front_end_bf16 fe_b (.x(b), .d(db));

  always_comb begin
    product = '0;
    product.p_sign = da.sign ^ db.sign;

    if (da.is_nan || db.is_nan || da.is_oor || db.is_oor) begin
      // NaN operand, or an out-of-range (out-of-window normal) operand: both are
      // invalid operations that emit a canonical QNaN and bypass the numeric
      // accumulator via the special ladder.
      product.is_nan = 1'b1;
      product.invalid = 1'b1;
    end else if ((da.is_zero && db.is_inf) || (da.is_inf && db.is_zero)) begin
      product.is_nan = 1'b1;
      product.invalid = 1'b1;
    end else if (da.is_inf || db.is_inf) begin
      product.is_inf = 1'b1;
    end else if (da.is_zero || db.is_zero) begin
      product.is_zero = 1'b1;
    end else begin
      product.p = da.sig * db.sig;
      product.q = da.q + db.q;
    end
  end
endmodule
`endif
