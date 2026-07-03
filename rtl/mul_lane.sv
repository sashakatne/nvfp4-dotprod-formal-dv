`ifndef MUL_LANE_SV
`define MUL_LANE_SV
import dotprod_pkg::*;
module mul_lane (
  input  logic signed [INT8_W-1:0] a_op,
  input  logic signed [INT8_W-1:0] b_op,
  output logic signed [PROD_W-1:0] prod
);
  assign prod = a_op * b_op;   // signed 8x8 -> 16b, exact
endmodule
`endif
