`ifndef FINAL_ROUND_SV
`define FINAL_ROUND_SV
import dotprod_pkg::*;
module final_round (
  input  logic signed [ACC_W-1:0]      sum,
  output logic signed [INT8_OUT_W-1:0] result,
  output logic                         sat
);
  // INT8 mode: no rounding, saturate only.
`ifdef BUG_INT8_ROUND
  // BUG: corrupt the LSB of the correct result so equivalence falsifies for
  // every input (including zero: 0 ^ 1 = 1 != 0). Uses correctly-sized
  // sat_cast output (no out-of-range part-select).
  always_comb begin
    logic sbit;
    logic signed [INT8_OUT_W-1:0] good;
    good   = sat_cast(sum, sbit);
    result = good ^ 32'sd1;
    sat    = sbit;
  end
`else
  always_comb result = sat_cast(sum, sat);
`endif
endmodule
`endif
