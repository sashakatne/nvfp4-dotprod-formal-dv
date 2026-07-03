`ifndef FRONT_END_BF16_SV
`define FRONT_END_BF16_SV
import dotprod_pkg::*;

module front_end_bf16 (
  input  logic [BF16_W-1:0] x,
  output bf16_decoded_t     d
);
  logic [7:0] exp;
  logic [6:0] mant;

  always_comb begin
    exp = x[14:7];
    mant = x[6:0];
    d = '0;
    d.sign = x[15];

    if (exp == 8'h00) begin
`ifdef BUG_INJECTION
      // BUG: treat subnormal (exp==0, mant!=0) as a normal number instead of
      // flushing to zero. Violates the FTZ contract; falsifies the lane proof.
      if (mant != 7'h00) begin
        d.sig = {1'b1, mant};
        d.q   = 10'(int'(exp) - 134);
      end else begin
        d.is_zero = 1'b1;
      end
`else
      d.is_zero = 1'b1;
`endif
    end else if (exp == 8'hFF) begin
      if (mant == 7'h00) d.is_inf = 1'b1;
      else               d.is_nan = 1'b1;
    end else begin
      d.sig = {1'b1, mant};
      d.q = 10'(int'(exp) - 134);
    end
  end
endmodule
`endif
