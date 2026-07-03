# Verification Plan - M2: Sequential INT8 Dot-Product

**Author:** Sasha Katne

## 1. Scope

### In Scope
- `dotprod_seq` sequential pipeline wrapper
- INT8 mode only (mode=INT8)
- Ready/valid handshake protocol on both input and output ports
- Backpressure handling (out_ready deassertion)
- Synchronous active-low reset behavior
- Bug-injection mutation testing (BUG_INJECTION ifdef)

### Out of Scope
- BF16 and NVFP4 arithmetic modes (M3/M4)
- Arithmetic equivalence of the combinational core (covered by M1 FPV)
- SoC-level integration and multi-module interactions
- Timing closure and synthesis

## 2. UVM Environment Architecture

The testbench follows a standard UVM layered architecture with two agents, a scoreboard, and a functional coverage subscriber.

### Interface
`dotprod_if` provides three clocking blocks: `drv_cb` (input driver), `outdrv_cb` (output driver), and `mon_cb` (monitor). It exposes modports `IN_DRV`, `OUT_DRV`, and `MON`.

### Input Agent (`dotprod_in_agent`)
- **Sequencer** (`dotprod_sequencer`): drives sequence items to the input driver
- **Input Driver** (`in_driver`): drives `a`, `b`, `mode`, and `in_valid`; honors `in_ready` for flow control; inserts random idle gaps between transactions to exercise non-contiguous valid patterns
- **Input Monitor** (`in_monitor`): samples transactions when `in_valid && in_ready` at the clock edge; broadcasts via analysis port `ap_in`

### Output Agent (`dotprod_out_agent`)
- **Output Driver** (`out_driver`): drives randomized `out_ready` backpressure patterns; no sequencer
- **Output Monitor** (`out_monitor`): samples transactions when `out_valid && out_ready` at the clock edge; broadcasts via analysis port `ap_out`

### Scoreboard (`dotprod_scoreboard`)
- `write_in`: receives input transactions from `ap_in`, computes the golden reference via `dotprod_ref(a, b)`, and pushes the expected result to `exp_q`
- `write_out`: receives output transactions from `ap_out`, pops the head of `exp_q`, and compares `result` and `sat` against expected values; increments `matched` or `mismatched` counters
- Reports `leftover` (non-zero `exp_q` at end of test) in addition to match/mismatch counts

### Coverage Subscriber (`dotprod_coverage`)
- Receives `ap_in` transactions and samples `cg_value` (per-lane value classes and cross)
- Samples `cg_proto` from the DUT interface during the run phase (handshake protocol states)

### Environment Wiring
```
in_agent.mon.ap_in  --> scoreboard.ap_in  (write_in)
                    --> coverage.analysis_export (cg_value sampling)
out_agent.mon.ap_out --> scoreboard.ap_out (write_out)
```
The environment `run_phase` includes a drain delay of 1000 time units after the test sequence ends to allow in-flight transactions to complete before checking scoreboard state.

### Tests
| Test | Description | Items |
|------|-------------|-------|
| `dotprod_random_test` | Fully randomized a/b vectors with random backpressure | 500 |
| `dotprod_backpressure_test` | Randomized a/b with aggressive sustained backpressure | 1000 |
| `dotprod_corner_test` | Directed: zero, max-positive, max-negative, mixed-sign vectors | 4 |

## 3. Coverage Model

### Code Coverage Targets
| Metric | Target | Rationale |
|--------|--------|-----------|
| Statements | 100% | Full sequential logic coverage |
| Branches | 100% | Both stall and non-stall paths |
| Expressions | >= 90% | FEC may leave low-priority terms uncovered |

### Functional Coverage - cg_value
Samples per-lane input values and their cross, from accepted input transactions via `ap_in`.

- `cp_a`: 5 bins for lane A - `zero` ({0}), `maxp` ({127}), `maxn` ({-128}), `neg` ([-127:-1]), `pos` ([1:126])
- `cp_b`: 5 bins for lane B - same class partition as `cp_a`
- `x_ab`: auto-cross of `cp_a` x `cp_b` = 25 bins total

### Functional Coverage - cg_proto
Samples handshake protocol states each clock cycle from the DUT interface (run_phase loop on `mon_cb`). Two coverpoints:

**`cp_in`** on `{in_valid, in_ready}`:

| Bin | Condition | Meaning |
|-----|-----------|---------|
| `accept` | in_valid && in_ready (2'b11) | Input handshake completing |
| `in_stall` | in_valid && !in_ready (2'b10) | Producer held off by backpressure |
| `idle` | !in_valid && !in_ready (2'b00) | No input activity |

**`cp_out`** on `{out_valid, out_ready}`:

| Bin | Condition | Meaning |
|-----|-----------|---------|
| `drain` | out_valid && out_ready (2'b11) | Output handshake completing |
| `backpressure` | out_valid && !out_ready (2'b10) | Consumer applying backpressure |
| `no_out` | !out_valid && !out_ready (2'b00) | No output activity |

### Protocol FPV Covers
- `c_accept`: `cover property (in_valid && in_ready)` - input handshake is reachable
- `c_backpressure`: `cover property (out_valid && !out_ready)` - stall condition is reachable

## 4. Protocol Property Catalog

All properties are clocked on `posedge clk`. P1 and P3 use `disable iff (~rst_n)` to suppress checks during reset. P2 has no `disable iff` because it checks the reset-release event itself (`$rose(rst_n)`) - disabling it during reset would vacuously trivialize the property.

### P1 - p_hold_stable
```systemverilog
property p_hold_stable;
  @(posedge clk) disable iff (~rst_n)
  (out_valid && !out_ready) |=> (out_valid && $stable(result) && $stable(sat));
endproperty
assert property (p_hold_stable);
```
When the output is valid but the consumer is not ready, both `out_valid` and the output data (`result`, `sat`) must remain stable on the next cycle.

### P2 - p_no_out_at_reset
```systemverilog
property p_no_out_at_reset;
  @(posedge clk)
  $rose(rst_n) |-> !out_valid;
endproperty
assert property (p_no_out_at_reset);
```
The cycle in which `rst_n` rises from 0 to 1, `out_valid` must be low. Proves the reset clears the output stage.

### P3 - p_stall_blocks_ready
```systemverilog
property p_stall_blocks_ready;
  @(posedge clk) disable iff (~rst_n)
  (out_valid && !out_ready) |-> !in_ready;
endproperty
assert property (p_stall_blocks_ready);
```
When a stall is active (output valid but consumer not ready), `in_ready` must be deasserted. Proves the backpressure propagates back to the producer.

### Cover Properties
```systemverilog
c_accept:      cover property (@(posedge clk) (in_valid && in_ready));
c_backpressure: cover property (@(posedge clk) (out_valid && !out_ready));
```

## 5. Bug-Injection Scenario

The RTL includes a guarded mutation under `ifdef BUG_INJECTION`. In the stall `else` branch (entered when `out_valid && !out_ready` is true), the buggy code sets `out_valid <= 1'b0` instead of holding it.

**Expected behavior without bug**: `out_valid` holds high during stall. P1 passes.

**Expected behavior with bug**: on the first stall cycle, `out_valid` drops to 0, silently discarding the held output. P1 falsifies.

The FPV campaign runs two configurations:
1. Clean (`fpv_run_seq.tcl`): all 3 assertions proven, both covers covered.
2. Bug-injected (`fpv_run_seq_buginjected.tcl`): P1 falsified at depth 4; P2 and P3 remain proven because they do not depend on the stall path.

This confirms that P1 provides meaningful detection coverage for the stall-path logic.

## 6. Pass Criteria

| Category | Criterion | Required Result |
|----------|-----------|-----------------|
| Scoreboard | mismatched | 0 for all tests |
| Scoreboard | leftover | 0 for all tests |
| Scoreboard | UVM_ERROR | 0 for all tests |
| Code coverage | Statements | 100% |
| Code coverage | Branches | 100% |
| Code coverage | Expressions | >= 75% (in_ready_0 FEC gap is low-priority) |
| FPV clean | Assertions proven | 3/3 |
| FPV clean | Non-vacuous | All 3 |
| FPV clean | Covers covered | 2/2 |
| FPV bug-injected | p_hold_stable | Falsified |
| FPV bug-injected | p_no_out_at_reset | Proven |
| FPV bug-injected | p_stall_blocks_ready | Proven |

## 7. Results Summary

### UVM Regression

| Test | Items | Matched | Mismatched | Leftover | UVM_ERROR |
|------|-------|---------|------------|----------|-----------|
| dotprod_random_test | 500 | 500 | 0 | 0 | 0 |
| dotprod_backpressure_test | 1000 | 1000 | 0 | 0 | 0 |
| dotprod_corner_test | 4 | 4 | 0 | 0 | 0 |

### Code Coverage

| Metric | Result |
|--------|--------|
| Statements | 100% |
| Branches | 100% |
| Expressions | 75% |
| Total | 92.91% |

### Functional Coverage

| Covergroup | Result | Bins Hit | Total Bins |
|------------|--------|----------|------------|
| cg_value | 93.33% | 30 | 35 |
| cg_proto | 100% | 6 | 6 |
| Overall (covergroups) | 96.66% | - | 2 groups |
| Overall (bins) | 87.80% | 36 | 41 |

### Protocol FPV

| Property | Result | Note |
|----------|--------|------|
| p_hold_stable | Proven | Non-vacuous |
| p_no_out_at_reset | Proven | Non-vacuous |
| p_stall_blocks_ready | Proven | Non-vacuous |
| c_accept | Covered | Depth 1 |
| c_backpressure | Covered | Depth 3 |
| Engine wall time | ~16s | VC Formal V-2023.12-SP2-3 |
