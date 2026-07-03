`timescale 1ns/1ps
import dotprod_pkg::*;

// Directed self-checking test for the BF16 final RNE rounder.
// Numeric cases are checked against the golden ref_round_bf16_acc_to_fp32
// (single source of truth) and against hand-pinned FP32 constants for landmark
// inputs. The special bypass is checked directly.
module final_round_bf16_tb;
  logic signed [ACC_BF16_W-1:0] sum;
  logic                         special_valid;
  logic [FP32_W-1:0]            special_result;
  dotprod_status_t              special_status;
  logic [FP32_W-1:0]            result;
  dotprod_status_t              status;
  int errors = 0;
  int cases  = 0;

  final_round_bf16 dut (
    .sum            (sum),
    .special_valid  (special_valid),
    .special_result (special_result),
    .special_status (special_status),
    .result         (result),
    .status         (status)
  );

  // Numeric round: check RTL against the golden, plus an optional pinned anchor.
  task automatic check_numeric(
      input string             name,
      input logic signed [ACC_BF16_W-1:0] s,
      input logic              pin,           // also assert against anchor?
      input logic [FP32_W-1:0] anchor);
    logic [FP32_W-1:0] gold;
    cases++;
    special_valid  = 1'b0;
    special_result = '0;
    special_status = '0;
    sum            = s;
    #1;
    gold = ref_round_bf16_acc_to_fp32(s);
    if (result !== gold || status !== '0 ||
        (pin && result !== anchor)) begin
      errors++;
      $error("%s: sum=0x%014h result=0x%08h gold=0x%08h anchor(pin=%0b)=0x%08h status={inv=%0b nan=%0b inf=%0b sat=%0b}",
             name, s, result, gold, pin, anchor,
             status.invalid, status.is_nan, status.is_inf, status.sat);
    end
  endtask

  // Special bypass: result and status must equal the special inputs verbatim,
  // regardless of the numeric sum.
  task automatic check_special(
      input string             name,
      input logic signed [ACC_BF16_W-1:0] s,
      input logic [FP32_W-1:0] sp_result,
      input dotprod_status_t   sp_status);
    cases++;
    special_valid  = 1'b1;
    special_result = sp_result;
    special_status = sp_status;
    sum            = s;
    #1;
    if (result !== sp_result || status !== sp_status) begin
      errors++;
      $error("%s: result=0x%08h exp=0x%08h status!=special", name, result, sp_result);
    end
  endtask

  function automatic dotprod_status_t st(input logic sat, invalid, is_nan, is_inf);
    st = '{sat:sat, invalid:invalid, is_nan:is_nan, is_inf:is_inf};
  endfunction

  initial begin
    // exact zero -> +0
    check_numeric("zero", 56'sd0, 1'b1, 32'h0000_0000);
    // exact +4.0: value = 4 * 2^30 = 2^32
    check_numeric("pos pow2 4.0", 56'sd1 <<< 32, 1'b1, 32'h4080_0000);
    // exact +1.0: value = 2^30
    check_numeric("pos pow2 1.0", 56'sd1 <<< 30, 1'b1, 32'h3F80_0000);
    // exact -2.0: value = -(2^31)
    check_numeric("neg pow2 -2.0", -(56'sd1 <<< 31), 1'b1, 32'hC000_0000);
    // tie, even kept-LSB -> round down (no increment): mag = 2^24 + 1
    check_numeric("tie even", (56'sd1 <<< 24) + 56'sd1, 1'b1, 32'h3C80_0000);
    // tie, odd kept-LSB -> round up: mag = 2^24 + 2 + 1
    check_numeric("tie odd", (56'sd1 <<< 24) + 56'sd3, 1'b1, 32'h3C80_0002);
    // sticky greater than half -> round up: mag = 2^25 + 3
    check_numeric("gt half", (56'sd1 <<< 25) + 56'sd3, 1'b1, 32'h3D00_0001);
    // max in-window magnitude -> finite normal, not Inf (checked vs golden;
    // anchor asserts exponent field below 0xFF).
    check_numeric("max window", 56'sd8 * (56'sd65025 <<< 30), 1'b0, 32'h0);
    if (result[30:23] === 8'hFF) begin
      errors++; $error("max window overflowed to Inf: 0x%08h", result);
    end

    // special bypass cases: numeric sum must be ignored.
    check_special("bypass qnan",  56'sd12345, FP32_QNAN,      st(0,1,1,0));
    check_special("bypass +inf",  -56'sd999,  32'h7F80_0000,  st(0,0,0,1));
    check_special("bypass -inf",  56'sd1 <<< 40, 32'hFF80_0000, st(0,0,0,1));

    if (errors) $fatal(1, "FINAL_ROUND_BF16 FAIL: %0d errors", errors);
    $display("FINAL_ROUND_BF16 PASS (%0d cases)", cases);
    $finish;
  end
endmodule
