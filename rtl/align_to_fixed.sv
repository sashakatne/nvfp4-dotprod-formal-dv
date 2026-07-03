`ifndef ALIGN_TO_FIXED_SV
`define ALIGN_TO_FIXED_SV
import dotprod_pkg::*;
module align_to_fixed (
  input  logic signed [PROD_W-1:0] prod [N_LANES],
  output logic signed [ACC_W-1:0]  wide [N_LANES]
);
  genvar i;
  generate
    for (i = 0; i < N_LANES; i++) begin : g_ext
      assign wide[i] = ACC_W'(prod[i]);   // sign-extend, no rounding
    end
  endgenerate
endmodule
`endif
