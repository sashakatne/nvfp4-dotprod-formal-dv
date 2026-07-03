`timescale 1ns/1ps
import dotprod_pkg::*;

// Directed self-checking test for the BF16 special-case resolver.
// The resolver mirrors the special-value priority ladder of dotprod_ref_bf16:
//   NaN (any lane) or (+Inf and -Inf together) -> canonical QNaN, invalid
//   single-signed Inf                          -> +Inf / -Inf
//   otherwise                                  -> special_valid=0 (defer to numeric)
module special_case_bf16_tb;
  bf16_product_t     prod [N_LANES];
  logic              special_valid;
  logic [FP32_W-1:0] special_result;
  dotprod_status_t   special_status;
  int errors = 0;
  int cases  = 0;

  special_case_bf16 dut (
    .prod           (prod),
    .special_valid  (special_valid),
    .special_result (special_result),
    .special_status (special_status)
  );

  // Reset every lane to a finite numeric product (is_zero=0, no special flags).
  task automatic clear_products();
    foreach (prod[i]) begin
      prod[i]         = '0;
      prod[i].p       = 16'h4000;   // some finite significand product
      prod[i].q       = 10'sd0;
    end
    #1;
  endtask

  task automatic check(
      input string             name,
      input logic              exp_valid,
      input logic [FP32_W-1:0] exp_result,
      input dotprod_status_t   exp_status);
    cases++;
    #1;
    if (special_valid !== exp_valid ||
        (exp_valid && special_result !== exp_result) ||
        special_status !== exp_status) begin
      errors++;
      $error("%s: valid=%0b result=0x%08h status={sat=%0b inv=%0b nan=%0b inf=%0b} exp valid=%0b result=0x%08h status={sat=%0b inv=%0b nan=%0b inf=%0b}",
             name, special_valid, special_result,
             special_status.sat, special_status.invalid, special_status.is_nan, special_status.is_inf,
             exp_valid, exp_result,
             exp_status.sat, exp_status.invalid, exp_status.is_nan, exp_status.is_inf);
    end
  endtask

  // Convenience constructors for status expectations.
  function automatic dotprod_status_t st(input logic sat, invalid, is_nan, is_inf);
    st = '{sat:sat, invalid:invalid, is_nan:is_nan, is_inf:is_inf};
  endfunction

  initial begin
    // 1: all finite -> resolver defers to numeric datapath.
    clear_products();
    check("all finite", 1'b0, 32'h0, st(0,0,0,0));

    // 2: a NaN product (e.g. NaN operand) -> canonical QNaN + invalid.
    clear_products();
    prod[2] = '0; prod[2].is_nan = 1'b1; prod[2].invalid = 1'b1;
    check("nan product", 1'b1, FP32_QNAN, st(0,1,1,0));

    // 3: 0*Inf presents identically to the resolver (is_nan + invalid).
    clear_products();
    prod[7] = '0; prod[7].is_nan = 1'b1; prod[7].invalid = 1'b1;
    check("zero times inf", 1'b1, FP32_QNAN, st(0,1,1,0));

    // 4: +Inf and -Inf together -> canonical QNaN + invalid (Inf minus Inf).
    clear_products();
    prod[0] = '0; prod[0].is_inf = 1'b1; prod[0].p_sign = 1'b0;
    prod[1] = '0; prod[1].is_inf = 1'b1; prod[1].p_sign = 1'b1;
    check("inf minus inf", 1'b1, FP32_QNAN, st(0,1,1,0));

    // 5: only +Inf -> +Inf.
    clear_products();
    prod[3] = '0; prod[3].is_inf = 1'b1; prod[3].p_sign = 1'b0;
    check("pos inf only", 1'b1, 32'h7F80_0000, st(0,0,0,1));

    // 6: only -Inf -> -Inf.
    clear_products();
    prod[4] = '0; prod[4].is_inf = 1'b1; prod[4].p_sign = 1'b1;
    check("neg inf only", 1'b1, 32'hFF80_0000, st(0,0,0,1));

    // 7: NaN dominates coexisting infinities (priority: NaN over Inf).
    clear_products();
    prod[0] = '0; prod[0].is_inf = 1'b1; prod[0].p_sign = 1'b0;
    prod[5] = '0; prod[5].is_nan = 1'b1; prod[5].invalid = 1'b1;
    check("nan over inf", 1'b1, FP32_QNAN, st(0,1,1,0));

    // 8: multiple same-signed infinities still resolve to that single Inf.
    clear_products();
    prod[2] = '0; prod[2].is_inf = 1'b1; prod[2].p_sign = 1'b1;
    prod[6] = '0; prod[6].is_inf = 1'b1; prod[6].p_sign = 1'b1;
    check("two neg inf", 1'b1, 32'hFF80_0000, st(0,0,0,1));

    if (errors) $fatal(1, "SPECIAL_CASE_BF16 FAIL: %0d errors", errors);
    $display("SPECIAL_CASE_BF16 PASS (%0d cases)", cases);
    $finish;
  end
endmodule
