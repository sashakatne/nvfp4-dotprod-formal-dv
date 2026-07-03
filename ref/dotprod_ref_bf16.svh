`ifndef DOTPROD_REF_BF16_SVH
`define DOTPROD_REF_BF16_SVH

function automatic bf16_decoded_t ref_decode_bf16(input logic [BF16_W-1:0] x);
  bf16_decoded_t d;
  logic [7:0] exp;
  logic [6:0] mant;

  exp = x[14:7];
  mant = x[6:0];
  d = '0;
  d.sign = x[15];

  if (exp == 8'h00) begin
    d.is_zero = 1'b1; // FTZ: subnormals decode as signed zero.
  end else if (exp == 8'hFF) begin
    if (mant == 7'h00) d.is_inf = 1'b1;
    else               d.is_nan = 1'b1;
  end else begin
    d.sig = {1'b1, mant};
    d.q = 10'(int'(exp) - 134);
    // Out-of-range: normal operand with exponent outside the M3 window
    // [119,134]. Mirrors the RTL front_end_bf16 guard so RTL == golden over the
    // full BF16 input space; the lane multiply folds is_oor into an
    // invalid-operation NaN.
    d.is_oor = (exp < BF16_EXP_LO[7:0]) || (exp > BF16_EXP_HI[7:0]);
  end

  ref_decode_bf16 = d;
endfunction

function automatic bf16_product_t ref_mul_bf16(
    input logic [BF16_W-1:0] a,
    input logic [BF16_W-1:0] b);
  bf16_decoded_t da;
  bf16_decoded_t db;
  bf16_product_t r;

  da = ref_decode_bf16(a);
  db = ref_decode_bf16(b);
  r = '0;
  r.p_sign = da.sign ^ db.sign;

  if (da.is_nan || db.is_nan || da.is_oor || db.is_oor) begin
    // NaN operand or out-of-range (out-of-window normal) operand: invalid op.
    r.is_nan = 1'b1;
    r.invalid = 1'b1;
  end else if ((da.is_zero && db.is_inf) || (da.is_inf && db.is_zero)) begin
    r.is_nan = 1'b1;
    r.invalid = 1'b1;
  end else if (da.is_inf || db.is_inf) begin
    r.is_inf = 1'b1;
  end else if (da.is_zero || db.is_zero) begin
    r.is_zero = 1'b1;
  end else begin
    r.p = da.sig * db.sig;
    r.q = da.q + db.q;
  end

  ref_mul_bf16 = r;
endfunction

// Aligned fixed-point contribution of one lane product. Finite products shift
// into the accumulator scale (LSB weight 2^-30) and are two's-complement
// negated by sign; special/zero products contribute numeric zero. Single source
// of truth shared by the golden reduction and the align lane proof.
function automatic logic signed [ACC_BF16_W-1:0] ref_align_bf16_lane(
    input bf16_product_t prod);
  logic signed [ACC_BF16_W-1:0] contrib;
  int shift_amt;
  ref_align_bf16_lane = '0;
  if (!prod.is_zero && !prod.is_inf && !prod.is_nan) begin
    shift_amt = int'(prod.q) + BF16_ACC_FRAC_BITS;
    contrib   = ACC_BF16_W'(prod.p) <<< shift_amt;
    ref_align_bf16_lane = prod.p_sign ? -contrib : contrib;
  end
endfunction

function automatic logic [FP32_W-1:0] ref_round_bf16_acc_to_fp32(
    input logic signed [ACC_BF16_W-1:0] acc);
  logic sign;
  logic [ACC_BF16_W-1:0] mag;
  logic [ACC_BF16_W-1:0] shifted;
  logic [ACC_BF16_W-1:0] low_mask;
  logic [ACC_BF16_W-1:0] remainder;
  logic [ACC_BF16_W-1:0] half;
  logic [24:0] sig_ext;
  logic [7:0] exp_bits;
  logic round_up;
  int msb;
  int shift;
  int exp_biased;

  if (acc == '0) begin
    ref_round_bf16_acc_to_fp32 = '0;
  end else begin
    sign = acc[ACC_BF16_W-1];
    mag = sign ? (~acc + ACC_BF16_W'(1)) : acc;

    msb = 0;
    for (int i = 0; i < ACC_BF16_W; i++) begin
      if (mag[i]) msb = i;
    end

    exp_biased = msb - BF16_ACC_FRAC_BITS + 127;
    sig_ext = '0;

    if (msb <= 23) begin
      shifted = mag << (23 - msb);
      sig_ext = {1'b0, shifted[23:0]};
    end else begin
      shift = msb - 23;
      shifted = mag >> shift;
      sig_ext = {1'b0, shifted[23:0]};

      low_mask = (ACC_BF16_W'(1) << shift) - ACC_BF16_W'(1);
      remainder = mag & low_mask;
      half = ACC_BF16_W'(1) << (shift - 1);
      round_up = (remainder > half) || ((remainder == half) && sig_ext[0]);
      if (round_up) sig_ext = sig_ext + 25'd1;

      if (sig_ext[24]) begin
        sig_ext = sig_ext >> 1;
        exp_biased = exp_biased + 1;
      end
    end

    exp_bits = exp_biased[7:0];
    ref_round_bf16_acc_to_fp32 = {sign, exp_bits, sig_ext[22:0]};
  end
endfunction

// Pre-round reduction: exact fixed-point accumulation of finite products plus
// the resolved special outcome, BEFORE the RNE round. This is the LINEAR part
// of the dot-product; the top AG proof asserts DUT equivalence at this
// boundary, and the rounded-result equivalence follows by transitivity with the
// standalone rounder proof (final_round_bf16 == ref_round_bf16_acc_to_fp32).
function automatic bf16_preround_t dotprod_ref_bf16_preround
    (input logic [BF16_W-1:0] a [N_LANES],
     input logic [BF16_W-1:0] b [N_LANES]);
  bf16_product_t prod;
  bf16_preround_t r;
  logic saw_pos_inf;
  logic saw_neg_inf;
  logic any_nan;

  r = '0;
  saw_pos_inf = 1'b0;
  saw_neg_inf = 1'b0;
  any_nan = 1'b0;
  r.acc = '0;

  for (int i = 0; i < N_LANES; i++) begin
    prod = ref_mul_bf16(a[i], b[i]);
    if (prod.is_nan) begin
      any_nan = 1'b1;
    end else if (prod.is_inf) begin
      if (prod.p_sign) saw_neg_inf = 1'b1;
      else             saw_pos_inf = 1'b1;
    end
    // Finite/zero contribution (special products contribute zero).
    r.acc = r.acc + ref_align_bf16_lane(prod);
  end

  // Special ladder, identical ordering to special_case_bf16.
  if (any_nan || (saw_pos_inf && saw_neg_inf)) begin
    r.special_valid          = 1'b1;
    r.special_result         = FP32_QNAN;
    r.special_status.is_nan  = 1'b1;
    r.special_status.invalid = 1'b1;
  end else if (saw_pos_inf || saw_neg_inf) begin
    r.special_valid        = 1'b1;
    r.special_result       = saw_neg_inf ? 32'hFF80_0000 : 32'h7F80_0000;
    r.special_status.is_inf = 1'b1;
  end else begin
    r.special_valid = 1'b0;
  end

  dotprod_ref_bf16_preround = r;
endfunction

function automatic logic [FP32_W-1:0] dotprod_ref_bf16
    (input logic [BF16_W-1:0] a [N_LANES],
     input logic [BF16_W-1:0] b [N_LANES],
     output logic invalid,
     output logic is_nan,
     output logic is_inf);
  bf16_preround_t pr;
  pr = dotprod_ref_bf16_preround(a, b);

  invalid = pr.special_status.invalid;
  is_nan  = pr.special_status.is_nan;
  is_inf  = pr.special_status.is_inf;

  if (pr.special_valid)
    dotprod_ref_bf16 = pr.special_result;
  else
    dotprod_ref_bf16 = ref_round_bf16_acc_to_fp32(pr.acc);
endfunction

`endif
