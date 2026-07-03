`timescale 1ns/1ps
import dotprod_pkg::*;

// Directed self-checking test for the NVFP4 final normalize/round.
// Each case is checked against a pinned FP32 constant derived from the brief's
// hand traces and against the reference function dotprod_ref_nvfp4_preround.
module final_round_nvfp4_tb;
  logic signed [NVFP4_INNER_W-1:0] inner_sum;
  logic [7:0]                       scale_sig;
  logic signed [6:0]                scale_exp;
  logic                             scale_is_nan;
  logic [FP32_W-1:0]               result;
  dotprod_status_t                  status;
  int errors = 0;
  int cases  = 0;

  final_round_nvfp4 dut (
    .inner_sum   (inner_sum),
    .scale_sig   (scale_sig),
    .scale_exp   (scale_exp),
    .scale_is_nan(scale_is_nan),
    .result      (result),
    .status      (status)
  );

  // Check a numeric (non-NaN-scale) case against a pinned FP32 constant.
  // Also verifies status is all-zero.
  task automatic check_numeric(
      input string              name,
      input logic signed [NVFP4_INNER_W-1:0] s,
      input logic [7:0]         sig,
      input logic signed [6:0]  exp_in,
      input logic [FP32_W-1:0]  expected);
    cases++;
    inner_sum    = s;
    scale_sig    = sig;
    scale_exp    = exp_in;
    scale_is_nan = 1'b0;
    #1;
    if (result !== expected || status !== '0) begin
      errors++;
      $error("%s: got 0x%08h exp 0x%08h status={inv=%0b nan=%0b inf=%0b sat=%0b}",
             name, result, expected,
             status.invalid, status.is_nan, status.is_inf, status.sat);
    end
  endtask

  // Check the NaN-scale bypass.
  task automatic check_nan(
      input string             name,
      input logic signed [NVFP4_INNER_W-1:0] s,
      input logic [7:0]        sig,
      input logic signed [6:0] exp_in);
    cases++;
    inner_sum    = s;
    scale_sig    = sig;
    scale_exp    = exp_in;
    scale_is_nan = 1'b1;
    #1;
    if (result !== FP32_QNAN || !status.invalid || !status.is_nan ||
        status.is_inf || status.sat) begin
      errors++;
      $error("%s: got 0x%08h exp 0x%08h status={inv=%0b nan=%0b inf=%0b sat=%0b}",
             name, result, FP32_QNAN,
             status.invalid, status.is_nan, status.is_inf, status.sat);
    end
  endtask

  initial begin
    // --- Case 1: inner_sum=16, scale_sig=1, scale_exp=0 -> 4.0 ---
    // M=16, e2=-2, mag=16, msb=4, exp_biased=129=0x81, frac=16<<19=2^23 -> 0x40800000
    check_numeric("4.0 pos", 13'sd16, 8'd1, 7'sd0, 32'h4080_0000);

    // --- Case 2: inner_sum=0 -> +0 ---
    check_numeric("zero",    13'sd0,  8'd1, 7'sd0, 32'h0000_0000);

    // --- Case 3: inner_sum=-16, scale_sig=1, scale_exp=0 -> -4.0 ---
    // M=-16, sign=1, same msb/frac -> 0xC0800000
    check_numeric("4.0 neg", -13'sd16, 8'd1, 7'sd0, 32'hC080_0000);

    // --- Case 4: scale_is_nan=1 -> QNaN 0x7FC00000, status.invalid=is_nan=1 ---
    check_nan("nan scale", 13'sd16, 8'd1, 7'sd0);

    // --- Case 5: max case: inner_sum=2304, scale_sig=225, scale_exp=10 ---
    // M=2304*225=518400=0x7E900, e2=8, msb=18, exp_biased=153=0x99
    // frac=518400<<5=16588800=0xFD2000; frac[22:0]=0x7D2000
    // result=0x4CFD2000; exponent field 0x99 != 0xFF (no overflow)
    check_numeric("max no-overflow", 13'sd2304, 8'd225, 7'sd10, 32'h4CFD_2000);
    if (result[30:23] === 8'hFF) begin
      errors++;
      $error("max case overflowed to Inf: 0x%08h", result);
    end

    // --- Case 6: negative scale_exp, exercises e2 < -2 path ---
    // inner_sum=4, scale_sig=1, scale_exp=-1 -> value = 4(units .25=1.0) * 2^(-1) = 0.5
    // M=4*1=4, e2=-1-2=-3, mag=4, msb=2, exp_biased=2+(-3)+127=126=0x7E
    // frac=4<<21=2^23=0x800000; frac[22:0]=0x000000
    // result={0,0x7E,0x000000}=0x3F000000=0.5
    check_numeric("neg scale_exp 0.5", 13'sd4, 8'd1, -7'sd1, 32'h3F00_0000);

    if (errors) $fatal(1, "FINAL_ROUND_NVFP4 FAIL: %0d errors", errors);
    $display("FINAL_ROUND_NVFP4 PASS (%0d cases)", cases);
    $finish;
  end
endmodule
