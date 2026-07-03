`ifndef DOTPROD_SEQUENCES_SV
`define DOTPROD_SEQUENCES_SV
// INT8 random stream (default mode via seq_item soft constraint).
class dotprod_base_seq extends uvm_sequence#(dotprod_seq_item);
  `uvm_object_utils(dotprod_base_seq)
  rand int unsigned n_items = 500;
  constraint c_n_items { soft n_items == 500; }
  function new(string name = "dotprod_base_seq"); super.new(name); endfunction
  task body();
    repeat (n_items) begin
      dotprod_seq_item req = dotprod_seq_item::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { mode == FMT_INT8; })
        `uvm_error("SEQ", "randomize failed")
      finish_item(req);
    end
  endtask
endclass

// INT8 directed corners.
class dotprod_corner_seq extends uvm_sequence#(dotprod_seq_item);
  `uvm_object_utils(dotprod_corner_seq)
  function new(string name = "dotprod_corner_seq"); super.new(name); endfunction
  task body();
    bit signed [INT8_W-1:0] corners [9][2]; // {a_fill, b_fill}
    corners = '{ '{8'sd0,   8'sd0},
                 '{8'sd127, 8'sd127},
                 '{-8'sd128,8'sd127},
                 '{-8'sd128,-8'sd128},
                 '{ 8'sd127,  -8'sd128},   // <maxp,maxn>
                 '{ 8'sd0,    -8'sd128},   // <zero,maxn>
                 '{ 8'sd0,     8'sd127},   // <zero,maxp>
                 '{-8'sd128,   8'sd0},     // <maxn,zero>
                 '{ 8'sd127,   8'sd0} };   // <maxp,zero>
    foreach (corners[k]) begin
      dotprod_seq_item req = dotprod_seq_item::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { mode == FMT_INT8;
                                  foreach (a[i]) a[i][INT8_W-1:0] == corners[k][0];
                                  foreach (b[i]) b[i][INT8_W-1:0] == corners[k][1]; })
        `uvm_error("SEQ", "corner randomize failed")
      finish_item(req);
    end
  endtask
endclass

// BF16 constrained-random stream. Each operand is drawn from a curated pool of
// interesting 16-bit patterns (in-window finite, zero, subnormal/FTZ, +/-Inf,
// NaN) so the stimulus actually hits the special ladder and the exponent
// window; a flat 16-bit random almost never would.
class dotprod_bf16_seq extends uvm_sequence#(dotprod_seq_item);
  `uvm_object_utils(dotprod_bf16_seq)
  rand int unsigned n_items = 500;
  constraint c_n_items { soft n_items == 500; }
  function new(string name = "dotprod_bf16_seq"); super.new(name); endfunction

  // Interesting BF16 patterns (exp in [119,134] window, plus specials). The
  // class selector and the in-window exponent/mantissa are drawn from
  // INDEPENDENT random words (sel vs r), so all 16 window exponents [119,134]
  // are reachable -- a single word would correlate the selector bits with the
  // exponent offset and starve most of the window.
  local function automatic logic [BF16_W-1:0] pick(int unsigned sel, int unsigned r);
    logic [7:0] exp;
    case (sel % 8)
      0: pick = 16'h0000;                       // +0
      1: pick = 16'h0001;                        // subnormal -> FTZ
      2: pick = 16'h7F80;                        // +Inf
      3: pick = 16'hFF80;                        // -Inf
      4: pick = 16'h7FC1;                        // NaN
      default: begin                              // in-window finite
        exp  = 8'(BF16_EXP_LO + (r % (BF16_EXP_HI - BF16_EXP_LO + 1)));
        pick = {r[16], exp, r[6:0]};             // sign, exp, 7-bit mantissa
      end
    endcase
  endfunction

  task body();
    repeat (n_items) begin
      dotprod_seq_item req = dotprod_seq_item::type_id::create("req");
      logic [BF16_W-1:0] av [N_LANES], bv [N_LANES];
      foreach (av[i]) begin
        av[i] = pick($urandom(), $urandom());
        bv[i] = pick($urandom(), $urandom());
      end
      start_item(req);
      if (!req.randomize() with {
            mode == FMT_BF16; force_int8 == 0;
            foreach (a[i]) a[i] == av[i];
            foreach (b[i]) b[i] == bv[i]; })
        `uvm_error("SEQ", "bf16 randomize failed")
      finish_item(req);
    end
  endtask
endclass

// BF16 directed corners: the special ladder and rounding landmarks.
class dotprod_bf16_corner_seq extends uvm_sequence#(dotprod_seq_item);
  `uvm_object_utils(dotprod_bf16_corner_seq)
  function new(string name = "dotprod_bf16_corner_seq"); super.new(name); endfunction

  // Drive one directed BF16 vector (lane fills chosen by the caller).
  local task automatic drive_vec(logic [BF16_W-1:0] av [N_LANES],
                                 logic [BF16_W-1:0] bv [N_LANES]);
    dotprod_seq_item req = dotprod_seq_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with {
          mode == FMT_BF16; force_int8 == 0;
          foreach (a[i]) a[i] == av[i];
          foreach (b[i]) b[i] == bv[i]; })
      `uvm_error("SEQ", "bf16 corner randomize failed")
    finish_item(req);
  endtask

  task body();
    logic [BF16_W-1:0] av [N_LANES], bv [N_LANES];

    // all +1 * +1 -> +8.0
    foreach (av[i]) begin av[i]=16'h3F80; bv[i]=16'h3F80; end
    drive_vec(av, bv);

    // exact cancellation -> +0
    foreach (av[i]) begin av[i]=16'h0000; bv[i]=16'h0000; end
    av[0]=16'h3F80; bv[0]=16'h3F80; av[1]=16'hBF80; bv[1]=16'h3F80;
    drive_vec(av, bv);

    // NaN operand -> QNaN invalid
    foreach (av[i]) begin av[i]=16'h3F80; bv[i]=16'h3F80; end
    av[2]=16'h7FC1;
    drive_vec(av, bv);

    // +Inf only -> +Inf
    foreach (av[i]) begin av[i]=16'h0000; bv[i]=16'h0000; end
    av[0]=16'h7F80; bv[0]=16'h3F80;
    drive_vec(av, bv);

    // -Inf only -> -Inf (closes the RES_NEG_INF result class)
    foreach (av[i]) begin av[i]=16'h0000; bv[i]=16'h0000; end
    av[0]=16'hFF80; bv[0]=16'h3F80;   // -Inf * +1.0 -> -Inf
    drive_vec(av, bv);

    // Inf minus Inf -> QNaN invalid
    foreach (av[i]) begin av[i]=16'h0000; bv[i]=16'h0000; end
    av[0]=16'h7F80; bv[0]=16'h3F80; av[1]=16'hFF80; bv[1]=16'h3F80;
    drive_vec(av, bv);

    // 0 * Inf -> QNaN invalid
    foreach (av[i]) begin av[i]=16'h0000; bv[i]=16'h0000; end
    av[0]=16'h0000; bv[0]=16'h7F80;
    drive_vec(av, bv);

    // FTZ subnormal + a real 1.0 -> +1.0
    foreach (av[i]) begin av[i]=16'h0000; bv[i]=16'h0000; end
    av[0]=16'h0001; bv[0]=16'h3F80; av[1]=16'h3F80; bv[1]=16'h3F80;
    drive_vec(av, bv);

    // max in-window: all +max * +max (exp 134 = 8'h86, full 7-bit mantissa).
    // 0x437F = sign 0, exp 8'b1000_0110 (134), mant 7'h7F.
    foreach (av[i]) begin av[i]=16'h437F; bv[i]=16'h437F; end
    drive_vec(av, bv);

    // out-of-range operands (exp 143 = 256.0, above the [119,134] window) on
    // BOTH sides -> whole block resolves to invalid QNaN via the OOR guard.
    // Driving both operands out-of-window closes the OP_OTHER operand-class bin
    // on cp_ca AND cp_cb. Exercises the new out-of-window detection.
    foreach (av[i]) begin av[i]=16'h0000; bv[i]=16'h0000; end
    av[0]=16'h4780; bv[0]=16'h4780;   // 256.0 * 256.0 -> OOR -> QNaN
    drive_vec(av, bv);
  endtask
endclass

// NVFP4 constrained-random stream. Each operand block is built from a curated
// pool of E2M1 value classes (zero, subnormal 0.5, small 1-2, large 3-6,
// negative) and UE4M3 scale classes (zero, subnormal, normal, max, NaN).
// The nibbles + scale are packed via dotprod_seq_item::pack_nvfp4 and then
// pinned via inline constraints - mirroring the BF16 sequence pattern.
class dotprod_nvfp4_seq extends uvm_sequence#(dotprod_seq_item);
  `uvm_object_utils(dotprod_nvfp4_seq)
  rand int unsigned n_items = 500;
  constraint c_n_items { soft n_items == 500; }
  function new(string name = "dotprod_nvfp4_seq"); super.new(name); endfunction

  // Return an E2M1 nibble from a small curated pool covering value classes.
  // E2M1 encoding: bits[3]=sign, bits[2:1]=EE, bits[0]=M.
  // Values: 0x0=+0, 0x1=+0.5, 0x2=+1, 0x3=+1.5, 0x4=+2, 0x5=+3, 0x6=+4,
  //         0x7=+6, 0x8=-0, 0x9=-0.5, 0xA=-1, 0xB=-1.5, 0xC=-2, 0xD=-3.
  local function automatic logic [3:0] pick_e2m1(int unsigned r);
    case (r % 12)
      0:       pick_e2m1 = 4'h0;         // zero
      1:       pick_e2m1 = 4'h1;         // subnormal +0.5
      2:       pick_e2m1 = 4'h2;         // small +1.0
      3:       pick_e2m1 = 4'h3;         // small +1.5
      4:       pick_e2m1 = 4'h4;         // large +2.0
      5:       pick_e2m1 = 4'h5;         // large +3.0
      6:       pick_e2m1 = 4'h6;         // large +4.0
      7:       pick_e2m1 = 4'h7;         // large +6.0
      8:       pick_e2m1 = 4'h9;         // negative subnormal -0.5
      9:       pick_e2m1 = 4'hA;         // negative -1.0
      10:      pick_e2m1 = 4'hB;         // negative -1.5
      default: pick_e2m1 = 4'hD;         // negative -3.0
    endcase
  endfunction

  // Return a UE4M3 scale byte from a curated pool covering scale classes.
  // UE4M3: bits[6:3]=exp(4b), bits[2:0]=mant(3b), 0x00=zero, 0x7F=NaN.
  local function automatic logic [7:0] pick_ue4m3(int unsigned r);
    case (r % 6)
      0:       pick_ue4m3 = 8'h00;        // zero scale
      1:       pick_ue4m3 = 8'h01;        // subnormal (exp=0, mant=1)
      2:       pick_ue4m3 = 8'h38;        // normal mid: exp=7, mant=0 -> value=1.0
      3:       pick_ue4m3 = 8'h40;        // normal: exp=8, mant=0 -> value=2.0
      4:       pick_ue4m3 = 8'h7E;        // max normal (0x7E)
      default: pick_ue4m3 = 8'h7F;        // NaN
    endcase
  endfunction

  task body();
    repeat (n_items) begin
      dotprod_seq_item req = dotprod_seq_item::type_id::create("req");
      logic [3:0] ea [NVFP4_BLOCK], eb [NVFP4_BLOCK];
      logic [7:0] sa, sb;
      logic [BF16_W-1:0] av [N_LANES], bv [N_LANES];
      foreach (ea[i]) begin
        ea[i] = pick_e2m1($urandom());
        eb[i] = pick_e2m1($urandom());
      end
      sa = pick_ue4m3($urandom());
      sb = pick_ue4m3($urandom());
      dotprod_seq_item::pack_nvfp4(ea, sa, av);
      dotprod_seq_item::pack_nvfp4(eb, sb, bv);
      start_item(req);
      if (!req.randomize() with {
            mode == FMT_NVFP4; force_int8 == 0;
            foreach (a[i]) a[i] == av[i];
            foreach (b[i]) b[i] == bv[i]; })
        `uvm_error("SEQ", "nvfp4 randomize failed")
      finish_item(req);
    end
  endtask
endclass

// NVFP4 directed corners: all-zero block, single outlier, max scale, min
// normal scale, mixed sign, NaN scale.
class dotprod_nvfp4_corner_seq extends uvm_sequence#(dotprod_seq_item);
  `uvm_object_utils(dotprod_nvfp4_corner_seq)
  function new(string name = "dotprod_nvfp4_corner_seq"); super.new(name); endfunction

  local task automatic drive_packed(logic [BF16_W-1:0] av [N_LANES],
                                    logic [BF16_W-1:0] bv [N_LANES]);
    dotprod_seq_item req = dotprod_seq_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with {
          mode == FMT_NVFP4; force_int8 == 0;
          foreach (a[i]) a[i] == av[i];
          foreach (b[i]) b[i] == bv[i]; })
      `uvm_error("SEQ", "nvfp4 corner randomize failed")
    finish_item(req);
  endtask

  task body();
    logic [3:0] ea [NVFP4_BLOCK], eb [NVFP4_BLOCK];
    logic [BF16_W-1:0] av [N_LANES], bv [N_LANES];

    // Corner 1: all-zero block, normal scale -> result = 0
    foreach (ea[i]) begin ea[i] = 4'h0; eb[i] = 4'h0; end
    dotprod_seq_item::pack_nvfp4(ea, 8'h38, av);
    dotprod_seq_item::pack_nvfp4(eb, 8'h38, bv);
    drive_packed(av, bv);

    // Corner 2: single outlier (+6.0) at element 0, rest zero, normal scale
    foreach (ea[i]) begin ea[i] = 4'h0; eb[i] = 4'h0; end
    ea[0] = 4'h7; eb[0] = 4'h7;  // +6.0 * +6.0 = +36.0
    dotprod_seq_item::pack_nvfp4(ea, 8'h38, av);
    dotprod_seq_item::pack_nvfp4(eb, 8'h38, bv);
    drive_packed(av, bv);

    // Corner 3: max scale 0x7E on both operands
    foreach (ea[i]) begin ea[i] = 4'h2; eb[i] = 4'h2; end  // all +1.0
    dotprod_seq_item::pack_nvfp4(ea, 8'h7E, av);
    dotprod_seq_item::pack_nvfp4(eb, 8'h7E, bv);
    drive_packed(av, bv);

    // Corner 4: min normal scale (exp=1, mant=0 -> 0x08)
    foreach (ea[i]) begin ea[i] = 4'h6; eb[i] = 4'h6; end  // all +4.0
    dotprod_seq_item::pack_nvfp4(ea, 8'h08, av);
    dotprod_seq_item::pack_nvfp4(eb, 8'h08, bv);
    drive_packed(av, bv);

    // Corner 5: mixed sign - alternating +/- elements
    for (int i = 0; i < NVFP4_BLOCK; i++) begin
      ea[i] = (i % 2 == 0) ? 4'h2 : 4'hA;  // +1.0 / -1.0
      eb[i] = 4'h2;                           // all +1.0
    end
    dotprod_seq_item::pack_nvfp4(ea, 8'h38, av);
    dotprod_seq_item::pack_nvfp4(eb, 8'h38, bv);
    drive_packed(av, bv);

    // Corner 6: NaN scale on operand A -> invalid/NaN result
    foreach (ea[i]) begin ea[i] = 4'h2; eb[i] = 4'h2; end
    dotprod_seq_item::pack_nvfp4(ea, 8'h7F, av);  // NaN scale
    dotprod_seq_item::pack_nvfp4(eb, 8'h38, bv);
    drive_packed(av, bv);

    // Corner 7: zero scale (A scale = 0x00) -> result = 0
    foreach (ea[i]) begin ea[i] = 4'h7; eb[i] = 4'h7; end  // all +6.0
    dotprod_seq_item::pack_nvfp4(ea, 8'h00, av);
    dotprod_seq_item::pack_nvfp4(eb, 8'h38, bv);
    drive_packed(av, bv);

    // Corner 8: subnormal scale (exp=0, mant=1 -> 0x01)
    foreach (ea[i]) begin ea[i] = 4'h2; eb[i] = 4'h2; end
    dotprod_seq_item::pack_nvfp4(ea, 8'h01, av);
    dotprod_seq_item::pack_nvfp4(eb, 8'h38, bv);
    drive_packed(av, bv);
  endtask
endclass
`endif
