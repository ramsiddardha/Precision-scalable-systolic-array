`timescale 1ns/1ps

// Signed accumulator addition using nine four-bit CLAs and parallel prefixes.
// Sixteen signed 8/16/32-bit products fit signed 12/20/36-bit sums.
// mode: 00 = INT4, 01 = INT8, 10 = INT16; 11 is inactive.
module precision_accumulator_adder #(
    // Keep signed formatting for standalone callers. The accumulator stores
    // raw active fields and formats only its external output.
    parameter integer RAW_RESULT = 0
) (
    input  wire               enable,
    input  wire [1:0]         mode,
    input  wire signed [35:0] acc_in,
    input  wire signed [31:0] product_in,
    output wire signed [35:0] sum_out,
    output wire               carry_out_8
);
    wire [35:0] product_extended;
    wire [35:0] raw_sum;
    wire [8:0] slice_enabled;
    wire carry_out_36;

    // Normalize the active signed product field before extending to 36 bits.
    // This also ignores unused upper input bits during narrow-precision work.
    // Continuous evaluation also covers inputs initialized to constant zero
    // before procedural simulation starts, without requiring a mode toggle.
    function [35:0] extend_product;
        input [1:0] selected_mode;
        input [31:0] value;
        begin
            case (selected_mode)
                2'b00: extend_product = {{28{value[7]}}, value[7:0]};
                2'b01: extend_product = {{20{value[15]}}, value[15:0]};
                2'b10: extend_product = {{4{value[31]}}, value};
                default: extend_product = 36'd0;
            endcase
        end
    endfunction
    assign product_extended = extend_product(mode, product_in);

    // INT4 enables CLAs 0..2; INT8 enables 0..4; INT16 enables 0..8.
    // The carry-prefix core performs operand and boundary isolation itself.
    // It is pure combinational logic: all storage stays in the clocked parent.
    cla_prefix_36 prefix (
        .a(acc_in), .b(product_extended), .enable(enable), .mode(mode),
        .sum(raw_sum), .slice_enabled(slice_enabled), .carry_out_36(carry_out_36),
        .carry_out_8(carry_out_8)
    );

    // Return the active signed result on one common 36-bit bus.
    // The accumulator's sixteen-product bound prevents arithmetic overflow.
    // As an isolated adder, arithmetic is modulo the selected active width.
    function [35:0] format_sum;
        input [1:0] selected_mode;
        input [35:0] value;
        begin
            case (selected_mode)
                2'b00: format_sum = {{24{value[11]}}, value[11:0]};
                2'b01: format_sum = {{16{value[19]}}, value[19:0]};
                2'b10: format_sum = value;
                default: format_sum = 36'd0;
            endcase
        end
    endfunction
    generate
        if (RAW_RESULT != 0) begin : g_raw_result
            // Unused fields are already zero inside the isolated CLA core.
            assign sum_out = raw_sum;
        end else begin : g_signed_result
            assign sum_out = enable ? format_sum(mode, raw_sum) : 36'd0;
        end
    endgenerate
endmodule
