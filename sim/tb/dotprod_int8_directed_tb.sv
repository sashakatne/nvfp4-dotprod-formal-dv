`timescale 1ns/1ps
import dotprod_pkg::*;
module dotprod_int8_directed_tb;
  // INT8 stimulus values and the widened 16-bit operand ports the unified top
  // now exposes. The INT8 datapath consumes only the low byte, so the high byte
  // is deliberately filled with noise to prove it is ignored.
  logic signed [INT8_W-1:0] a8 [N_LANES], b8 [N_LANES];
  logic        [BF16_W-1:0] a  [N_LANES], b  [N_LANES];
  logic [FP32_W-1:0]        result;
  dotprod_status_t          status;
  logic                     sat;
  logic signed [INT8_OUT_W-1:0] exp;
  logic                     exp_sat;
  int errors = 0;

  dotprod_top dut (.mode(FMT_INT8), .a(a), .b(b),
                   .result(result), .status(status), .sat(sat));

  // Pack INT8 values into the low byte; scribble a nonzero high byte.
  task automatic drive();
    foreach (a8[i]) begin
      a[i] = {8'hA5, a8[i]};
      b[i] = {8'h5A, b8[i]};
    end
  endtask

  task automatic check(string name);
    drive();
    #1;
    exp = dotprod_ref(a8, b8, exp_sat);
    // INT8 result occupies the low 32 bits; compare as signed via reinterpret.
    if ($signed(result) !== exp || sat !== exp_sat || status.sat !== exp_sat ||
        status.invalid !== 1'b0 || status.is_nan !== 1'b0 || status.is_inf !== 1'b0) begin
      errors++;
      $error("%s: got %0d/%0b exp %0d/%0b (status inv=%0b nan=%0b inf=%0b)",
             name, $signed(result), sat, exp, exp_sat,
             status.invalid, status.is_nan, status.is_inf);
    end
  endtask

  initial begin
    // 1: zeros
    foreach (a8[i]) begin a8[i]='0; b8[i]='0; end check("zeros");
    // 2: all max negative*max positive  => 8*(-128*127) = -130048, no sat
    foreach (a8[i]) begin a8[i]=-8'sd128; b8[i]=8'sd127; end check("min*max");
    // 3: all max positive               => 8*(127*127)  = 129032, no sat
    foreach (a8[i]) begin a8[i]=8'sd127; b8[i]=8'sd127; end check("max*max");
    // 4: alternating cancel             => 4*(100)-4*(100) = 0
    foreach (a8[i]) begin a8[i]=(i%2==0)?8'sd100:-8'sd100; b8[i]=8'sd1; end check("cancel");
    // 5: single lane active             => 50*2 = 100
    foreach (a8[i]) begin a8[i]='0; b8[i]='0; end a8[3]=8'sd50; b8[3]=8'sd2; check("single");
    // 6: identity (ramp b)              => sum i=0..7 of 1*i = 28
    foreach (a8[i]) begin a8[i]=8'sd1; b8[i]=i[7:0]; end check("ramp");

    if (errors) $fatal(1, "DIRECTED FAIL: %0d errors", errors);
    $display("DOTPROD_INT8_DIRECTED PASS (%0d cases)", 6);
    $finish;
  end
endmodule
