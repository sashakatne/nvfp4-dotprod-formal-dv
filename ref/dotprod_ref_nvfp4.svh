`ifndef DOTPROD_REF_NVFP4_SVH
`define DOTPROD_REF_NVFP4_SVH

// E2M1 -> signed integer in units of 0.5. mag table: {0,1,2,3,4,6,8,12} for
// EE M = 00_0,00_1,01_0,01_1,10_0,10_1,11_0,11_1.
function automatic e2m1_decoded_t ref_decode_e2m1(input logic [3:0] x);
  e2m1_decoded_t d;
  logic [1:0] ee; logic m;
  ee = x[2:1]; m = x[0];
  d.sign = x[3];
  case ({ee, m})
    3'b000: d.mag_int = 4'd0;   // 0.0
    3'b001: d.mag_int = 4'd1;   // 0.5
    3'b010: d.mag_int = 4'd2;   // 1.0
    3'b011: d.mag_int = 4'd3;   // 1.5
    3'b100: d.mag_int = 4'd4;   // 2.0
    3'b101: d.mag_int = 4'd6;   // 3.0
    3'b110: d.mag_int = 4'd8;   // 4.0
    3'b111: d.mag_int = 4'd12;  // 6.0
  endcase
  ref_decode_e2m1 = d;
endfunction

// product in units of 0.25 (mag_int units are 0.5, so mag_a*mag_b is units 0.25).
function automatic nvfp4_product_t ref_mul_nvfp4(input logic [3:0] a, input logic [3:0] b);
  e2m1_decoded_t da, db; nvfp4_product_t r;
  logic signed [8:0] mag;
  da = ref_decode_e2m1(a); db = ref_decode_e2m1(b);
  mag = 9'(da.mag_int) * 9'(db.mag_int);
  r.prod = (da.sign ^ db.sign) ? -mag : mag;
  ref_mul_nvfp4 = r;
endfunction

typedef struct packed {
  logic [3:0]        sig;   // integer significand (0..15)
  logic signed [6:0] k;     // value = sig * 2^k
  logic              is_nan;
  logic              is_zero;
} ue4m3_dec_t;

// UE4M3 (unsigned, bias 7, 3 mant, only NaN 0x7F). value = sig * 2^k where
// sig={1,mant} normal / {0,mant} subnormal, k = exp-10 normal / -9 subnormal.
function automatic ue4m3_dec_t ref_decode_ue4m3(input logic [7:0] x);
  ue4m3_dec_t d;
  logic [3:0] exp; logic [2:0] mant;
  exp = x[6:3]; mant = x[2:0];
  d = '0;
  if (x == UE4M3_NAN) begin
    d.is_nan = 1'b1;
  end else if (exp == 4'd0) begin
    if (mant == 3'd0) begin d.is_zero = 1'b1; d.sig = 4'd0; d.k = '0; end
    else begin d.sig = {1'b0, mant}; d.k = -7'sd9; end
  end else begin
    d.sig = {1'b1, mant}; d.k = 7'(int'(exp) - 10);
  end
  ref_decode_ue4m3 = d;
endfunction

function automatic nvfp4_preround_t dotprod_ref_nvfp4_preround(
    input logic [15:0] a [N_LANES], input logic [15:0] b [N_LANES]);
  nvfp4_preround_t r;
  logic [3:0] ea [NVFP4_BLOCK], eb [NVFP4_BLOCK];
  logic [7:0] sa, sb;
  ue4m3_dec_t da, db;
  nvfp4_product_t p;
  logic signed [NVFP4_INNER_W-1:0] acc;
  r = '0; acc = '0;
  ref_unpack_nvfp4(a, ea, sa);
  ref_unpack_nvfp4(b, eb, sb);
  for (int i = 0; i < NVFP4_BLOCK; i++) begin
    p = ref_mul_nvfp4(ea[i], eb[i]);
    acc = acc + NVFP4_INNER_W'(p.prod);
  end
  r.inner_sum = acc;
  da = ref_decode_ue4m3(sa); db = ref_decode_ue4m3(sb);
  r.scale_is_nan = da.is_nan || db.is_nan;
  r.scale_sig    = 8'(da.sig) * 8'(db.sig);
  r.scale_exp    = da.k + db.k;
  dotprod_ref_nvfp4_preround = r;
endfunction

// Pure FP32 encode of the pre-round fields. Extracted verbatim from the inline
// block in dotprod_ref_nvfp4 so the standalone final_round_nvfp4 FPV proof can
// assert the module against a callable golden (mirrors ref_round_bf16_acc_to_fp32).
// value = inner_sum(units .25) * scale_sig * 2^(scale_exp-2); |M| < 2^24 so exact.
function automatic logic [31:0] dotprod_ref_nvfp4_round(
    input logic signed [NVFP4_INNER_W-1:0] inner_sum,
    input logic [7:0]                       scale_sig,
    input logic signed [6:0]                scale_exp,
    input logic                             scale_is_nan,
    output logic invalid, output logic is_nan);
  logic signed [31:0] M;
  logic signed [7:0]  e2;
  logic sign; logic [31:0] mag;
  int msb; int exp_biased; logic [23:0] frac;
  invalid = 1'b0; is_nan = 1'b0;
  if (scale_is_nan) begin
    invalid = 1'b1; is_nan = 1'b1;
    dotprod_ref_nvfp4_round = FP32_QNAN;
  end else begin
    M  = 32'(signed'(inner_sum)) * 32'(signed'({1'b0, scale_sig}));
    e2 = scale_exp - 7'sd2;
    if (M == 0) begin
      dotprod_ref_nvfp4_round = 32'h0000_0000;
    end else begin
      sign = M[31];
      mag  = sign ? (~M + 32'd1) : M;
      msb = 0;
      for (int i = 0; i < 32; i++) if (mag[i]) msb = i;
      exp_biased = msb + int'(e2) + 127;
      if (msb <= 23) frac = mag << (23 - msb);
      else           frac = mag >> (msb - 23);
      dotprod_ref_nvfp4_round = {sign, exp_biased[7:0], frac[22:0]};
    end
  end
endfunction

function automatic logic [31:0] dotprod_ref_nvfp4(
    input logic [15:0] a [N_LANES], input logic [15:0] b [N_LANES],
    output logic invalid, output logic is_nan, output logic is_inf);
  nvfp4_preround_t pr;
  is_inf = 1'b0;
  pr = dotprod_ref_nvfp4_preround(a, b);
  dotprod_ref_nvfp4 = dotprod_ref_nvfp4_round(
      pr.inner_sum, pr.scale_sig, pr.scale_exp, pr.scale_is_nan, invalid, is_nan);
endfunction
`endif
