`ifndef DOTPROD_ENV_SV
`define DOTPROD_ENV_SV
class dotprod_env extends uvm_env;
  `uvm_component_utils(dotprod_env)
  dotprod_in_agent  in_agent;
  dotprod_out_agent out_agent;
  dotprod_scoreboard scb;
  dotprod_coverage   cov;
  virtual dotprod_if vif;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    in_agent  = dotprod_in_agent::type_id::create("in_agent", this);
    out_agent = dotprod_out_agent::type_id::create("out_agent", this);
    scb = dotprod_scoreboard::type_id::create("scb", this);
    cov = dotprod_coverage::type_id::create("cov", this);
    if (!uvm_config_db#(virtual dotprod_if)::get(this,"","vif",vif))
      `uvm_fatal("ENV","no vif")
  endfunction
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    in_agent.mon.ap_in.connect(scb.ap_in);
    in_agent.mon.ap_in.connect(cov.analysis_export);
    out_agent.mon.ap_out.connect(scb.ap_out);
  endfunction

  // Deterministic end-of-test drain: wait (bounded) until every accepted input
  // beat has produced a checked output, i.e. the scoreboard's expected queue is
  // empty. Avoids the fragile fixed-#delay that left in-flight beats unchecked.
  task drain(uvm_component ctxt);
    int guard = 0;
    while (scb.exp_q.size() != 0 && guard < 10000) begin
      @(posedge vif.clk);
      guard++;
    end
    // a few extra cycles so the last output beat is fully sampled
    repeat (4) @(posedge vif.clk);
    if (scb.exp_q.size() != 0)
      `uvm_error("ENV", $sformatf("drain timeout: %0d beats still pending", scb.exp_q.size()))
  endtask
endclass
`endif
