`timescale 1ns/1ps
import dotprod_pkg::*;

module align_bf16_tb;
  bf16_product_t prod [N_LANES];
  logic signed [ACC_BF16_W-1:0] wide [N_LANES];
  int errors = 0;
  int cases = 0;

  align_bf16 dut (.prod(prod), .wide(wide));

  task automatic clear_products();
    foreach (prod[i]) begin
      prod[i] = '0;
      prod[i].is_zero = 1'b1;
    end
    #1;
  endtask

  task automatic check_lane(
      input string name,
      input int lane,
      input logic signed [ACC_BF16_W-1:0] exp);
    cases++;
    #1;
    if (wide[lane] !== exp) begin
      errors++;
      $error("%s: lane %0d got 0x%014h exp 0x%014h",
             name, lane, wide[lane], exp);
    end
  endtask

  initial begin
    clear_products();
    prod[0].is_zero = 1'b0;
    prod[0].p = 16'h4000;
    prod[0].q = 10'sd0;
    check_lane("q0 high placement", 0, 56'sd1 <<< 44);

    clear_products();
    prod[1].is_zero = 1'b0;
    prod[1].p = 16'h4000;
    prod[1].q = -10'sd30;
    check_lane("q-30 lsb placement", 1, 56'sd16384);

    clear_products();
    prod[2].is_zero = 1'b0;
    prod[2].p_sign = 1'b1;
    prod[2].p = 16'h4000;
    prod[2].q = -10'sd14;
    check_lane("negative product", 2, -(56'sd1 <<< 30));

    clear_products();
    prod[3].is_zero = 1'b1;
    prod[4].is_zero = 1'b0;
    prod[4].is_inf = 1'b1;
    prod[5].is_zero = 1'b0;
    prod[5].is_nan = 1'b1;
    check_lane("zero product", 3, '0);
    check_lane("inf product numeric zero", 4, '0);
    check_lane("nan product numeric zero", 5, '0);

    if (errors) $fatal(1, "ALIGN_BF16 FAIL: %0d errors", errors);
    $display("ALIGN_BF16 PASS (%0d cases)", cases);
    $finish;
  end
endmodule
