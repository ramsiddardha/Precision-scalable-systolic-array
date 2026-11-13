`timescale 1ns/1ps

// Self-contained carry-select replacement for the PE final-adder module.
// Both helper modules are included below; no separate adder file is required.
// The top-level ports, precision decoding and isolation match the supplied RTL.

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
    // Both sections use the explicit pfa_csla16 architecture.
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
    pfa_csla16 low_adder (
        .a(low_a), .b(low_b), .cin(1'b0),
        .sum(low_result[15:0]), .cout(low_result[16])
    );

    // Also isolate the carry input of the unused upper section in INT8.
    assign high_cin = high_enable ? low_result[16] : 1'b0;
    pfa_csla16 high_adder (
        .a(high_a), .b(high_b), .cin(high_cin),
        .sum(high_result[15:0]), .cout(high_result[16])
    );

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

// Four 4-bit carry-select sections (4+4+4+4).
// The upper three sections compute cin=0 and cin=1 in parallel.
// A mux selects each section once its actual incoming carry is known.
module pfa_csla16 (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire cin,
    output wire [15:0] sum,
    output wire cout
);
    wire [4:0] carry;
    assign carry[0] = cin;
    pfa_rca4 first_section (.a(a[3:0]), .b(b[3:0]), .cin(cin), .sum(sum[3:0]), .cout(carry[1]));

    // Section 1: two candidates, selected by carry[1].
    wire [3:0] s1_zero, s1_one;
    wire c1_zero, c1_one;
    pfa_rca4 section1_zero (.a(a[7:4]), .b(b[7:4]), .cin(1'b0), .sum(s1_zero), .cout(c1_zero));
    pfa_rca4 section1_one (.a(a[7:4]), .b(b[7:4]), .cin(1'b1), .sum(s1_one), .cout(c1_one));
    assign sum[7:4] = carry[1] ? s1_one : s1_zero;
    assign carry[2] = carry[1] ? c1_one : c1_zero;

    // Section 2: two candidates, selected by carry[2].
    wire [3:0] s2_zero, s2_one;
    wire c2_zero, c2_one;
    pfa_rca4 section2_zero (.a(a[11:8]), .b(b[11:8]), .cin(1'b0), .sum(s2_zero), .cout(c2_zero));
    pfa_rca4 section2_one (.a(a[11:8]), .b(b[11:8]), .cin(1'b1), .sum(s2_one), .cout(c2_one));
    assign sum[11:8] = carry[2] ? s2_one : s2_zero;
    assign carry[3] = carry[2] ? c2_one : c2_zero;

    // Section 3: two candidates, selected by carry[3].
    wire [3:0] s3_zero, s3_one;
    wire c3_zero, c3_one;
    pfa_rca4 section3_zero (.a(a[15:12]), .b(b[15:12]), .cin(1'b0), .sum(s3_zero), .cout(c3_zero));
    pfa_rca4 section3_one (.a(a[15:12]), .b(b[15:12]), .cin(1'b1), .sum(s3_one), .cout(c3_one));
    assign sum[15:12] = carry[3] ? s3_one : s3_zero;
    assign carry[4] = carry[3] ? c3_one : c3_zero;
    assign cout = carry[4];
endmodule

// Each candidate is an explicit four-bit ripple adder.
module pfa_rca4 (
    input wire [3:0] a, b,
    input wire cin,
    output wire [3:0] sum,
    output wire cout
);
    wire [3:0] p, g;
    wire [4:0] carry;
    assign carry[0] = cin;
    assign p[0] = a[0] ^ b[0];
    assign g[0] = a[0] & b[0];
    assign sum[0] = p[0] ^ carry[0];
    assign carry[1] = g[0] | (p[0] & carry[0]);
    assign p[1] = a[1] ^ b[1];
    assign g[1] = a[1] & b[1];
    assign sum[1] = p[1] ^ carry[1];
    assign carry[2] = g[1] | (p[1] & carry[1]);
    assign p[2] = a[2] ^ b[2];
    assign g[2] = a[2] & b[2];
    assign sum[2] = p[2] ^ carry[2];
    assign carry[3] = g[2] | (p[2] & carry[2]);
    assign p[3] = a[3] ^ b[3];
    assign g[3] = a[3] & b[3];
    assign sum[3] = p[3] ^ carry[3];
    assign carry[4] = g[3] | (p[3] & carry[3]);
    assign cout = carry[4];
endmodule
