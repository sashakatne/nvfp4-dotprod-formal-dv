`ifndef DOTPROD_REF_SVH
`define DOTPROD_REF_SVH
// Exact INT8 dot-product golden. Summed in ACC_W with zero intermediate
// rounding (integer add is associative), then saturated once to INT8_OUT_W.
function automatic logic signed [INT8_OUT_W-1:0] dotprod_ref
    (input logic signed [INT8_W-1:0] a [N_LANES],
     input logic signed [INT8_W-1:0] b [N_LANES],
     output logic sat);
  logic signed [ACC_W-1:0] acc;
  logic signed [PROD_W-1:0] p;
  acc = '0;
  for (int i = 0; i < N_LANES; i++) begin
    p   = a[i] * b[i];            // exact signed 8x8 -> 16b
    acc = acc + ACC_W'(p);        // exact accumulate
  end
  dotprod_ref = sat_cast(acc, sat);
endfunction
`endif
