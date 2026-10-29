`timescale 1ns/1ps

// Combinational 36-bit adder: nine four-bit CLAs plus a parallel prefix network.
// Precision selects a contiguous low field of 12, 20 or 36 bits: 3, 5 or 9 CLAs.
// Operands must already have the desired signed representation; this core
// returns raw result bits. precision_accumulator_adder handles sign extension.
module cla_prefix_36 (
    input  wire [35:0] a,
    input  wire [35:0] b,
    input  wire        enable,
    input  wire [1:0]  mode,
    output wire [35:0] sum,
    output wire [8:0]  slice_enabled,
    output wire        carry_out_36,
    output wire        carry_out_8
);
    wire [35:0] a_isolated, b_isolated;
    wire [8:0] block_g, block_p;
    wire [8:0] cut_g, cut_p;
    wire [8:0] g1, p1, g2, p2, g4, p4, g8;
    wire [9:0] carry;

    // Continuous case decoding also handles constant-input simulation startup.
    // Unknown or reserved precision disables every block.
    function [8:0] precision_mask;
        input [1:0] selected_mode;
        begin
            case (selected_mode)
                2'b00: precision_mask = 9'b000000111;
                2'b01: precision_mask = 9'b000011111;
                2'b10: precision_mask = 9'b111111111;
                default: precision_mask = 9'd0;
            endcase
        end
    endfunction
    assign slice_enabled = enable ? precision_mask(mode) : 9'd0;

    // This two-operand accumulator addition has no external carry input.
    // carry[n] enters CLA n; carry[9] is the bit-36 carry in full-width mode.
    assign carry[0] = 1'b0;
    assign carry[9:1] = g8;
    assign carry_out_36 = carry[9];
    // Carry from the lowest eight bits; used for INT4 register-clock gating.
    assign carry_out_8 = carry[2];

    genvar n;
    generate
        for (n = 0; n < 9; n = n + 1) begin : g_slice
            wire pass_boundary;

            // Each unused CLA sees two zero operands and a zero incoming carry.
            assign a_isolated[4*n +: 4] = slice_enabled[n] ? a[4*n +: 4] : 4'd0;
            assign b_isolated[4*n +: 4] = slice_enabled[n] ? b[4*n +: 4] : 4'd0;

            // Cut BOTH generate and propagate before prefix combination at an
            // active-to-inactive boundary. A narrow addition cannot activate
            // the first unused block through an outgoing carry.
            if (n < 8) begin : g_boundary
                assign pass_boundary = slice_enabled[n] && slice_enabled[n+1];
            end else begin : g_last
                // No further CLA follows, but preserve the full-width carry
                // for verification. Narrow modes leave this block disabled.
                assign pass_boundary = slice_enabled[n];
            end
            assign cut_g[n] = block_g[n] & pass_boundary;
            assign cut_p[n] = block_p[n] & pass_boundary;

            cla4 block_adder (
                .a(a_isolated[4*n +: 4]), .b(b_isolated[4*n +: 4]),
                .cin(carry[n]), .sum(sum[4*n +: 4]),
                .group_g(block_g[n]), .group_p(block_p[n])
            );
        end
    endgenerate

    // Parallel group combination: Ghi:lo = Ghi | Phi*Glo,
    // Phi:lo = Phi*Plo. Each level combines preceding summaries at a fixed
    // block distance (1, 2, 4, 8); there is no serial nine-block carry chain.
    // A missing lower group has identity G=0 and P=1.
    assign g1 = cut_g | (cut_p & {cut_g[7:0], 1'b0});
    assign p1 = cut_p & {cut_p[7:0], 1'b1};
    assign g2 = g1 | (p1 & {g1[6:0], 2'b0});
    assign p2 = p1 & {p1[6:0], 2'b11};
    assign g4 = g2 | (p2 & {g2[4:0], 4'b0});
    assign p4 = p2 & {p2[4:0], 4'b1111};
    assign g8 = g4 | (p4 & {g4[0], 8'b0});

    // The raw narrow result is zero above its active field. The caller
    // sign-extends that field; the bit-36 carry is not a signed overflow flag.
    // Synthesis may flatten/optimize the explicit logical block boundaries.
endmodule
