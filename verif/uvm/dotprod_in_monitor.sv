`ifndef DOTPROD_IN_MONITOR_SV
`define DOTPROD_IN_MONITOR_SV
class dotprod_in_monitor extends uvm_monitor;
  `uvm_component_utils(dotprod_in_monitor)
  virtual dotprod_if vif;
  uvm_analysis_port#(dotprod_seq_item) ap_in;
  function new(string name, uvm_component parent); super.new(name,parent); ap_in=new("ap_in",this); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual dotprod_if)::get(this,"","vif",vif))
      `uvm_fatal("IN_MON","no vif")
  endfunction
  task run_phase(uvm_phase phase);
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.in_valid === 1'b1 && vif.mon_cb.in_ready === 1'b1) begin
        dotprod_seq_item t = dotprod_seq_item::type_id::create("t");
        t.a = vif.mon_cb.a; t.b = vif.mon_cb.b; t.mode = vif.mon_cb.mode;
        ap_in.write(t);
      end
    end
  endtask
endclass
`endif
