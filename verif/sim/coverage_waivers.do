# Coverage waivers for structurally-unreachable bins.
# Each exclusion cites a concrete structural reason; reachable bins are
# closed by stimulus (dotprod_corner_seq), never waived.
#
# dotprod_seq.sv:143  v_s1 <= in_valid & in_ready;
#   This line lives inside else-if (!stall), and in_ready = ~stall, so
#   in_ready is unconditionally 1 whenever execution reaches this line.
#   The in_ready_0 FEC row (row 3) can therefore never be taken.
coverage exclude -scope /dotprod_seq_tb/dut -fecexprrow 143 3 -reason EUR -comment {in_ready=~stall, so in_ready_0 is unreachable whenever this line (inside else-if !stall) executes}
