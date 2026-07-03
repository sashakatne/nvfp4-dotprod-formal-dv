`ifndef DOTPROD_SEQ_SV
`define DOTPROD_SEQ_SV
import dotprod_pkg::*;
// Sequential ready/valid wrapper around the unified INT8/BF16 combinational
// core. 2-cycle latency: stage1 registers inputs, stage2 registers the
// combinational result. The handshake/stall contract is unchanged from M2; M3
// only widens the datapath (16-bit operands, dotprod_status_t) and adds the
// BF16 path, muxed by mode.
module dotprod_seq (
  input  logic                         clk,
  input  logic                         rst_n,
  input  fmt_e                         mode,
  input  logic [BF16_W-1:0]            a [N_LANES],
  input  logic [BF16_W-1:0]            b [N_LANES],
  input  logic                         in_valid,
  output logic                         in_ready,
  output logic [FP32_W-1:0]            result,
  output dotprod_status_t              status,
  output logic                         sat,
  output logic                         out_valid,
  input  logic                         out_ready
);
  // Global stall: hold everything when a produced result is not being accepted.
  logic stall;
  assign stall    = out_valid & ~out_ready;
  assign in_ready = ~stall;

  // Stage 1: capture inputs (mode + widened operands).
  logic [BF16_W-1:0] a_s1 [N_LANES], b_s1 [N_LANES];
  fmt_e              mode_s1;
  logic              v_s1;

  // ---------------- INT8 datapath (M1, unchanged; low byte only) ----------
  logic signed [INT8_W-1:0]  a_op [N_LANES], b_op [N_LANES];
  logic signed [PROD_W-1:0]  prod [N_LANES];
  logic signed [ACC_W-1:0]   wide [N_LANES];
  logic signed [ACC_W-1:0]   sum;
  logic signed [INT8_OUT_W-1:0] int8_result;
  logic                      int8_sat;

  genvar i;
  generate
    for (i = 0; i < N_LANES; i++) begin : g_lane
      front_end_int8 fe (
        .a_in(a_s1[i][INT8_W-1:0]), .b_in(b_s1[i][INT8_W-1:0]),
        .a_op(a_op[i]), .b_op(b_op[i]));
      mul_lane       ml (.a_op(a_op[i]), .b_op(b_op[i]), .prod(prod[i]));
    end
  endgenerate
  align_to_fixed al (.prod(prod), .wide(wide));
  exact_acc_tree ac (.wide(wide), .sum(sum));
  final_round    fr (.sum(sum), .result(int8_result), .sat(int8_sat));

  // ---------------- BF16 datapath (M3, parallel) --------------------------
  bf16_product_t                 prod_bf16 [N_LANES];
  logic signed [ACC_BF16_W-1:0]  wide_bf16 [N_LANES];
  logic signed [ACC_BF16_W-1:0]  sum_bf16;
  logic                          special_valid;
  logic [FP32_W-1:0]             special_result;
  dotprod_status_t               special_status;
  logic [FP32_W-1:0]             bf16_result;
  dotprod_status_t               bf16_status;

  generate
    for (i = 0; i < N_LANES; i++) begin : g_lane_bf16
      mul_lane_bf16 ml16 (.a(a_s1[i]), .b(b_s1[i]), .product(prod_bf16[i]));
    end
  endgenerate
  align_bf16        al16 (.prod(prod_bf16), .wide(wide_bf16));
  exact_acc_tree #(.W(ACC_BF16_W)) ac16 (.wide(wide_bf16), .sum(sum_bf16));
  special_case_bf16 sc16 (
    .prod(prod_bf16), .special_valid(special_valid),
    .special_result(special_result), .special_status(special_status));
  final_round_bf16  fr16 (
    .sum(sum_bf16), .special_valid(special_valid),
    .special_result(special_result), .special_status(special_status),
    .result(bf16_result), .status(bf16_status));

  // ---------------- NVFP4 datapath (M4, parallel) --------------------------
  logic [3:0]                       nv_ea [NVFP4_BLOCK], nv_eb [NVFP4_BLOCK];
  logic [7:0]                       nv_sa, nv_sb;
  nvfp4_product_t                   nvfp4_prod [NVFP4_BLOCK];
  logic signed [NVFP4_INNER_W-1:0]  nvfp4_wide [NVFP4_BLOCK];
  logic signed [NVFP4_INNER_W-1:0]  nvfp4_inner_sum;
  logic [7:0]                       nvfp4_scale_sig;
  logic signed [6:0]                nvfp4_scale_exp;
  logic                             nvfp4_scale_is_nan;
  logic [FP32_W-1:0]                nvfp4_result;
  dotprod_status_t                  nvfp4_status;

  always_comb begin
    for (int k = 0; k < NVFP4_BLOCK; k++) begin
      nv_ea[k] = a_s1[k/4][4*(k%4) +: 4];
      nv_eb[k] = b_s1[k/4][4*(k%4) +: 4];
    end
    nv_sa = a_s1[4][7:0];
    nv_sb = b_s1[4][7:0];
  end
  generate
    for (i = 0; i < NVFP4_BLOCK; i++) begin : g_lane_nvfp4
      mul_lane_nvfp4 mln (.a(nv_ea[i]), .b(nv_eb[i]), .product(nvfp4_prod[i]));
    end
  endgenerate
  align_nvfp4 aln (.prod(nvfp4_prod), .wide(nvfp4_wide));
  exact_acc_tree #(.N(NVFP4_BLOCK), .W(NVFP4_INNER_W)) acn (
    .wide(nvfp4_wide), .sum(nvfp4_inner_sum));
  scale_mul_nvfp4 scn (
    .sa(nv_sa), .sb(nv_sb),
    .scale_sig(nvfp4_scale_sig), .scale_exp(nvfp4_scale_exp),
    .scale_is_nan(nvfp4_scale_is_nan));
  final_round_nvfp4 frn (
    .inner_sum(nvfp4_inner_sum),
    .scale_sig(nvfp4_scale_sig), .scale_exp(nvfp4_scale_exp),
    .scale_is_nan(nvfp4_scale_is_nan),
    .result(nvfp4_result), .status(nvfp4_status));

  // Unified core output, selected by the staged mode.
  logic [FP32_W-1:0] core_result;
  dotprod_status_t   core_status;
  always_comb begin
    unique case (mode_s1)
      FMT_BF16: begin
        core_result = bf16_result;
        core_status = bf16_status;
      end
      FMT_NVFP4: begin
        core_result = nvfp4_result;
        core_status = nvfp4_status;
      end
      default: begin
        core_result = FP32_W'(int8_result);
        core_status = '{sat:int8_sat, invalid:1'b0, is_nan:1'b0, is_inf:1'b0};
      end
    endcase
  end

  // Stage registers + 2-deep valid pipeline, all frozen on stall.
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      v_s1 <= 1'b0; out_valid <= 1'b0;
    end else if (!stall) begin
      // stage 1 accepts a new beat when input handshake fires
      v_s1    <= in_valid & in_ready;
      mode_s1 <= mode;
      foreach (a_s1[j]) a_s1[j] <= a[j];
      foreach (b_s1[j]) b_s1[j] <= b[j];
      // stage 2 registers the core output and advances valid
      out_valid <= v_s1;
      result    <= core_result;
      status    <= core_status;
    end
`ifdef BUG_SEQ_DROP
    else begin
      // BUG: under backpressure stall, drop the held output instead of holding it.
      // Directly violates p_hold_stable.
      out_valid <= 1'b0;
    end
`endif
  end

  assign sat = status.sat;
endmodule
`endif
