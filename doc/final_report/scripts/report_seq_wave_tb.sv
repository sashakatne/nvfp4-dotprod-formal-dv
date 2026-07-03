`timescale 1ns/1ps
import dotprod_pkg::*;

module report_seq_wave_tb;
  logic                  clk = 1'b0;
  logic                  rst_n = 1'b0;
  fmt_e                  mode;
  logic [BF16_W-1:0]     a [N_LANES], b [N_LANES];
  logic                  in_valid;
  logic                  in_ready;
  logic [FP32_W-1:0]     result;
  dotprod_status_t       status;
  logic                  sat;
  logic                  out_valid;
  logic                  out_ready;
  logic                  report_assert_failed = 1'b0;

`ifdef BUG_INJECTION
  localparam bit EXPECT_FAIL = 1'b1;
`else
  localparam bit EXPECT_FAIL = 1'b0;
`endif

  always #5 clk = ~clk;

  dotprod_seq dut (
    .clk(clk),
    .rst_n(rst_n),
    .mode(mode),
    .a(a),
    .b(b),
    .in_valid(in_valid),
    .in_ready(in_ready),
    .result(result),
    .status(status),
    .sat(sat),
    .out_valid(out_valid),
    .out_ready(out_ready)
  );

  property p_report_hold_stable;
    @(posedge clk) disable iff (!rst_n)
      out_valid && !out_ready |=>
        out_valid && $stable(result) && $stable(status) && $stable(sat);
  endproperty

  a_report_hold_stable: assert property (p_report_hold_stable)
    else begin
      report_assert_failed = 1'b1;
      $display("REPORT_ASSERT_FAIL p_hold_stable time=%0t out_valid=%0b out_ready=%0b result=0x%08h",
               $time, out_valid, out_ready, result);
    end

  task automatic drive_int8_case();
    mode = FMT_INT8;
    foreach (a[i]) begin
      a[i] = {8'hA5, 8'sd1};
      b[i] = {8'h5A, i[7:0]};
    end
  endtask

  initial begin
    in_valid = 1'b0;
    out_ready = 1'b1;
    mode = FMT_INT8;
    foreach (a[i]) begin
      a[i] = '0;
      b[i] = '0;
    end

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    repeat (1) @(posedge clk);

    drive_int8_case();
    in_valid = 1'b1;
    @(posedge clk);
    in_valid = 1'b0;

    wait (out_valid === 1'b1);
    #1;
    out_ready = 1'b0;
    repeat (2) @(posedge clk);
    out_ready = 1'b1;
    repeat (2) @(posedge clk);

    if (EXPECT_FAIL && !report_assert_failed)
      $fatal(1, "REPORT_SEQ_WAVE expected p_hold_stable failure but none occurred");
    if (!EXPECT_FAIL && report_assert_failed)
      $fatal(1, "REPORT_SEQ_WAVE unexpected p_hold_stable failure");

    $display("REPORT_SEQ_WAVE PASS expect_fail=%0b fail_seen=%0b", EXPECT_FAIL, report_assert_failed);
    $finish;
  end
endmodule
