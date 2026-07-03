`ifndef DOTPROD_IF_SV
`define DOTPROD_IF_SV
import dotprod_pkg::*;
interface dotprod_if (input logic clk, input logic rst_n);
  // Whole-array fields are 4-state (logic) so seq_item<->interface whole-array
  // copies are legal in Questa. Operands widened to BF16 width; INT8 uses the
  // low byte. Result is the shared 32-bit INT8/FP32 bit-pattern.
  logic [BF16_W-1:0]   a [N_LANES];
  logic [BF16_W-1:0]   b [N_LANES];
  fmt_e                mode;
  logic                in_valid, in_ready;
  logic [FP32_W-1:0]   result;
  dotprod_status_t     status;
  logic                sat;
  logic                out_valid, out_ready;

  clocking drv_cb @(posedge clk);
    output a, b, mode, in_valid;
    input  in_ready;
  endclocking
  clocking outdrv_cb @(posedge clk);
    output out_ready;
    input  out_valid;
  endclocking
  clocking mon_cb @(posedge clk);
    input a, b, mode, in_valid, in_ready, result, status, sat, out_valid, out_ready;
  endclocking

  modport IN_DRV  (clocking drv_cb,    input clk, rst_n);
  modport OUT_DRV (clocking outdrv_cb, input clk, rst_n);
  modport MON     (clocking mon_cb,    input clk, rst_n);
endinterface
`endif
