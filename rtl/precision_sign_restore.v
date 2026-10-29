// Restore the sign of one unsigned product magnitude.
// The decoder supplies negative = sign(A) XOR sign(B).
// INT4, INT8 and INT16 products occupy 8, 16 and 32 bits respectively.
module precision_sign_restore (
    input  wire               enable,
    input  wire [1:0]         mode,
    input  wire               negative,
    input  wire [31:0]        magnitude_product,
    output reg signed [31:0]  product
);

    // One conditional two's-complement datapath, split as 8 + 8 + 16 bits.
    // Positive products bypass it; unused negation sections receive zeros.
    wire low_enable, mid_enable, high_enable;
    wire [7:0] low_inverted, mid_inverted;
    wire [15:0] high_inverted;
    wire mid_cin, high_cin;
    wire [8:0] low_negative, mid_negative;
    wire [16:0] high_negative;
    wire [7:0] result8;
    wire [15:0] result16;
    wire [31:0] result32;

    // The top module enables this block only for valid precision modes.
    assign low_enable = enable && negative;
    assign mid_enable = low_enable && ((mode == 2'b01) || (mode == 2'b10));
    assign high_enable = low_enable && (mode == 2'b10);

    // Two's complement means invert the active magnitude bits and add one.
    // The addition's carry continues into each required upper section.
    assign low_inverted = low_enable ? ~magnitude_product[7:0] : 8'd0;
    assign low_negative = {1'b0, low_inverted} + {8'd0, low_enable};
    assign mid_inverted = mid_enable ? ~magnitude_product[15:8] : 8'd0;
    assign mid_cin = mid_enable ? low_negative[8] : 1'b0;
    assign mid_negative = {1'b0, mid_inverted} + {8'd0, mid_cin};
    assign high_inverted = high_enable ? ~magnitude_product[31:16] : 16'd0;
    assign high_cin = high_enable ? mid_negative[8] : 1'b0;
    assign high_negative = {1'b0, high_inverted} + {16'd0, high_cin};

    // Choose the positive magnitude or its negation at the active width.
    assign result8 = low_enable ? low_negative[7:0] : magnitude_product[7:0];
    assign result16 = low_enable ? {mid_negative[7:0], low_negative[7:0]}
                                 : magnitude_product[15:0];
    assign result32 = low_enable ? {high_negative[15:0], mid_negative[7:0], low_negative[7:0]}
                                 : magnitude_product;

    // Sign-extend the active signed product to the common 32-bit output bus.
    // A zero magnitude restores to zero even when the negative flag is set.
    always @* begin
        product = 32'sd0;
        if (enable) begin
            case (mode)
                2'b00: product = {{24{result8[7]}}, result8};
                2'b01: product = {{16{result16[15]}}, result16};
                2'b10: product = result32;
                default: product = 32'sd0;
            endcase
        end
    end
endmodule
