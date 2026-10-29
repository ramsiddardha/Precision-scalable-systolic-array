// Convert the selected CSA sum/carry pair into one unsigned magnitude.
// csa_carry is UNSHIFTED, matching csa_3to2 and csa_tree_16x32.
// For valid inputs: magnitude = csa_sum + 2*csa_carry.
// The tile bank guarantees that the result fits its precision's product width.
module precision_final_adder (
    input  wire [1:0]  mode,
    input  wire        enable,
    input  wire [31:0] csa_sum,
    input  wire [31:0] csa_carry,
    output reg  [31:0] magnitude_product
);

    // Two 16-bit sections, with a carry from the lower to the upper section.
    // The '+' operators let synthesis choose the implementation within each.
    wire low_enable;
    wire high_enable;
    wire [15:0] low_a, low_b;
    wire [15:0] high_a, high_b;
    wire high_cin;
    wire [16:0] low_result;
    wire [16:0] high_result;

    // INT8 needs the lower 16-bit section; INT16 needs both sections.
    // INT4 already has a finished tile product and bypasses both sections.
    assign low_enable = enable && ((mode == 2'b01) || (mode == 2'b10));
    assign high_enable = enable && (mode == 2'b10);

    // Align the carry row once while selecting its low and high fields.
    // (csa_carry << 1)[15:0]  = {csa_carry[14:0], 1'b0}.
    // (csa_carry << 1)[31:16] = csa_carry[30:15].
    // csa_carry[31] is zero for a valid product that fits in 32 bits.
    assign low_a = low_enable ? csa_sum[15:0] : 16'd0;
    assign low_b = low_enable ? {csa_carry[14:0], 1'b0} : 16'd0;
    assign high_a = high_enable ? csa_sum[31:16] : 16'd0;
    assign high_b = high_enable ? csa_carry[30:15] : 16'd0;

    // Retain the carry out of the lower section before joining the sections.
    assign low_result = {1'b0, low_a} + {1'b0, low_b};

    // Also isolate the carry input of the unused upper section in INT8.
    assign high_cin = high_enable ? low_result[16] : 1'b0;
    assign high_result = {1'b0, high_a} + {1'b0, high_b} + {16'd0, high_cin};

    // Present the active product width as a zero-extended 32-bit magnitude.
    // Sign restoration is a separate following block.
    always @* begin
        magnitude_product = 32'd0;
        if (enable) begin
            case (mode)
                2'b00: magnitude_product = {24'd0, csa_sum[7:0]};
                2'b01: magnitude_product = {16'd0, low_result[15:0]};
                2'b10: magnitude_product = {high_result[15:0], low_result[15:0]};
                default: magnitude_product = 32'd0;
            endcase
        end
    end
endmodule
