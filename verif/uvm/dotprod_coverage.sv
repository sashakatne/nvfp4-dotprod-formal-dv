`ifndef DOTPROD_COVERAGE_SV
`define DOTPROD_COVERAGE_SV
class dotprod_coverage extends uvm_subscriber#(dotprod_seq_item);
  `uvm_component_utils(dotprod_coverage)
  virtual dotprod_if vif;

  // INT8 value coverage on accepted input beats (low byte).
  bit signed [INT8_W-1:0] s_a, s_b;
  covergroup cg_value;
    cp_a: coverpoint s_a { bins zero={0}; bins maxp={127}; bins maxn={-128};
                           bins neg={[-127:-1]}; bins pos={[1:126]}; }
    cp_b: coverpoint s_b { bins zero={0}; bins maxp={127}; bins maxn={-128};
                           bins neg={[-127:-1]}; bins pos={[1:126]}; }
    x_ab: cross cp_a, cp_b;
  endgroup

  // BF16 operand-class coverage on accepted input beats.
  typedef enum { OP_ZERO, OP_SUBNORMAL, OP_SMALL, OP_LARGE, OP_MAXWIN,
                 OP_INF, OP_NAN, OP_OTHER } bf16_opclass_e;
  bf16_opclass_e s_ca, s_cb;
  covergroup cg_bf16_operand;
    cp_ca: coverpoint s_ca;
    cp_cb: coverpoint s_cb;
    // Operand-pair cross distinguishes the invalid-path pairings (NaN x zero vs
    // NaN x NaN vs Inf x Inf, etc.) that a marginal coverpoint collapses. The
    // OP_OTHER (out-of-window) class is a directed-only, single-sided stimulus
    // (one operand of the OOR corner); its correctness is covered by its marginal
    // bin plus the formal out-of-range lane proof, so cross pairings involving it
    // are ignored rather than left as unreachable holes.
    x_ca_cb: cross cp_ca, cp_cb {
      ignore_bins oor_pairs = binsof(cp_ca) intersect {OP_OTHER} ||
                              binsof(cp_cb) intersect {OP_OTHER};
    }
  endgroup

  // BF16 result-class coverage on observed output beats.
  typedef enum { RES_ZERO, RES_NORMAL, RES_NAN, RES_POS_INF, RES_NEG_INF } bf16_resclass_e;
  bf16_resclass_e s_res;
  covergroup cg_bf16_result;
    cp_res: coverpoint s_res;
  endgroup

  // INT8 result-class coverage on observed output beats. Saturation is
  // structurally unreachable for an 8-lane single-shot dot product (max sum
  // 8*128*128 = 131072 fits in the 32-bit output), so IR_SAT is an illegal bin.
  typedef enum { IR_ZERO, IR_POS, IR_NEG, IR_SAT } int8_resclass_e;
  int8_resclass_e s_ires;
  covergroup cg_int8_result;
    cp_ires: coverpoint s_ires { illegal_bins never_sat = {IR_SAT}; }
  endgroup

  // NVFP4 element value-class and scale-class coverage.
  typedef enum { NV_ZERO, NV_SUBNORM, NV_SMALL, NV_LARGE, NV_MAX, NV_NEG } nvfp4_valclass_e;
  typedef enum { NS_ZERO, NS_SUBNORM, NS_NORMAL, NS_MAX, NS_NAN   } nvfp4_scaleclass_e;
  nvfp4_valclass_e   s_nva, s_nvb;
  nvfp4_scaleclass_e s_nsa, s_nsb;
  bit                s_nv_all_zero_a, s_nv_sign_mix;
  covergroup cg_nvfp4_element;
    cp_ela:  coverpoint s_nva;
    cp_elb:  coverpoint s_nvb;
    x_el_ab: cross cp_ela, cp_elb;
  endgroup
  covergroup cg_nvfp4_scale;
    cp_scale:   coverpoint s_nsa;
    cp_scale_b: coverpoint s_nsb;
    // Scale-pair cross: NaN_A x Normal_B vs NaN_A x NaN_B drive the
    // scale_is_nan = na||nb logic differently. Both sides draw from the same
    // curated pool, so all 5x5 pairings are reachable.
    x_scale_ab: cross cp_scale, cp_scale_b;
  endgroup
  covergroup cg_nvfp4_block;
    cp_all_zero: coverpoint s_nv_all_zero_a { bins yes={1}; bins no={0}; }
    cp_sign_mix: coverpoint s_nv_sign_mix   { bins yes={1}; bins no={0}; }
  endgroup

  // NVFP4 result-class coverage on observed output beats. NR_INF is a dedicated
  // class: NVFP4 can never legitimately produce FP32 Inf, so a DUT that emits one
  // surfaces as its own bin instead of hiding inside NR_NORMAL.
  typedef enum { NR_ZERO, NR_NORMAL, NR_NAN, NR_INF } nvfp4_resclass_e;
  nvfp4_resclass_e s_nvres;
  covergroup cg_nvfp4_result;
    cp_nvres: coverpoint s_nvres { illegal_bins never_inf = {NR_INF}; }
  endgroup

  // Classify a 4-bit E2M1 nibble. Sign is bit[3]; mag encoded in bits[2:0].
  local function automatic nvfp4_valclass_e classify_e2m1(logic [3:0] x);
    logic [2:0] mag3 = x[2:0];
    if (mag3 == 3'b000) return NV_ZERO;    // +0 (0x0) and -0 (0x8): numerically zero
    if (x[3]) return NV_NEG;               // any nonzero negative
    if (mag3 == 3'b001) return NV_SUBNORM; // 0.5
    if (mag3 <= 3'b011) return NV_SMALL;   // 1.0, 1.5
    if (mag3 == 3'b111) return NV_MAX;     // +6.0 (max E2M1 magnitude)
    return NV_LARGE;                       // 2.0, 3.0, 4.0
  endfunction

  // Classify a UE4M3 scale byte.
  local function automatic nvfp4_scaleclass_e classify_ue4m3(logic [7:0] x);
    logic [3:0] exp  = x[6:3];
    logic [2:0] mant = x[2:0];
    if (x == 8'h7F)                  return NS_NAN;
    if (x == 8'h7E)                  return NS_MAX;
    if (exp == 4'd0 && mant == 3'd0) return NS_ZERO;
    if (exp == 4'd0)                 return NS_SUBNORM;
    return NS_NORMAL;
  endfunction

  // Classify an FP32 result bit-pattern for NVFP4. Inf (exp 0xFF, mant 0) gets
  // its own class so an illegal Inf output is visible rather than folded into
  // NR_NORMAL; the covergroup marks NR_INF as an illegal bin.
  local function automatic nvfp4_resclass_e classify_nvfp4_result(logic [FP32_W-1:0] r);
    logic [7:0] exp  = r[30:23];
    logic [22:0] mant = r[22:0];
    if (exp == 8'hFF && mant != 0)       return NR_NAN;
    if (exp == 8'hFF && mant == 0)       return NR_INF;
    if (exp == 8'h00 && mant == 0)       return NR_ZERO;
    return NR_NORMAL;
  endfunction

  // protocol coverage sampled every clock
  bit iv, ir, ov, orr;
  covergroup cg_proto;
    cp_in:  coverpoint {iv,ir} { bins accept={2'b11}; bins in_stall={2'b10};
                                 bins ready_idle={2'b01}; bins idle={2'b00}; }
    cp_out: coverpoint {ov,orr}{ bins drain={2'b11}; bins backpressure={2'b10};
                                 bins ready_no_out={2'b01}; bins no_out={2'b00}; }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name,parent);
    cg_value=new(); cg_bf16_operand=new(); cg_bf16_result=new(); cg_proto=new();
    cg_nvfp4_element=new(); cg_nvfp4_scale=new(); cg_nvfp4_block=new();
    cg_nvfp4_result=new(); cg_int8_result=new();
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual dotprod_if)::get(this,"","vif",vif))
      `uvm_fatal("COV","no vif")
  endfunction

  // Classify a raw BF16 operand into a coverage class.
  local function automatic bf16_opclass_e classify_operand(logic [BF16_W-1:0] x);
    logic [7:0] exp = x[14:7];
    logic [6:0] mant = x[6:0];
    if (exp == 8'h00 && mant == 7'h00)      return OP_ZERO;
    else if (exp == 8'h00)                  return OP_SUBNORMAL;
    else if (exp == 8'hFF && mant == 7'h00) return OP_INF;
    else if (exp == 8'hFF)                  return OP_NAN;
    else if (exp == BF16_EXP_HI[7:0])       return OP_MAXWIN;
    else if (exp >= BF16_EXP_LO[7:0] && exp < 8'(BF16_EXP_LO+8)) return OP_SMALL;
    else if (exp <= BF16_EXP_HI[7:0])       return OP_LARGE;
    else                                    return OP_OTHER;
  endfunction

  // Classify an FP32 result bit-pattern into a coverage class.
  local function automatic bf16_resclass_e classify_result(logic [FP32_W-1:0] r);
    logic [7:0] exp = r[30:23];
    logic [22:0] mant = r[22:0];
    if (exp == 8'hFF && mant != 0)       return RES_NAN;
    else if (exp == 8'hFF &&  r[31])     return RES_NEG_INF;
    else if (exp == 8'hFF && !r[31])     return RES_POS_INF;
    else if (exp == 8'h00 && mant == 0)  return RES_ZERO;
    else                                 return RES_NORMAL;
  endfunction

  // value + operand-class sampling from the input monitor stream
  function void write(dotprod_seq_item t);
    if (t.mode == FMT_INT8) begin
      foreach (t.a[i]) begin
        s_a=t.a[i][INT8_W-1:0]; s_b=t.b[i][INT8_W-1:0]; cg_value.sample();
      end
    end else if (t.mode == FMT_BF16) begin
      foreach (t.a[i]) begin
        s_ca=classify_operand(t.a[i]); s_cb=classify_operand(t.b[i]);
        cg_bf16_operand.sample();
      end
    end else if (t.mode == FMT_NVFP4) begin
      // unpack and sample element + scale + block-level covergroups
      begin
        logic [3:0] ea [NVFP4_BLOCK], eb [NVFP4_BLOCK];
        logic [7:0] sa, sb;
        bit has_pos_a, has_neg_a, all_zero_a;
        ref_unpack_nvfp4(t.a, ea, sa);
        ref_unpack_nvfp4(t.b, eb, sb);
        s_nsa = classify_ue4m3(sa);
        s_nsb = classify_ue4m3(sb);
        cg_nvfp4_scale.sample();
        all_zero_a = 1'b1; has_pos_a = 1'b0; has_neg_a = 1'b0;
        foreach (ea[k]) begin
          s_nva = classify_e2m1(ea[k]);
          s_nvb = classify_e2m1(eb[k]);
          cg_nvfp4_element.sample();
          if (ea[k] != 4'h0 && ea[k] != 4'h8) all_zero_a = 1'b0;
          if (ea[k][3] == 1'b0 && ea[k] != 4'h0) has_pos_a = 1'b1;
          // -0 (0x8) is numerically zero: exclude it from the negative-sign set
          // so a {+x, -0} block is not falsely reported as sign-mixed.
          if (ea[k][3] == 1'b1 && ea[k] != 4'h8) has_neg_a = 1'b1;
        end
        s_nv_all_zero_a = all_zero_a;
        s_nv_sign_mix   = has_pos_a & has_neg_a;
        cg_nvfp4_block.sample();
      end
    end
  endfunction

  // In-flight mode queue: the result-class of an output beat belongs to the
  // transaction that was ACCEPTED at the input (2-cycle pipeline latency), not to
  // whatever mode the input side happens to present now. Push mode on each
  // input-accept, pop on each output beat, and classify with the popped mode so
  // result-class coverage is attributed to the correct transaction (correct even
  // under interleaved-mode streams).
  fmt_e mode_q[$];

  // protocol + result-class sampling every clock
  task run_phase(uvm_phase phase);
    forever begin
      @(vif.mon_cb);
      iv=vif.mon_cb.in_valid; ir=vif.mon_cb.in_ready;
      ov=vif.mon_cb.out_valid; orr=vif.mon_cb.out_ready;
      cg_proto.sample();
      if (iv === 1'b1 && ir === 1'b1)
        mode_q.push_back(vif.mon_cb.mode);
      if (ov === 1'b1 && orr === 1'b1) begin
        fmt_e out_mode;
        out_mode = (mode_q.size() > 0) ? mode_q.pop_front() : vif.mon_cb.mode;
        if (out_mode == FMT_BF16) begin
          s_res = classify_result(vif.mon_cb.result);
          cg_bf16_result.sample();
        end else if (out_mode == FMT_NVFP4) begin
          s_nvres = classify_nvfp4_result(vif.mon_cb.result);
          cg_nvfp4_result.sample();
        end else begin
          // INT8: classify the signed 32-bit result (sat is unreachable).
          if ($signed(vif.mon_cb.result) == 0)     s_ires = IR_ZERO;
          else if ($signed(vif.mon_cb.result) > 0) s_ires = IR_POS;
          else                                     s_ires = IR_NEG;
          cg_int8_result.sample();
        end
      end
    end
  endtask
endclass
`endif
