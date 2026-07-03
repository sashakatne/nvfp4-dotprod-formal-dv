`ifndef NVFP4_UNPACK_SVH
`define NVFP4_UNPACK_SVH
// Shared NVFP4 port packing (spec §5): element k at a[k/4][4*(k%4) +: 4],
// UE4M3 scale at a[4][7:0].
function automatic void ref_unpack_nvfp4(
    input  logic [15:0] v [N_LANES],
    output logic [3:0]  e [NVFP4_BLOCK],
    output logic [7:0]  scale);
  for (int k = 0; k < NVFP4_BLOCK; k++)
    e[k] = v[k/4][4*(k%4) +: 4];
  scale = v[4][7:0];
endfunction
`endif
