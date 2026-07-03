`timescale 1ns/1ps
import dotprod_pkg::*;
// Directed self-checking test of the unified top in NVFP4 mode. Expected values
// come from the golden dotprod_ref_nvfp4 (single source of truth); a few
// landmark FP32 constants are also pinned as independent anchors.
module dotprod_nvfp4_directed_tb;
  logic [BF16_W-1:0]  a [N_LANES], b [N_LANES];
  logic [FP32_W-1:0]  result;
  dotprod_status_t    status;
  logic               sat;
  logic [FP32_W-1:0]  exp_result;
  logic               exp_inv, exp_nan, exp_inf;
  int errors = 0;
  int cases  = 0;

  dotprod_top dut (.mode(FMT_NVFP4), .a(a), .b(b),
                   .result(result), .status(status), .sat(sat));

  task automatic clear_inputs();
    foreach (a[i]) begin a[i]='0; b[i]='0; end
  endtask

  // Pack element k (0..15) into the correct lane/nibble position of v[].
  // Element k goes into v[k/4][4*(k%4) +: 4]; scale into v[4][7:0].
  task automatic pack_elem(ref logic [15:0] v [N_LANES],
                            input int k, input logic [3:0] val);
    v[k/4][4*(k%4) +: 4] = val;
  endtask

  task automatic pack_scale(ref logic [15:0] v [N_LANES],
                             input logic [7:0] scale);
    v[4][7:0] = scale;
  endtask

  // Check RTL against the golden, and optionally against a pinned anchor.
  task automatic check(
      input string             name,
      input logic              pin,
      input logic [FP32_W-1:0] anchor);
    cases++;
    #1;
    exp_result = dotprod_ref_nvfp4(a, b, exp_inv, exp_nan, exp_inf);
    if (result !== exp_result ||
        status.invalid !== exp_inv || status.is_nan !== exp_nan ||
        status.is_inf  !== exp_inf || status.sat !== 1'b0 ||
        (pin && result !== anchor)) begin
      errors++;
      $error("%s: result=0x%08h status{inv=%0b nan=%0b inf=%0b} exp=0x%08h{inv=%0b nan=%0b inf=%0b} anchor(pin=%0b)=0x%08h",
             name, result, status.invalid, status.is_nan, status.is_inf,
             exp_result, exp_inv, exp_nan, exp_inf, pin, anchor);
    end
  endtask

  initial begin
    // Case 1: all-ones block -- element 0x2 (+1.0) x16, scale 0x38 (1.0 each)
    // inner_sum = 16*4 = 64, scale_sig = 8*8=64, scale_exp = -6,
    // M = 4096, e2 = -8, value = 16.0 = 0x41800000
    clear_inputs();
    for (int k = 0; k < NVFP4_BLOCK; k++) begin
      pack_elem(a, k, 4'h2);  // +1.0 in E2M1 (sign=0, ee=01, m=0 -> mag=2 = 1.0 in 0.5u)
      pack_elem(b, k, 4'h2);
    end
    pack_scale(a, 8'h38);  // exp=7,mant=0 -> sig=8, k=-3
    pack_scale(b, 8'h38);
    check("all-ones 16.0", 1'b1, 32'h4180_0000);

    // Case 2: NaN scale on a (0x7F) -> QNaN 0x7FC00000, invalid + is_nan
    clear_inputs();
    for (int k = 0; k < NVFP4_BLOCK; k++) begin
      pack_elem(a, k, 4'h2);
      pack_elem(b, k, 4'h2);
    end
    pack_scale(a, 8'h7F);  // UE4M3_NAN
    pack_scale(b, 8'h38);
    check("nan scale a", 1'b1, FP32_QNAN);

    // Case 3: zero scale (0x00) -> 0x00000000
    clear_inputs();
    for (int k = 0; k < NVFP4_BLOCK; k++) begin
      pack_elem(a, k, 4'h2);
      pack_elem(b, k, 4'h2);
    end
    pack_scale(a, 8'h00);  // zero scale
    pack_scale(b, 8'h38);
    check("zero scale", 1'b1, 32'h0000_0000);

    // Case 4: mixed sign -- half positive (+1.0), half negative (-1.0) -> sum=0
    // E2M1 -1.0 = sign=1, ee=01, m=0 -> 4'ha
    clear_inputs();
    for (int k = 0; k < 8; k++) begin
      pack_elem(a, k, 4'h2);  // +1.0
      pack_elem(b, k, 4'h2);
    end
    for (int k = 8; k < NVFP4_BLOCK; k++) begin
      pack_elem(a, k, 4'ha);  // -1.0 (sign=1,ee=01,m=0)
      pack_elem(b, k, 4'h2);
    end
    pack_scale(a, 8'h38);
    pack_scale(b, 8'h38);
    check("mixed sign zero", 1'b0, 32'h0);

    // Case 5: max elements (0x7 = +6.0 in E2M1) with max-ish scale
    // E2M1 0x7: sign=0, ee=11, m=1 -> mag=12 (6.0 in 0.5u)
    // scale 0x78: exp=15, mant=0 -> sig=8, k=15-10=5. Both -> scale_sig=64, scale_exp=10
    // inner_sum = 16 * 144 = 2304 (12*12 per lane, 0.25 units)
    // M = 2304 * 64 = 147456, e2 = 10-2=8, value = 147456 * 2^8 = 37748736 = 0x4900_0000 (2^25*1.125)
    // Actually: 147456 = 0x24000, msb=17, exp_biased = 17+8+127=152=0x98, frac = 0x24000 << 6 = 0x900000
    // FP32 = {0, 8'h98, 23'h100000} = 0x4C10_0000  -- let golden verify
    clear_inputs();
    for (int k = 0; k < NVFP4_BLOCK; k++) begin
      pack_elem(a, k, 4'h7);  // +6.0
      pack_elem(b, k, 4'h7);
    end
    pack_scale(a, 8'h78);
    pack_scale(b, 8'h78);
    check("max scale case", 1'b0, 32'h0);

    if (errors) $fatal(1, "DOTPROD_NVFP4_DIRECTED FAIL: %0d errors", errors);
    $display("DOTPROD_NVFP4_DIRECTED PASS (%0d cases)", cases);
    $finish;
  end
endmodule
