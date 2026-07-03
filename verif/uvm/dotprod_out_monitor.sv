`ifndef DOTPROD_OUT_MONITOR_SV
`define DOTPROD_OUT_MONITOR_SV
class dotprod_out_monitor extends uvm_monitor;
  `uvm_component_utils(dotprod_out_monitor)
  virtual dotprod_if vif;
  uvm_analysis_port#(dotprod_seq_item) ap_out;
  function new(string name, uvm_component parent); super.new(name,parent); ap_out=new("ap_out",this); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual dotprod_if)::get(this,"","vif",vif))
      `uvm_fatal("OUT_MON","no vif")
  endfunction
  task run_phase(uvm_phase phase);
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.out_valid === 1'b1 && vif.mon_cb.out_ready === 1'b1) begin
        dotprod_seq_item t = dotprod_seq_item::type_id::create("t");
        t.result = vif.mon_cb.result; t.status = vif.mon_cb.status; t.sat = vif.mon_cb.sat;
        // Tag with the mode observed at the output beat for debug/trace. The
        // scoreboard pairs by FIFO order (not by this field); mode-accurate
        // result-class attribution under the 2-cycle latency is handled by the
        // coverage subscriber's in-flight mode queue.
        t.mode = vif.mon_cb.mode;
        ap_out.write(t);
      end
    end
  endtask
endclass
`endif
