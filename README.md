# nvfp4-dotprod-formal-dv

**Author:** Sasha Katne

Formal and simulation verification of an 8-lane mixed-precision vector
dot-product unit with an exact wide accumulator. Supported formats:

- INT8, with a combinational datapath and a pipelined ready/valid wrapper.
- BF16, with exact fixed-point accumulation and a single IEEE binary32 round.
- NVFP4 block-scaled FP4, with E2M1 elements and UE4M3 block scales.

The verification methodology uses shared SystemVerilog golden references in
`ref/` for both formal assertions and simulation scoreboards, reducing model
drift between the two verification methods.

See `doc/FinalReport_M5.md` for the whole-project sign-off summary. Raw tool
logs, transcripts, and coverage databases are generated artifacts and are not
checked into the repository.

## Repository Layout

| Path | Description |
|------|-------------|
| `rtl/` | Synthesizable RTL: `dotprod_pkg`, `dotprod_top`, and submodules |
| `ref/` | Golden reference models shared by formal and simulation |
| `formal/RTL/` | SVA modules, bind files, and filelists |
| `formal/run/` | VC Formal Tcl scripts for clean and bug-injected runs |
| `sim/tb/` | Directed SystemVerilog testbenches |
| `sim/run.do` | Directed Questa compile/run script |
| `verif/uvm/` | UVM environment, sequences, scoreboard, coverage, and tests |
| `verif/tb/` | UVM top-level testbench |
| `verif/sim/run.do` | UVM compile/run script |
| `doc/` | Design specs, verification plans, final reports, and diagrams |

## Milestone Arc

| Milestone | Status | Content |
|-----------|--------|---------|
| M1 | Complete | INT8 RTL, FPV proof, directed sim, bug injection, docs |
| M2 | Complete | INT8 sequential pipeline, UVM environment, protocol FPV, coverage |
| M3 | Complete | BF16 tier, assume-guarantee formal decomposition, UVM BF16 regression |
| M4 | Complete | NVFP4 tier, block-scaled FP4 datapath, assume-guarantee proof, UVM NVFP4 regression |
| M5 | Complete | Full regression sweep, NVFP4 final-round proof, 100% reachable merged coverage |

## Verification Summary

The final sweep covers 18 formal proof jobs and 7 UVM tests:

- All clean formal variants prove their target assertions.
- Each bug-injected variant falsifies at least one intended assertion.
- All UVM tests report zero mismatches, zero leftovers, and zero fatal/errors.
- Merged reachable coverage is 100.00% after applying the documented waiver in
  `verif/sim/coverage_waivers.do`.

Two cover goals are structurally unreachable and documented in
`doc/FinalReport_M5.md`:

- INT8 saturation cannot occur for a single 8-lane dot product because the
  maximum exact sum fits far below the 32-bit saturating output range.
- The maximum NVFP4 scale significand condition cannot occur because the largest
  E2M1 significand product is below the covered threshold.

## Reproduction

These commands assume compatible VC Formal and Questa installations are already
configured in the shell environment.

```bash
# INT8 formal
cd formal/run
vcf -batch -f fpv_run_top.tcl
vcf -batch -f fpv_run_top_buginjected.tcl
vcf -batch -f fpv_run_seq.tcl
vcf -batch -f fpv_run_seq_buginjected.tcl

# BF16 formal
vcf -batch -f fpv_run_lane_bf16.tcl
vcf -batch -f fpv_run_align_bf16.tcl
vcf -batch -f fpv_run_round_bf16.tcl
vcf -batch -f fpv_run_special_bf16.tcl
vcf -batch -f fpv_run_bf16_top.tcl
vcf -batch -f fpv_run_bf16_top_buginjected.tcl

# NVFP4 formal
vcf -batch -f fpv_run_lane_nvfp4.tcl
vcf -batch -f fpv_run_lane_nvfp4_buginjected.tcl
vcf -batch -f fpv_run_scale_nvfp4.tcl
vcf -batch -f fpv_run_scale_nvfp4_buginjected.tcl
vcf -batch -f fpv_run_round_nvfp4.tcl
vcf -batch -f fpv_run_round_nvfp4_buginjected.tcl
vcf -batch -f fpv_run_nvfp4_top.tcl
vcf -batch -f fpv_run_nvfp4_top_buginjected.tcl

# Directed simulation
cd ../../sim
vsim -c -do run.do

# UVM regression
cd ../verif/sim
vsim -c -do run.do
```

Expected outcome: clean formal runs prove, bug-injected formal runs falsify their
target properties, directed simulation passes, and UVM regression completes with
zero scoreboard mismatches.
