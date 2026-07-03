`timescale 1ns/1ps
import dotprod_pkg::*;

module dotprod_bf16_ref_tb;
  logic [BF16_W-1:0] a [N_LANES], b [N_LANES];
  logic [FP32_W-1:0] result;
  logic invalid, is_nan, is_inf;
  bf16_product_t prod;
  int errors = 0;
  int cases = 0;

  task automatic clear_inputs();
    foreach (a[i]) begin
      a[i] = '0;
      b[i] = '0;
    end
  endtask

  task automatic check_dot(
      input string name,
      input logic [FP32_W-1:0] exp_result,
      input logic exp_invalid,
      input logic exp_is_nan,
      input logic exp_is_inf);
    cases++;
    result = dotprod_ref_bf16(a, b, invalid, is_nan, is_inf);
    if (result !== exp_result || invalid !== exp_invalid ||
        is_nan !== exp_is_nan || is_inf !== exp_is_inf) begin
      errors++;
      $error("%s: got result=0x%08h invalid=%0b is_nan=%0b is_inf=%0b exp=0x%08h/%0b/%0b/%0b",
             name, result, invalid, is_nan, is_inf,
             exp_result, exp_invalid, exp_is_nan, exp_is_inf);
    end
  endtask

  task automatic check_lane_product();
    cases++;
    prod = ref_mul_bf16(16'h3F80, 16'hBF80); // +1.0 * -1.0
    if (prod.p_sign !== 1'b1 || prod.q !== -10'sd14 ||
        prod.p !== 16'h4000 || prod.is_nan || prod.is_inf ||
        prod.is_zero || prod.invalid) begin
      errors++;
      $error("ref_mul_bf16 finite lane mismatch");
    end

    cases++;
    prod = ref_mul_bf16(16'h0000, 16'h7F80); // +0 * +Inf
    if (!prod.is_nan || !prod.invalid || prod.is_inf || prod.is_zero) begin
      errors++;
      $error("ref_mul_bf16 invalid 0*Inf lane mismatch");
    end
  endtask

  initial begin
    check_lane_product();

    clear_inputs();
    foreach (a[i]) begin
      a[i] = 16'h3F80; // BF16 +1.0
      b[i] = 16'h3F80; // BF16 +1.0
    end
    check_dot("eight ones", 32'h4100_0000, 1'b0, 1'b0, 1'b0); // FP32 +8.0

    clear_inputs();
    a[0] = 16'h0000; // +0
    b[0] = 16'h7F80; // +Inf
    check_dot("zero times inf", FP32_QNAN, 1'b1, 1'b1, 1'b0);

    clear_inputs();
    a[0] = 16'h7F80; // +Inf
    b[0] = 16'h3F80; // +1.0
    a[1] = 16'hFF80; // -Inf
    b[1] = 16'h3F80; // +1.0
    check_dot("inf minus inf", FP32_QNAN, 1'b1, 1'b1, 1'b0);

    clear_inputs();
    a[0] = 16'h7FC1; // NaN
    b[0] = 16'h3F80; // +1.0
    check_dot("nan operand", FP32_QNAN, 1'b1, 1'b1, 1'b0);

    clear_inputs();
    a[0] = 16'h0001; // BF16 subnormal, FTZ to +0
    b[0] = 16'h3F80; // +1.0
    a[1] = 16'h3F80; // +1.0
    b[1] = 16'h3F80; // +1.0
    check_dot("subnormal ftz", 32'h3F80_0000, 1'b0, 1'b0, 1'b0);

    clear_inputs();
    a[0] = 16'h3F80; // +1.0
    b[0] = 16'h3F80; // +1.0
    a[1] = 16'hBF80; // -1.0
    b[1] = 16'h3F80; // +1.0
    check_dot("exact cancellation", 32'h0000_0000, 1'b0, 1'b0, 1'b0);

    if (errors) $fatal(1, "DOTPROD_BF16_REF FAIL: %0d errors", errors);
    $display("DOTPROD_BF16_REF PASS (%0d cases)", cases);
    $finish;
  end
endmodule
