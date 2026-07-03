# Design Specification - M2: Sequential INT8 Dot-Product Wrapper

**Author:** Sasha Katne

## 1. Overview

M1 proved the combinational INT8 dot-product core correct via FPV equivalence against a floating-point reference. M2 wraps that core in a ready/valid streaming interface and adds a 2-stage pipeline register. The wrapper serves two goals: make the module plug into a standard handshake fabric, and give the verification environment a place to prove handshake and backpressure properties that are out of scope for M1's arithmetic proof.

The sequential wrapper (`dotprod_seq`) does not touch the arithmetic datapath. All multiplications, accumulations, rounding, and saturation happen inside the same M1 combinational sub-modules. M2 adds input capture registers (Stage 1), output capture registers (Stage 2), a stall signal, and the ready/valid handshake logic.

## 2. Interface

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Synchronous active-low reset |
| `mode` | input | `fmt_e` | Format select (INT8 only in M2) |
| `a[N_LANES]` | input | 8 per lane | Signed INT8 input vector A (N_LANES=8) |
| `b[N_LANES]` | input | 8 per lane | Signed INT8 input vector B (N_LANES=8) |
| `in_valid` | input | 1 | Producer asserts: a/b/mode are valid this cycle |
| `in_ready` | output | 1 | Wrapper asserts: ready to accept inputs |
| `result` | output | 32 | Signed INT8 dot-product result |
| `sat` | output | 1 | Saturation flag from M1 core |
| `out_valid` | output | 1 | Result on `result`/`sat` is valid |
| `out_ready` | input | 1 | Consumer asserts: ready to consume output |

## 3. Handshake Contract

Input side: a transaction is accepted when both `in_valid` and `in_ready` are high at the rising clock edge (`in_valid && in_ready`). The producer must hold `a`, `b`, and `mode` stable until the handshake completes.

Output side: a transaction is consumed when both `out_valid` and `out_ready` are high at the rising clock edge (`out_valid && out_ready`). The wrapper must hold `result` and `sat` stable until the handshake completes.

Reset: synchronous, active-low. On the falling edge of `rst_n` (sampled at posedge `clk`), all pipeline registers and `out_valid` clear to zero. `out_valid` must already be low at the cycle `rst_n` rises - the same-cycle implication `$rose(rst_n) |-> !out_valid` (P2, proven by FPV).

## 4. Pipeline Architecture

The wrapper implements a 2-cycle latency pipeline.

```
Cycle N:   in_valid && in_ready -> Stage-1 captures a/b/mode, v_s1 <= 1
Cycle N+1: Stage-2 captures core_result/core_sat, out_valid <= v_s1
```

**Stage 1** (`always_ff` on posedge `clk`): when not stalled, latches `in_valid && in_ready` into `v_s1` and unconditionally captures `a`/`b` into `a_s1`/`b_s1` (the beat is valid downstream only when `v_s1` is high). On reset, `v_s1` clears; the data registers are not reset.

**Stage 2** (same `always_ff` block, same stall guard): when not stalled, captures `core_result` and `core_sat` from the M1 combinational core and drives `out_valid <= v_s1`.

**Combinational core**: `a_s1` and `b_s1` feed through the same M1 sub-pipeline (`front_end_int8 -> mul_lane -> align_to_fixed -> exact_acc_tree -> final_round`), producing `core_result` (32-bit) and `core_sat` (1-bit) each cycle.

**Global stall**: `stall = out_valid & ~out_ready`. When the consumer holds `out_ready` low while `out_valid` is high, `stall` goes high. Both always_ff blocks are gated by `!stall`, so every register in the pipeline freezes simultaneously.

**in_ready**: `in_ready = ~stall`. When the pipeline stalls, the wrapper deasserts `in_ready` to stop the producer from injecting new data into a frozen pipeline.

## 5. Stall / Backpressure

When the consumer asserts `out_ready=0` while `out_valid=1`:

1. `stall` asserts combinationally.
2. `in_ready` deasserts, signaling the producer to pause.
3. All `always_ff` blocks skip their update (guarded by `if (!stall)`).
4. `result`, `sat`, and `out_valid` are frozen on the output.
5. `a_s1`, `b_s1`, `v_s1` are frozen in Stage 1.

The pipeline resumes the cycle after the consumer deasserts backpressure (`out_ready=1`), at which point `stall` clears, registers update, and `in_ready` reasserts.

This is a simple global-freeze backpressure scheme. It is not the most throughput-efficient approach (a FIFO or credit-based scheme would allow Stage 2 to drain while Stage 1 continues), but it is correct, simple to reason about, and straightforward to verify formally.

## 6. Arithmetic Coverage

The M1 FPV campaign proved the combinational core (`front_end_int8`, `mul_lane`, `align_to_fixed`, `exact_acc_tree`, `final_round`) correct for all INT8 input combinations via bounded equivalence checking against the floating-point reference. M2 does not re-prove arithmetic correctness.

M2 adds and formally proves three handshake/control properties over the sequential wrapper:

- **P1 p_hold_stable**: output held stable during stall
- **P2 p_no_out_at_reset**: `out_valid` deasserted at the cycle `rst_n` rises
- **P3 p_stall_blocks_ready**: stall deasserts in_ready

These properties cover the sequential control logic that is outside M1's scope.

## 7. Bug Injection

The module contains a guarded bug injection point controlled by the `BUG_INJECTION` preprocessor define:

```systemverilog
`ifdef BUG_INJECTION
  else begin  // stall branch
    out_valid <= 1'b0;  // BUG: should hold, but drops out_valid
  end
`endif
```

When compiled with `+define+BUG_INJECTION`, the stall `else` branch incorrectly clears `out_valid` instead of holding it. This violates P1 (`p_hold_stable`): a valid output can be silently dropped when the consumer applies backpressure. The FPV bug-injection run falsifies P1 at depth 4, confirming the property is sensitive to this mutation. P2 and P3 remain proven because they do not depend on the stall-path behavior.
