`timescale 1ns/1ps

// One product pipeline stage after tiled_multiplier_signed.
// mode: 00 = INT4, 01 = INT8, 10 = INT16, 11 = reserved.
// The corresponding signed products occupy 8, 16 and 32 bits.
module precision_product_register (
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

    // rst_n = 0 clears immediately, without waiting for a rising clock edge.
    // Supply a reset whose release is synchronized to clk at the system level.
    // Priority: asynchronous reset, synchronous clear, then pipeline advance.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            low_q           <= 8'd0;
            mid_q           <= 8'd0;
            high_q          <= 16'd0;
            product_mode_q  <= 2'b00;
            product_valid_q <= 1'b0;
        end else if (clear) begin
            // A dot-product clear also flushes any pending pipeline product.
            // clear takes effect on a rising edge even when advance is zero.
            low_q           <= 8'd0;
            mid_q           <= 8'd0;
            high_q          <= 16'd0;
            product_mode_q  <= 2'b00;
            product_valid_q <= 1'b0;
        end else if (advance) begin
            // An advancing cycle without a new valid product is a bubble.
            // Keep the data/mode but mark them invalid for the next consumer.
            product_valid_q <= 1'b0;
            if (in_valid) begin
                case (mode)
                    2'b00, 2'b01, 2'b10: begin
                        low_q <= product_in[7:0];

                        if ((mode == 2'b01) || (mode == 2'b10))
                            mid_q <= product_in[15:8];

                        if (mode == 2'b10)
                            high_q <= product_in[31:16];

                        // Store metadata with the accepted product, not later.
                        product_mode_q  <= mode;
                        product_valid_q <= 1'b1;
                    end
                    default: begin
                        // Reserved/unknown mode: insert a bubble and hold data.
                    end
                endcase
            end
        end
        // advance = 0 holds data, mode and valid together for a pipeline stall.
    end

    // Rebuild the signed bus using the STORED precision.
    // Held upper slices must not leak into a later narrow-precision product.
    // This combinational selection adds no further pipeline register.
    always @* begin
        product_q = 32'sd0;
        case (product_mode_q)
            2'b00: product_q = {{24{low_q[7]}}, low_q};
            2'b01: product_q = {{16{mid_q[7]}}, mid_q, low_q};
            2'b10: product_q = {high_q, mid_q, low_q};
            default: product_q = 32'sd0;
        endcase
    end

    // Data holding uses ordinary register enables; the clock is never gated
    // by RTL logic. Physical clock gating and power savings require tool checks.
    // The downstream accumulator may consume only when advance && product_valid_q.
    // Reset/clear must have priority over accumulation in that downstream stage.
endmodule
