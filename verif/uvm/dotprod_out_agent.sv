`ifndef DOTPROD_OUT_AGENT_SV
`define DOTPROD_OUT_AGENT_SV
class dotprod_out_agent extends uvm_agent;
  `uvm_component_utils(dotprod_out_agent)
  dotprod_out_driver  drv;
  dotprod_out_monitor mon;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv = dotprod_out_driver::type_id::create("drv", this);
    mon = dotprod_out_monitor::type_id::create("mon", this);
  endfunction
endclass
`endif
