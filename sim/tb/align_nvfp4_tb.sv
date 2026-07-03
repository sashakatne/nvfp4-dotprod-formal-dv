`timescale 1ns/1ps
import dotprod_pkg::*;

module align_nvfp4_tb;
  nvfp4_product_t                   prod [NVFP4_BLOCK];
  logic signed [NVFP4_INNER_W-1:0]  wide [NVFP4_BLOCK];
  int errors = 0;
  int cases  = 0;

  align_nvfp4 dut (.prod(prod), .wide(wide));

  task automatic clear_products();
    foreach (prod[i]) prod[i] = '0;
    #1;
  endtask

  task automatic check_lane(
      input string name,
      input int    lane,
      input logic signed [NVFP4_INNER_W-1:0] exp);
    cases++;
    #1;
    if (wide[lane] !== exp) begin
      errors++;
      $error("%s: lane %0d got %0d (0x%04h) exp %0d (0x%04h)",
             name, lane, wide[lane], wide[lane], exp, exp);
    end
  endtask

  initial begin
    // Case 1: positive product +144 sign-extends to 13'sd144
    clear_products();
    prod[0].prod = 9'sd144;
    check_lane("+144 sign-extend", 0, 13'sd144);

    // Case 2: negative product -144 sign-extends to -13'sd144
    // -144 in 9-bit two's complement: 9'h170 = 9'b1_0111_0000
    clear_products();
    prod[1].prod = -9'sd144;
    check_lane("-144 sign-extend", 1, -13'sd144);

    // Case 3: all lanes +9 (e.g. 3.0 * 3.0 == 9)
    clear_products();
    foreach (prod[i]) prod[i].prod = 9'sd9;
    foreach (prod[i]) check_lane("all lanes +9", i, 13'sd9);

    // Case 4: zero product -> wide == 0
    clear_products();
    prod[0].prod = 9'sd0;
    check_lane("zero product", 0, 13'sd0);

    if (errors) $fatal(1, "ALIGN_NVFP4 FAIL: %0d errors", errors);
    $display("ALIGN_NVFP4 PASS (%0d cases)", cases);
    $finish;
  end
endmodule
