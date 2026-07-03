`ifndef DOTPROD_SEQ_ITEM_SV
`define DOTPROD_SEQ_ITEM_SV
class dotprod_seq_item extends uvm_sequence_item;
  // 4-state (logic) to match the DUT-facing interface signals, so whole-array
  // copies between seq_item and dotprod_if are legal in Questa. Operands are
  // BF16-width; INT8 mode constrains each element to a sign-extended byte.
  rand logic [BF16_W-1:0] a [N_LANES];
  rand logic [BF16_W-1:0] b [N_LANES];
  rand fmt_e              mode;

  // captured on the output side by the monitor. 4-state so a DUT that drives
  // X/Z reaches the scoreboard and fails === rather than being truncated.
  logic [FP32_W-1:0] result;
  dotprod_status_t   status;
  logic              sat;

  // Default mode is INT8; tests/sequences relax or override via c_mode/inline.
  // NVFP4 sequences pre-pack a/b and drive with force_int8==0, mode==FMT_NVFP4.
  rand bit force_int8;
  constraint c_mode_default { soft force_int8 == 1; }
  constraint c_mode { force_int8 -> mode == FMT_INT8; }
  constraint c_mode_valid  { mode inside {FMT_INT8, FMT_BF16, FMT_NVFP4}; }

  // INT8 stimulus lives in the low byte as a sign-extended value; the high byte
  // is don't-care to the INT8 datapath, so pin it to the sign extension to keep
  // the transaction human-readable and reproducible.
  constraint c_int8_lowbyte {
    (mode == FMT_INT8) -> {
      foreach (a[i]) a[i][BF16_W-1:INT8_W] == {(BF16_W-INT8_W){a[i][INT8_W-1]}};
      foreach (b[i]) b[i][BF16_W-1:INT8_W] == {(BF16_W-INT8_W){b[i][INT8_W-1]}};
    }
  }

  // Pack 16 E2M1 nibbles and a UE4M3 scale byte into the a/b lane arrays
  // using the shared layout (spec §5): element k at v[k/4][4*(k%4)+:4],
  // scale at v[4][7:0]; lanes 5-7 are zero-padded.
  static function automatic void pack_nvfp4(
      input  logic [3:0] elem  [NVFP4_BLOCK],
      input  logic [7:0] scale,
      output logic [BF16_W-1:0] v [N_LANES]);
    v = '{default: 16'h0};
    for (int k = 0; k < NVFP4_BLOCK; k++)
      v[k/4][4*(k%4) +: 4] = elem[k];
    v[4][7:0] = scale;
  endfunction

  `uvm_object_utils_begin(dotprod_seq_item)
    `uvm_field_sarray_int(a, UVM_ALL_ON)
    `uvm_field_sarray_int(b, UVM_ALL_ON)
    `uvm_field_enum(fmt_e, mode, UVM_ALL_ON)
    `uvm_field_int(result, UVM_ALL_ON)
    `uvm_field_int(sat, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "dotprod_seq_item");
    super.new(name);
  endfunction
endclass
`endif
