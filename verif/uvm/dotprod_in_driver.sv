`ifndef DOTPROD_IN_DRIVER_SV
`define DOTPROD_IN_DRIVER_SV
class dotprod_in_driver extends uvm_driver#(dotprod_seq_item);
  `uvm_component_utils(dotprod_in_driver)
  virtual dotprod_if vif;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual dotprod_if)::get(this,"","vif",vif))
      `uvm_fatal("IN_DRV","no vif")
  endfunction
  task run_phase(uvm_phase phase);
    dotprod_seq_item req;
    // idle defaults — blocking assigns at time 0, no clocking-block race
    vif.in_valid = 1'b0;
    foreach (vif.a[i]) vif.a[i] = '0;
    foreach (vif.b[i]) vif.b[i] = '0;
    vif.mode = FMT_INT8;
    @(posedge vif.rst_n);
    forever begin
      // random idle gap (bubble injection)
      int gap = $urandom_range(0,2);
      repeat (gap) @(vif.drv_cb);
      seq_item_port.get_next_item(req);
      vif.drv_cb.a       <= req.a;
      vif.drv_cb.b       <= req.b;
      vif.drv_cb.mode    <= req.mode;
      vif.drv_cb.in_valid<= 1'b1;
      // hold until accepted (in_ready high at a posedge)
      do @(vif.drv_cb); while (vif.drv_cb.in_ready !== 1'b1);
      vif.drv_cb.in_valid<= 1'b0;
      seq_item_port.item_done();
    end
  endtask
endclass
`endif
