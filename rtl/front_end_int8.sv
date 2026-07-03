`ifndef FRONT_END_INT8_SV
`define FRONT_END_INT8_SV
import dotprod_pkg::*;
module front_end_int8 (
  input  logic signed [INT8_W-1:0] a_in,
  input  logic signed [INT8_W-1:0] b_in,
  output logic signed [INT8_W-1:0] a_op,
  output logic signed [INT8_W-1:0] b_op
);
  assign a_op = a_in;   // INT8: operands used directly
  assign b_op = b_in;
endmodule
`endif
