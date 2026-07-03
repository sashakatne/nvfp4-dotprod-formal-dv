`timescale 1ns/1ps
import dotprod_pkg::*;

module report_top_modes_tb;
  logic [BF16_W-1:0] a [N_LANES], b [N_LANES];
  fmt_e              mode;
  logic [1:0]        mode_bits;
  logic [3:0]        case_id;
  logic [FP32_W-1:0] result;
  logic [FP32_W-1:0] expected_result;
  dotprod_status_t   status;
  logic              sat;
  logic              status_invalid, status_is_nan, status_is_inf;
  int                errors = 0;

  assign mode_bits      = mode;
  assign status_invalid = status.invalid;
  assign status_is_nan  = status.is_nan;
  assign status_is_inf  = status.is_inf;

  dotprod_top dut (
    .mode(mode),
    .a(a),
    .b(b),
    .result(result),
    .status(status),
    .sat(sat)
  );

  task automatic clear_inputs();
    foreach (a[i]) begin
      a[i] = '0;
      b[i] = '0;
    end
  endtask

  task automatic pack_elem(ref logic [15:0] v [N_LANES],
                           input int k,
                           input logic [3:0] val);
    v[k/4][4*(k%4) +: 4] = val;
  endtask

  task automatic pack_scale(ref logic [15:0] v [N_LANES],
                            input logic [7:0] scale);
    v[4][7:0] = scale;
  endtask

  task automatic check_current(
      input string name,
      input logic exp_invalid,
      input logic exp_nan,
      input logic exp_inf);
    #2;
    if (result !== expected_result ||
        status.invalid !== exp_invalid ||
        status.is_nan !== exp_nan ||
        status.is_inf !== exp_inf) begin
      errors++;
      $error("REPORT_TOP_MODE %s mismatch: got result=0x%08h inv=%0b nan=%0b inf=%0b expected result=0x%08h inv=%0b nan=%0b inf=%0b",
             name, result, status.invalid, status.is_nan, status.is_inf,
             expected_result, exp_invalid, exp_nan, exp_inf);
    end else begin
      $display("REPORT_TOP_MODE %s PASS result=0x%08h inv=%0b nan=%0b inf=%0b",
               name, result, status.invalid, status.is_nan, status.is_inf);
    end
    #8;
  endtask

  initial begin
    logic signed [INT8_W-1:0] a8 [N_LANES], b8 [N_LANES];
    logic exp_sat;
    logic exp_invalid, exp_nan, exp_inf;

    clear_inputs();
    mode = FMT_INT8;
    case_id = 4'd0;
    expected_result = '0;
    #10;

    case_id = 4'd1;
    foreach (a8[i]) begin
      a8[i] = 8'sd127;
      b8[i] = 8'sd127;
      a[i] = {8'hA5, a8[i]};
      b[i] = {8'h5A, b8[i]};
    end
    expected_result = FP32_W'(dotprod_ref(a8, b8, exp_sat));
    check_current("int8_max_positive", 1'b0, 1'b0, 1'b0);

    case_id = 4'd2;
    clear_inputs();
    mode = FMT_BF16;
    foreach (a[i]) begin
      a[i] = 16'h3F80;
      b[i] = 16'h3F80;
    end
    expected_result = dotprod_ref_bf16(a, b, exp_invalid, exp_nan, exp_inf);
    check_current("bf16_eight_ones", exp_invalid, exp_nan, exp_inf);

    case_id = 4'd3;
    clear_inputs();
    mode = FMT_NVFP4;
    for (int k = 0; k < NVFP4_BLOCK; k++) begin
      pack_elem(a, k, 4'h2);
      pack_elem(b, k, 4'h2);
    end
    pack_scale(a, 8'h38);
    pack_scale(b, 8'h38);
    expected_result = dotprod_ref_nvfp4(a, b, exp_invalid, exp_nan, exp_inf);
    check_current("nvfp4_all_ones", exp_invalid, exp_nan, exp_inf);

    case_id = 4'd4;
    clear_inputs();
    mode = FMT_NVFP4;
    for (int k = 0; k < NVFP4_BLOCK; k++) begin
      pack_elem(a, k, 4'h2);
      pack_elem(b, k, 4'h2);
    end
    pack_scale(a, 8'h7F);
    pack_scale(b, 8'h38);
    expected_result = dotprod_ref_nvfp4(a, b, exp_invalid, exp_nan, exp_inf);
    check_current("nvfp4_nan_scale", exp_invalid, exp_nan, exp_inf);

    case_id = 4'd5;
    if (errors) $fatal(1, "REPORT_TOP_MODES FAIL: %0d errors", errors);
    $display("REPORT_TOP_MODES PASS");
    $finish;
  end
endmodule
