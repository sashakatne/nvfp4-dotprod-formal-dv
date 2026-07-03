`ifndef ALIGN_BF16_SV
`define ALIGN_BF16_SV
import dotprod_pkg::*;

module align_bf16 (
  input  bf16_product_t                    prod [N_LANES],
  output logic signed [ACC_BF16_W-1:0]     wide [N_LANES]
);
  logic signed [ACC_BF16_W-1:0] contrib;
  int shift_amt;

  always_comb begin
    foreach (prod[i]) begin
      wide[i] = '0;
      contrib = '0;
      shift_amt = int'(prod[i].q) + BF16_ACC_FRAC_BITS;

      if (!prod[i].is_zero && !prod[i].is_inf && !prod[i].is_nan) begin
`ifdef BUG_ALIGN
        // BUG: off-by-one alignment shift. Every finite product lands one binary
        // position too high, so the accumulated sum mismatches dotprod_ref_bf16
        // and the top AG proof falsifies. Dedicated define so the top bug proof
        // isolates exactly this fault (the rounder is assumed-correct there).
        contrib = ACC_BF16_W'(prod[i].p) <<< (shift_amt + 1);
`else
        contrib = ACC_BF16_W'(prod[i].p) <<< shift_amt;
`endif
        wide[i] = prod[i].p_sign ? -contrib : contrib;
      end
    end
  end
endmodule
`endif
