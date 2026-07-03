`timescale 1ns/1ps
import dotprod_pkg::*;

module dotprod_nvfp4_ref_tb;
  logic [15:0] a [N_LANES], b [N_LANES];
  logic [31:0] result;
  logic invalid, is_nan, is_inf;
  e2m1_decoded_t decoded_e;
  nvfp4_product_t prod;
  ue4m3_dec_t decoded_s;
  int errors = 0;
  int cases = 0;

  // Build a packed 16-element NVFP4 word vector from element array + scale.
  // Packing: element k -> v[k/4][4*(k%4) +: 4], scale -> v[4][7:0].
  task automatic pack_nvfp4(
      input logic [3:0] elems [NVFP4_BLOCK],
      input logic [7:0] scale,
      output logic [15:0] v [N_LANES]);
    foreach (v[i]) v[i] = '0;
    for (int k = 0; k < NVFP4_BLOCK; k++)
      v[k/4][4*(k%4) +: 4] = elems[k];
    v[4][7:0] = scale;
  endtask

  task automatic check_dot(
      input string name,
      input logic [31:0] exp_result,
      input logic exp_invalid,
      input logic exp_is_nan,
      input logic exp_is_inf);
    cases++;
    result = dotprod_ref_nvfp4(a, b, invalid, is_nan, is_inf);
    if (result !== exp_result || invalid !== exp_invalid ||
        is_nan !== exp_is_nan || is_inf !== exp_is_inf) begin
      errors++;
      $error("%s: got result=0x%08h invalid=%0b is_nan=%0b is_inf=%0b exp=0x%08h/%0b/%0b/%0b",
             name, result, invalid, is_nan, is_inf,
             exp_result, exp_invalid, exp_is_nan, exp_is_inf);
    end
  endtask

  initial begin
    // --- element decode checks ---

    // 0x7 = 0111: sign=0, ee=11, m=1 -> mag_int=12, value 6.0
    cases++;
    decoded_e = ref_decode_e2m1(4'h7);
    if (decoded_e.sign !== 1'b0 || decoded_e.mag_int !== 4'd12) begin
      errors++;
      $error("ref_decode_e2m1(0x7): got sign=%0b mag_int=%0d exp sign=0 mag_int=12",
             decoded_e.sign, decoded_e.mag_int);
    end

    // 0xF = 1111: sign=1, ee=11, m=1 -> mag_int=12, value -6.0
    cases++;
    decoded_e = ref_decode_e2m1(4'hF);
    if (decoded_e.sign !== 1'b1 || decoded_e.mag_int !== 4'd12) begin
      errors++;
      $error("ref_decode_e2m1(0xF): got sign=%0b mag_int=%0d exp sign=1 mag_int=12",
             decoded_e.sign, decoded_e.mag_int);
    end

    // 0x8 = 1000: sign=1, ee=00, m=0 -> mag_int=0, value -0
    cases++;
    decoded_e = ref_decode_e2m1(4'h8);
    if (decoded_e.mag_int !== 4'd0) begin
      errors++;
      $error("ref_decode_e2m1(0x8): got mag_int=%0d exp mag_int=0",
             decoded_e.mag_int);
    end

    // 0x1 = 0001: sign=0, ee=00, m=1 -> mag_int=1, value 0.5
    cases++;
    decoded_e = ref_decode_e2m1(4'h1);
    if (decoded_e.sign !== 1'b0 || decoded_e.mag_int !== 4'd1) begin
      errors++;
      $error("ref_decode_e2m1(0x1): got sign=%0b mag_int=%0d exp sign=0 mag_int=1",
             decoded_e.sign, decoded_e.mag_int);
    end

    #1;

    // --- product checks ---

    // ref_mul_nvfp4(0x7, 0x7): +6.0*+6.0 = +144 units-0.25
    cases++;
    prod = ref_mul_nvfp4(4'h7, 4'h7);
    if (prod.prod !== 9'sd144) begin
      errors++;
      $error("ref_mul_nvfp4(0x7,0x7): got prod=%0d exp +144", prod.prod);
    end

    // ref_mul_nvfp4(0xF, 0x7): -6.0*+6.0 = -144 units-0.25
    cases++;
    prod = ref_mul_nvfp4(4'hF, 4'h7);
    if (prod.prod !== -9'sd144) begin
      errors++;
      $error("ref_mul_nvfp4(0xF,0x7): got prod=%0d exp -144", prod.prod);
    end

    #1;

    // --- UE4M3 scale decode checks ---

    // 0x38 = 0011_1000: exp=0111=7, mant=000; normal: sig=8, k=7-10=-3; value=1.0
    cases++;
    decoded_s = ref_decode_ue4m3(8'h38);
    if (decoded_s.sig !== 4'd8 || decoded_s.k !== -7'sd3 ||
        decoded_s.is_nan || decoded_s.is_zero) begin
      errors++;
      $error("ref_decode_ue4m3(0x38): got sig=%0d k=%0d is_nan=%0b is_zero=%0b exp sig=8 k=-3 nan=0 zero=0",
             decoded_s.sig, decoded_s.k, decoded_s.is_nan, decoded_s.is_zero);
    end

    // 0x7F: NaN
    cases++;
    decoded_s = ref_decode_ue4m3(8'h7F);
    if (!decoded_s.is_nan) begin
      errors++;
      $error("ref_decode_ue4m3(0x7F): expected is_nan=1, got %0b", decoded_s.is_nan);
    end

    // 0x00: zero
    cases++;
    decoded_s = ref_decode_ue4m3(8'h00);
    if (!decoded_s.is_zero) begin
      errors++;
      $error("ref_decode_ue4m3(0x00): expected is_zero=1, got %0b", decoded_s.is_zero);
    end

    #1;

    // --- dot-product checks ---

    // All-ones block: 16 elements = 0x2 (+1.0), scale A=B=0x38 (1.0).
    // inner_sum = 16*(2*2) = 64 units-0.25. scale_sig=8*8=64, scale_exp=-3-3=-6.
    // M=64*64=4096, e2=-6-2=-8. value=4096*2^-8=16.0 -> 0x41800000.
    begin
      logic [3:0] elems_a [NVFP4_BLOCK], elems_b [NVFP4_BLOCK];
      foreach (elems_a[i]) elems_a[i] = 4'h2;
      foreach (elems_b[i]) elems_b[i] = 4'h2;
      pack_nvfp4(elems_a, 8'h38, a);
      pack_nvfp4(elems_b, 8'h38, b);
    end
    #1;
    check_dot("all-ones block scale 1.0", 32'h4180_0000, 1'b0, 1'b0, 1'b0);

    // NaN scale: sA=0x7F -> QNaN, invalid=1, is_nan=1.
    begin
      logic [3:0] elems_a [NVFP4_BLOCK], elems_b [NVFP4_BLOCK];
      foreach (elems_a[i]) elems_a[i] = 4'h2;
      foreach (elems_b[i]) elems_b[i] = 4'h2;
      pack_nvfp4(elems_a, 8'h7F, a);
      pack_nvfp4(elems_b, 8'h38, b);
    end
    #1;
    check_dot("nan scale sA", FP32_QNAN, 1'b1, 1'b1, 1'b0);

    // Zero scale: sA=0x00 -> FP32 0x0.
    begin
      logic [3:0] elems_a [NVFP4_BLOCK], elems_b [NVFP4_BLOCK];
      foreach (elems_a[i]) elems_a[i] = 4'h7;
      foreach (elems_b[i]) elems_b[i] = 4'h7;
      pack_nvfp4(elems_a, 8'h00, a);
      pack_nvfp4(elems_b, 8'h38, b);
    end
    #1;
    check_dot("zero scale sA", 32'h0000_0000, 1'b0, 1'b0, 1'b0);

    // Mixed-sign cancellation: A=all +1.0 (0x2), B=alternating +1.0/−1.0 (0x2/0xA),
    // 8 positive and 8 negative products -> inner_sum=0 -> result 0x0.
    // 0xA = 1010: sign=1, ee=01, m=0 -> mag_int=2, value -1.0.
    begin
      logic [3:0] elems_a [NVFP4_BLOCK], elems_b [NVFP4_BLOCK];
      for (int i = 0; i < NVFP4_BLOCK; i++) begin
        elems_a[i] = 4'h2;
        elems_b[i] = (i % 2 == 0) ? 4'h2 : 4'hA;
      end
      pack_nvfp4(elems_a, 8'h38, a);
      pack_nvfp4(elems_b, 8'h38, b);
    end
    #1;
    check_dot("mixed-sign cancellation", 32'h0000_0000, 1'b0, 1'b0, 1'b0);

    if (errors) $fatal(1, "NVFP4_REF FAIL: %0d errors", errors);
    $display("NVFP4_REF PASS (%0d cases)", cases);
    $finish;
  end
endmodule
