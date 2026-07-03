`ifndef DOTPROD_UVM_PKG_SV
`define DOTPROD_UVM_PKG_SV
package dotprod_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import dotprod_pkg::*;

  `include "dotprod_seq_item.sv"
  `include "dotprod_sequencer.sv"
  `include "dotprod_sequences.sv"
  `include "dotprod_in_driver.sv"
  `include "dotprod_out_driver.sv"
  `include "dotprod_in_monitor.sv"
  `include "dotprod_out_monitor.sv"
  `include "dotprod_in_agent.sv"
  `include "dotprod_out_agent.sv"
  `include "dotprod_scoreboard.sv"
  `include "dotprod_coverage.sv"
  `include "dotprod_env.sv"
  `include "dotprod_tests.sv"
endpackage
`endif
