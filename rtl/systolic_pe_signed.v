`timescale 1ns/1ps

// One output-stationary systolic PE: registered A-right/B-down forwarding plus
// the existing tiled multiplier, product register and CLA/prefix accumulator.
// USE_HSM is an elaboration choice; mode is fixed during one sixteen-term frame.
//
// All connected PEs and boundary sources share advance, clear, clk and rst_n.
// There is no independent ready/valid backpressure on a forwarding link. On each
// advancing edge, valid operands move one hop; upstream sequencing must align
// matching A[k]/B[k] at a PE. One-sided valid tokens during fill/drain are legal.
module systolic_pe_signed #(
    parameter integer USE_HSM = 1
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               clear,
    input  wire               advance,
    input  wire [1:0]         mode,
    input  wire [15:0]        a_in,
    input  wire [15:0]        b_in,
    input  wire               a_valid_in,
    input  wire               b_valid_in,
    output wire signed [15:0] a_out,
    output wire signed [15:0] b_out,
    output wire               a_valid_out,
    output wire               b_valid_out,
    output wire signed [35:0] acc_q,
    output wire [1:0]         acc_mode_q,
    output wire [4:0]         term_count,
    output wire               result_valid,
    output wire               protocol_error,
    output wire [15:0]        tile_enabled
);
    wire [1:0] a_mode_q, b_mode_q;
    wire input_mode_valid;
    wire paired_valid, paired_modes_match;
    wire mac_ready, mac_mode_valid, mac_error;
    reg stream_error_q;

    // A and B keep independent valids so array startup/drain does not invent
    // products. Both registered outputs also feed the local multiplier.
    precision_operand_register a_stage (
        .clk(clk), .rst_n(rst_n), .clear(clear), .advance(advance),
        .in_valid(a_valid_in), .mode(mode), .data_in(a_in),
        .data_q(a_out), .mode_q(a_mode_q), .valid_q(a_valid_out)
    );
    precision_operand_register b_stage (
        .clk(clk), .rst_n(rst_n), .clear(clear), .advance(advance),
        .in_valid(b_valid_in), .mode(mode), .data_in(b_in),
        .data_q(b_out), .mode_q(b_mode_q), .valid_q(b_valid_out)
    );

    function mode_is_valid;
        input [1:0] selected_mode;
        begin
            case (selected_mode)
                2'b00, 2'b01, 2'b10: mode_is_valid = 1'b1;
                default: mode_is_valid = 1'b0;
            endcase
        end
    endfunction
    assign input_mode_valid = mode_is_valid(mode);
    assign paired_valid = a_valid_out && b_valid_out;
    assign paired_modes_match = (a_mode_q == b_mode_q);

    // The MAC admits at most sixteen pairs including its pending product slot.
    // Its operand pair comes from the OLD A/B registers at this rising edge;
    // the two operand registers simultaneously capture the next forwarding hop.
    tiled_mac_signed #(.USE_HSM(USE_HSM)) mac (
        .clk(clk), .rst_n(rst_n), .clear(clear), .advance(advance),
        .in_valid(paired_valid && paired_modes_match && !stream_error_q),
        .mode(a_mode_q), .a_in(a_out), .b_in(b_out),
        .in_ready(mac_ready), .mode_valid(mac_mode_valid),
        .acc_q(acc_q), .acc_mode_q(acc_mode_q), .term_count(term_count),
        .result_valid(result_valid), .protocol_error(mac_error),
        .tile_enabled(tile_enabled)
    );

    // The fixed schedule has no local retry channel. Diagnose a bad valid-mode
    // token or an unconsumable aligned pair (changed precision / seventeenth
    // term), rather than silently losing a product. Legal forwarding continues;
    // after an error no further local pairs enter until clear/reset. An already
    // stored product may still drain. Results with protocol_error are invalid.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            stream_error_q <= 1'b0;
        else if (clear)
            stream_error_q <= 1'b0;
        else if (advance) begin
            if (((a_valid_in || b_valid_in) && !input_mode_valid) ||
                (paired_valid && (!paired_modes_match || !mac_ready)))
                stream_error_q <= 1'b1;
        end
    end
    assign protocol_error = stream_error_q || mac_error;

    // From a clear state: edge 1 captures A1/B1; edge 2 captures product 1;
    // edge 3 accumulates product 1. Sixteen uninterrupted external pairs finish
    // on advancing edge 18. Keep advancing with invalid inputs to drain both
    // pending stages. The output remains valid until clear/reset.
endmodule
