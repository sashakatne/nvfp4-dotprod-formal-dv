`ifndef DOTPROD_TESTS_SV
`define DOTPROD_TESTS_SV
class dotprod_base_test extends uvm_test;
  `uvm_component_utils(dotprod_base_test)
  dotprod_env env;
  function new(string name, uvm_component parent=null); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = dotprod_env::type_id::create("env", this);
  endfunction
endclass

class dotprod_random_test extends dotprod_base_test;
  `uvm_component_utils(dotprod_random_test)
  function new(string name, uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    dotprod_base_seq seq;
    seq = dotprod_base_seq::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(env.in_agent.seqr);
    env.drain(this);        // wait until every driven beat has been checked
    phase.drop_objection(this);
  endtask
endclass

class dotprod_backpressure_test extends dotprod_base_test;
  `uvm_component_utils(dotprod_backpressure_test)
  function new(string name, uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    dotprod_base_seq seq;
    seq = dotprod_base_seq::type_id::create("seq");
    // out_driver already randomizes backpressure; just drive a long stream
    phase.raise_objection(this);
    seq.n_items = 1000;
    seq.start(env.in_agent.seqr);
    env.drain(this);
    phase.drop_objection(this);
  endtask
endclass

class dotprod_corner_test extends dotprod_base_test;
  `uvm_component_utils(dotprod_corner_test)
  function new(string name, uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    dotprod_corner_seq seq;
    seq = dotprod_corner_seq::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(env.in_agent.seqr);
    env.drain(this);
    phase.drop_objection(this);
  endtask
endclass

// BF16 constrained-random test: in-window finite / special mix.
class dotprod_bf16_test extends dotprod_base_test;
  `uvm_component_utils(dotprod_bf16_test)
  function new(string name, uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    dotprod_bf16_seq seq;
    seq = dotprod_bf16_seq::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(env.in_agent.seqr);
    env.drain(this);
    phase.drop_objection(this);
  endtask
endclass

// BF16 directed corner test: NaN, +/-Inf, Inf-minus-Inf, 0*Inf, FTZ,
// cancellation, max in-window.
class dotprod_bf16_corner_test extends dotprod_base_test;
  `uvm_component_utils(dotprod_bf16_corner_test)
  function new(string name, uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    dotprod_bf16_corner_seq seq;
    seq = dotprod_bf16_corner_seq::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(env.in_agent.seqr);
    env.drain(this);
    phase.drop_objection(this);
  endtask
endclass

// NVFP4 constrained-random test: E2M1 value classes + UE4M3 scale classes.
class dotprod_nvfp4_test extends dotprod_base_test;
  `uvm_component_utils(dotprod_nvfp4_test)
  function new(string name, uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    dotprod_nvfp4_seq seq;
    seq = dotprod_nvfp4_seq::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(env.in_agent.seqr);
    env.drain(this);
    phase.drop_objection(this);
  endtask
endclass

// NVFP4 directed corner test: all-zero block, single outlier, max scale,
// min normal scale, mixed sign, NaN scale, zero scale, subnormal scale.
class dotprod_nvfp4_corner_test extends dotprod_base_test;
  `uvm_component_utils(dotprod_nvfp4_corner_test)
  function new(string name, uvm_component parent=null); super.new(name,parent); endfunction
  task run_phase(uvm_phase phase);
    dotprod_nvfp4_corner_seq seq;
    seq = dotprod_nvfp4_corner_seq::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(env.in_agent.seqr);
    env.drain(this);
    phase.drop_objection(this);
  endtask
endclass
`endif
