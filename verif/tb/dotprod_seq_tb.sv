`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"
import dotprod_pkg::*;
import dotprod_uvm_pkg::*;

module dotprod_seq_tb;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  dotprod_if vif (.clk(clk), .rst_n(rst_n));

  dotprod_seq dut (
    .clk(clk), .rst_n(rst_n), .mode(vif.mode),
    .a(vif.a), .b(vif.b),
    .in_valid(vif.in_valid), .in_ready(vif.in_ready),
    .result(vif.result), .status(vif.status), .sat(vif.sat),
    .out_valid(vif.out_valid), .out_ready(vif.out_ready)
  );

  // Set the vif and start UVM at time 0. The set precedes run_test in the same
  // block, so build_phase (which get()s the vif) cannot race ahead of it. No
  // time may be consumed before run_test() (UVM RUNPHSTIME rule).
  initial begin
    uvm_config_db#(virtual dotprod_if)::set(null, "*", "vif", vif);
    run_test();
  end

  // Drive synchronous active-low reset concurrently. Starts at 0 (declared),
  // releases after a few clocks, producing the posedge the drivers wait on.
  initial begin
    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;
  end
endmodule
