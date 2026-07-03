`ifndef DOTPROD_SCOREBOARD_SV
`define DOTPROD_SCOREBOARD_SV

`uvm_analysis_imp_decl(_in)
`uvm_analysis_imp_decl(_out)

class dotprod_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(dotprod_scoreboard)

  uvm_analysis_imp_in #(dotprod_seq_item, dotprod_scoreboard) ap_in;
  uvm_analysis_imp_out#(dotprod_seq_item, dotprod_scoreboard) ap_out;

  typedef struct {
    logic [FP32_W-1:0] result;
    dotprod_status_t   status;
  } expected_t;
  expected_t exp_q[$];
  int matched, mismatched;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_in  = new("ap_in",  this);
    ap_out = new("ap_out", this);
  endfunction

  // Predict from the committed goldens; never duplicate DUT math here.
  function void write_in(dotprod_seq_item t);
    expected_t e;
    e.status = '0;
    if (t.mode == FMT_BF16) begin
      logic inv, nan, inf;
      e.result         = dotprod_ref_bf16(t.a, t.b, inv, nan, inf);
      e.status.sat     = 1'b0;
      e.status.invalid = inv;
      e.status.is_nan  = nan;
      e.status.is_inf  = inf;
    end else if (t.mode == FMT_NVFP4) begin
      logic inv, nan, inf;
      e.result         = dotprod_ref_nvfp4(t.a, t.b, inv, nan, inf);
      e.status.sat     = 1'b0;
      e.status.invalid = inv;
      e.status.is_nan  = nan;
      e.status.is_inf  = inf;
    end else begin
      logic esat = 1'b0;
      logic signed [INT8_W-1:0] aa [N_LANES], bb [N_LANES];
      logic signed [INT8_OUT_W-1:0] r;
      foreach (t.a[i]) begin aa[i] = t.a[i][INT8_W-1:0]; bb[i] = t.b[i][INT8_W-1:0]; end
      r               = dotprod_ref(aa, bb, esat);
      e.result        = FP32_W'(r);
      e.status.sat    = esat;
      e.status.invalid= 1'b0;
      e.status.is_nan = 1'b0;
      e.status.is_inf = 1'b0;
    end
    exp_q.push_back(e);
  endfunction

  function void write_out(dotprod_seq_item t);
    expected_t e;
    if (exp_q.size() == 0) begin
      mismatched++;
      `uvm_error("SCB", "output with no pending expected")
      return;
    end
    e = exp_q.pop_front();
    if (t.result === e.result && t.status === e.status && t.sat === e.status.sat) begin
      matched++;
      `uvm_info("SCB", $sformatf("PASS result=0x%08h status=%p", t.result, t.status), UVM_HIGH)
    end else begin
      mismatched++;
      `uvm_error("SCB", $sformatf("MISMATCH dut(result=0x%08h status=%p sat=%0b) exp(result=0x%08h status=%p)",
                 t.result, t.status, t.sat, e.result, e.status))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    int leftover;
    super.report_phase(phase);
    leftover = exp_q.size();
    if (leftover != 0)
      `uvm_error("SCB", $sformatf("%0d expected results never observed", leftover))
    `uvm_info("SCB", $sformatf("SCOREBOARD matched=%0d mismatched=%0d leftover=%0d",
              matched, mismatched, leftover), UVM_LOW)
  endfunction

endclass
`endif
