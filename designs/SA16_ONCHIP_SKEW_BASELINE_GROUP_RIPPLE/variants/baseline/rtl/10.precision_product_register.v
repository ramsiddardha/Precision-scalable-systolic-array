`timescale 1ns/1ps

// One product pipeline stage after tiled_multiplier_signed.
// mode: 00 = INT4, 01 = INT8, 10 = INT16, 11 = reserved.
// The corresponding signed products occupy 8, 16 and 32 bits.
// Encoded outputs carry active two's-complement bits; sign is decoded using stored mode.
// ENCODED_OUTPUT=0 restores the original sign-extended bus.
module precision_product_register #(parameter integer ENCODED_OUTPUT = 1) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               clear,
    input  wire               advance,
    input  wire               in_valid,
    input  wire [1:0]         mode,
    input  wire signed [31:0] product_in,
    output reg  signed [31:0] product_q,
    output reg  [1:0]         product_mode_q,
    output reg                product_valid_q
);

    // One 32-bit storage bank, described as three independently enabled slices.
    // INT4 writes low_q; INT8 writes low_q and mid_q; INT16 writes all three.
    // Unused slices retain their previous bits until written, cleared or reset.
    reg [7:0]  low_q;
    reg [7:0]  mid_q;
    reg [15:0] high_q;

    wire valid_mode;
    wire write_product;
    wire clk_low, clk_mid, clk_high, clk_meta, clk_mode;

    // Reject reserved/X precision just as the original case statement did.
    function mode_is_valid;
        input [1:0] selected_mode;
        begin
            case (selected_mode)
                2'b00, 2'b01, 2'b10: mode_is_valid = 1'b1;
                default: mode_is_valid = 1'b0;
            endcase
        end
    endfunction
    assign valid_mode = mode_is_valid(mode);
    assign write_product = advance && in_valid && valid_mode;

    // Clear reaches every bank even during a stall. Valid metadata clocks on token/bubble transitions; only an accepted operand/product updates data.
    precision_icg icg_low (.clk(clk), .enable(clear || write_product),
        .test_enable(1'b0), .gclk(clk_low));
    precision_icg icg_mid (.clk(clk),
        .enable(clear || (write_product && ((mode == 2'b01) || (mode == 2'b10)))),
        .test_enable(1'b0), .gclk(clk_mid));
    precision_icg icg_high (.clk(clk), .enable(clear || (write_product && (mode == 2'b10))),
        .test_enable(1'b0), .gclk(clk_high));
    // Metadata clocks pulse only when their stored value needs to change.
    // The data banks keep the original accepted-token update schedule.
    precision_icg icg_meta (.clk(clk),
        .enable(clear || (advance && (product_valid_q != write_product)) || (write_product && (mode != product_mode_q))),
        .test_enable(1'b0), .gclk(clk_meta));
    // Monitor alias only; mode and valid share one physical gate.
    assign clk_mode = clk_meta;

    // Separate gated clocks stop the unused data-bank clock pins toggling.
    // Every storage bank still resets directly when rst_n falls.
    always @(posedge clk_low or negedge rst_n) begin
        if (!rst_n) low_q <= 8'd0;
        else if (clear) low_q <= 8'd0;
        else if (write_product) low_q <= product_in[7:0];
    end
    always @(posedge clk_mid or negedge rst_n) begin
        if (!rst_n) mid_q <= 8'd0;
        else if (clear) mid_q <= 8'd0;
        else if (write_product && ((mode == 2'b01) || (mode == 2'b10)))
            mid_q <= product_in[15:8];
    end
    always @(posedge clk_high or negedge rst_n) begin
        if (!rst_n) high_q <= 16'd0;
        else if (clear) high_q <= 16'd0;
        else if (write_product && (mode == 2'b10)) high_q <= product_in[31:16];
    end

    // Valid changes on token/bubble transitions; mode changes on accepted
    // precision changes. Both still hold on a stall and clear synchronously.
    always @(posedge clk_meta or negedge rst_n) begin
        if (!rst_n) begin product_valid_q <= 1'b0; product_mode_q <= 2'b00; end
        else if (clear) begin product_valid_q <= 1'b0; product_mode_q <= 2'b00; end
        else begin
            if (advance) product_valid_q <= write_product;
            if (write_product) product_mode_q <= mode;
        end
    end

    // Rebuild the signed bus using the STORED precision.
    // Held upper slices must not leak into a later narrow-precision product.
    // This combinational selection adds no further pipeline register.
    always @* begin
        product_q = 32'sd0;
        case (product_mode_q)
            2'b00: product_q = (ENCODED_OUTPUT ? {24'd0, low_q} : {{24{low_q[7]}}, low_q});
            2'b01: product_q = (ENCODED_OUTPUT ? {16'd0, mid_q, low_q} : {{16{mid_q[7]}}, mid_q, low_q});
            2'b10: product_q = {high_q, mid_q, low_q};
            default: product_q = 32'sd0;
        endcase
    end

    // Data-bank clocks use explicit latch-based clock-gating RTL. Library-cell
    // mapping and the power benefit must be checked in the synthesis reports.
    // The downstream accumulator may consume only when advance && product_valid_q.
    // Reset/clear must have priority over accumulation in that downstream stage.
endmodule
