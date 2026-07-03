`ifndef DOTPROD_OUT_DRIVER_SV
`define DOTPROD_OUT_DRIVER_SV
class dotprod_out_driver extends uvm_component;
  `uvm_component_utils(dotprod_out_driver)
  virtual dotprod_if vif;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual dotprod_if)::get(this,"","vif",vif))
      `uvm_fatal("OUT_DRV","no vif")
  endfunction
  task run_phase(uvm_phase phase);
    vif.out_ready <= 1'b1;
    @(posedge vif.rst_n);
    forever begin
      @(vif.outdrv_cb);
      // mostly ready, sometimes stall to exercise backpressure
      vif.outdrv_cb.out_ready <= ($urandom_range(0,3) != 0);
    end
  endtask
endclass
`endif
