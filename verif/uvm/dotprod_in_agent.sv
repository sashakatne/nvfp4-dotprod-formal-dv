`ifndef DOTPROD_IN_AGENT_SV
`define DOTPROD_IN_AGENT_SV
class dotprod_in_agent extends uvm_agent;
  `uvm_component_utils(dotprod_in_agent)
  dotprod_sequencer   seqr;
  dotprod_in_driver   drv;
  dotprod_in_monitor  mon;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    seqr = dotprod_sequencer::type_id::create("seqr", this);
    drv  = dotprod_in_driver::type_id::create("drv", this);
    mon  = dotprod_in_monitor::type_id::create("mon", this);
  endfunction
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass
`endif
