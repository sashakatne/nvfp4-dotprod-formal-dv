`timescale 1ns/1ps
import dotprod_pkg::*;
// Directed self-checking test of the unified top in BF16 mode. Expected values
// come from the golden dotprod_ref_bf16 (single source of truth); a few
// landmark FP32 constants are also pinned as independent anchors.
module dotprod_bf16_directed_tb;
  logic [BF16_W-1:0]  a [N_LANES], b [N_LANES];
  logic [FP32_W-1:0]  result;
  dotprod_status_t    status;
  logic               sat;
  logic [FP32_W-1:0]  exp;
  logic               exp_inv, exp_nan, exp_inf;
  int errors = 0;
  int cases  = 0;

  dotprod_top dut (.mode(FMT_BF16), .a(a), .b(b),
                   .result(result), .status(status), .sat(sat));

  task automatic clear_inputs();
    foreach (a[i]) begin a[i]='0; b[i]='0; end
  endtask

  // Check RTL against the golden, and optionally against a pinned anchor.
  task automatic check(
      input string             name,
      input logic              pin,
      input logic [FP32_W-1:0] anchor);
    cases++;
    #1;
    exp = dotprod_ref_bf16(a, b, exp_inv, exp_nan, exp_inf);
    if (result !== exp ||
        status.invalid !== exp_inv || status.is_nan !== exp_nan ||
        status.is_inf !== exp_inf || status.sat !== 1'b0 ||
        (pin && result !== anchor)) begin
      errors++;
      $error("%s: result=0x%08h status{inv=%0b nan=%0b inf=%0b} exp=0x%08h{inv=%0b nan=%0b inf=%0b} anchor(pin=%0b)=0x%08h",
             name, result, status.invalid, status.is_nan, status.is_inf,
             exp, exp_inv, exp_nan, exp_inf, pin, anchor);
    end
  endtask

  initial begin
    // numeric all-ones -> FP32 +8.0
    clear_inputs();
    foreach (a[i]) begin a[i]=16'h3F80; b[i]=16'h3F80; end
    check("eight ones", 1'b1, 32'h4100_0000);

    // exact cancellation -> +0
    clear_inputs();
    a[0]=16'h3F80; b[0]=16'h3F80;   // +1
    a[1]=16'hBF80; b[1]=16'h3F80;   // -1
    check("cancellation", 1'b1, 32'h0000_0000);

    // NaN operand -> canonical QNaN, invalid
    clear_inputs();
    a[0]=16'h7FC1; b[0]=16'h3F80;
    check("nan operand", 1'b1, FP32_QNAN);

    // +Inf only -> +Inf
    clear_inputs();
    a[0]=16'h7F80; b[0]=16'h3F80;
    check("pos inf", 1'b1, 32'h7F80_0000);

    // Inf minus Inf -> canonical QNaN, invalid
    clear_inputs();
    a[0]=16'h7F80; b[0]=16'h3F80;   // +Inf
    a[1]=16'hFF80; b[1]=16'h3F80;   // -Inf
    check("inf minus inf", 1'b1, FP32_QNAN);

    // FTZ subnormal contribution: lane0 subnormal -> +0, lane1 +1*+1 -> +1.0
    clear_inputs();
    a[0]=16'h0001; b[0]=16'h3F80;
    a[1]=16'h3F80; b[1]=16'h3F80;
    check("ftz subnormal", 1'b1, 32'h3F80_0000);

    // Out-of-range operand: 256.0 (exp 143, above the [119,134] window) times
    // 1.0. The OOR guard folds it into an invalid QNaN for the whole block.
    clear_inputs();
    a[0]=16'h4780; b[0]=16'h3F80;   // 256.0 * 1.0 -> OOR
    check("oor operand", 1'b1, FP32_QNAN);

    if (errors) $fatal(1, "DOTPROD_BF16_DIRECTED FAIL: %0d errors", errors);
    $display("DOTPROD_BF16_DIRECTED PASS (%0d cases)", cases);
    $finish;
  end
endmodule
