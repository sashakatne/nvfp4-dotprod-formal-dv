`ifndef SCALE_MUL_NVFP4_SV
`define SCALE_MUL_NVFP4_SV
import dotprod_pkg::*;

module scale_mul_nvfp4 (
  input  logic [7:0]           sa, sb,
  output logic [7:0]           scale_sig,
  output logic signed [6:0]    scale_exp,
  output logic                 scale_is_nan
);
  function automatic void dec(input logic [7:0] x, output logic [3:0] sig, output logic signed [6:0] k, output logic nan);
    logic [3:0] exp; logic [2:0] mant;
    exp = x[6:3]; mant = x[2:0]; sig='0; k='0; nan=1'b0;
`ifdef BUG_NAN
    if (x == 8'h7E) nan = 1'b1;  // BUG: treat 0x7E as NaN instead of 0x7F
    else if (exp == 4'd0) begin
`else
    if (x == UE4M3_NAN) nan = 1'b1;
    else if (exp == 4'd0) begin
`endif
      if (mant == 3'd0) begin sig = 4'd0; k = '0; end
      else begin sig = {1'b0, mant}; k = -7'sd9; end
    end else begin
`ifdef BUG_SCALE
      sig = {1'b1, mant}; k = 7'(int'(exp) - 9);  // BUG: off-by-one, should be exp-10
`else
      sig = {1'b1, mant}; k = 7'(int'(exp) - 10);
`endif
    end
  endfunction

  logic [3:0] siga, sigb; logic signed [6:0] ka, kb; logic na, nb;

  always_comb begin
    dec(sa, siga, ka, na); dec(sb, sigb, kb, nb);
    scale_is_nan = na || nb;
    scale_sig    = 8'(siga) * 8'(sigb);
    scale_exp    = ka + kb;
  end
endmodule
`endif
