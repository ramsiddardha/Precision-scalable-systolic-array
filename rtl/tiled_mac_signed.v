`timescale 1ns/1ps

// Registered multiply-accumulate datapath for one sixteen-term dot product.
// External A/B are sampled through the multiplier into the product register.
// The following edge accumulates that stored product. A/B forwarding/input
// registers for a complete systolic PE are a later integration step.
module tiled_mac_signed #(
    parameter integer USE_HSM = 1
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               clear,
    input  wire               advance,
    input  wire               in_valid,
    input  wire [1:0]         mode,
    input  wire [15:0]        a_in,
    input  wire [15:0]        b_in,
    output wire               in_ready,
    output wire               mode_valid,
    output wire signed [35:0] acc_q,
    output wire [1:0]         acc_mode_q,
    output wire [4:0]         term_count,
    output wire               result_valid,
    output wire               protocol_error,
    output wire [15:0]        tile_enabled
);
    wire frame_compatible;
    wire [5:0] reserved_terms;
    wire accept_input;
    wire signed [31:0] multiplier_product;
    wire multiplier_mode_valid;
    wire signed [31:0] product_q;
    wire [1:0] product_mode_q;
    wire product_valid_q;

    // Keep the admission decoder independent of the multiplier data path.
    // The precision input is valid even when the pipeline is idle/stalled.
    function mode_is_valid;
        input [1:0] selected_mode;
        begin
            case (selected_mode)
                2'b00, 2'b01, 2'b10: mode_is_valid = 1'b1;
                default: mode_is_valid = 1'b0;
            endcase
        end
    endfunction
    assign mode_valid = mode_is_valid(mode);

    // Count consumed products plus the one possibly waiting in the register.
    // Reserving that pending slot prevents accepting a seventeenth product.
    assign reserved_terms = {1'b0, term_count} + {5'd0, product_valid_q};
    assign frame_compatible = (term_count != 5'd0) ? (mode == acc_mode_q) :
                              product_valid_q ? (mode == product_mode_q) : 1'b1;
    assign in_ready = rst_n && !clear && advance && mode_valid &&
                      frame_compatible && (reserved_terms < 6'd16) && !protocol_error;
    assign accept_input = in_valid && in_ready;

    // Only accepted input transactions activate the combinational multiplier.
    tiled_multiplier_signed #(.USE_HSM(USE_HSM)) multiply (
        .mode(mode), .enable(accept_input), .a_in(a_in), .b_in(b_in),
        .product(multiplier_product), .mode_valid(multiplier_mode_valid),
        .tile_enabled(tile_enabled)
    );

    // On an advancing bubble the valid bit drops while product data is held.
    // On a stall, this stage and the accumulator both retain their state.
    precision_product_register product_stage (
        .clk(clk), .rst_n(rst_n), .clear(clear), .advance(advance),
        .in_valid(accept_input), .mode(mode), .product_in(multiplier_product),
        .product_q(product_q), .product_mode_q(product_mode_q),
        .product_valid_q(product_valid_q)
    );

    // Nonblocking updates mean this stage consumes the OLD registered product
    // at the same edge that product_stage can capture the NEXT product.
    precision_accumulator accumulate (
        .clk(clk), .rst_n(rst_n), .clear(clear), .advance(advance),
        .product_valid(product_valid_q), .product_mode(product_mode_q),
        .product_in(product_q), .acc_q(acc_q), .acc_mode_q(acc_mode_q),
        .term_count(term_count), .result_valid(result_valid),
        .protocol_error(protocol_error)
    );

    // result_valid becomes high after sixteen consumed products and remains
    // high until clear/reset. After the last accepted input, advance at least
    // once more to drain the pending product into the final accumulator sum.
endmodule
