`timescale 1ns/1ps

// Precision-aware signed-to-magnitude conversion, with no registers/latches.
// mode 00/01/10 selects 4/8/16 operand bits; reserved/X modes return zero.
// The tile bank still consumes unsigned magnitudes; sign restoration is later.
module precision_decode_mag (
    input  wire [1:0]  mode,
    input  wire [15:0] a_in,
    input  wire [15:0] b_in,
    output wire [15:0] a_mag,
    output wire [15:0] b_mag,
    output wire        product_negative,
    output wire        mode_valid
);
    // Decode through continuous functions, including constant-input startup.
    // {valid, sign_A, sign_B}; ignored upper input bits are never sign inputs.
    function [2:0] decode_signs;
        input [1:0] selected_mode;
        input [15:0] a_value, b_value;
        begin
            case (selected_mode)
                2'b00: decode_signs = {1'b1, a_value[3],  b_value[3]};
                2'b01: decode_signs = {1'b1, a_value[7],  b_value[7]};
                2'b10: decode_signs = {1'b1, a_value[15], b_value[15]};
                default: decode_signs = 3'b000;
            endcase
        end
    endfunction
    wire [2:0] signs;
    assign signs = decode_signs(mode, a_in, b_in);
    assign mode_valid = signs[2];
    assign product_negative = signs[2] && (signs[1] ^ signs[0]);

    // Share one 4+4+8-bit magnitude path per operand. Positive operands pass
    // through; negative operands use (value XOR sign_mask) + sign.
    // Upper sections receive zero operands AND zero carry when unused.
    function [15:0] magnitude;
        input [1:0] selected_mode;
        input [15:0] value;
        input negative, valid;
        reg use_mid, use_high;
        reg [3:0] low_xor, mid_xor;
        reg [7:0] high_xor;
        reg [4:0] low_result, mid_result;
        reg [8:0] high_result;
        begin
            // INT4 uses only the lowest four arithmetic bits. INT8 extends
            // that path to eight bits; INT16 enables all sixteen bits.
            use_mid = valid && ((selected_mode == 2'b01) || (selected_mode == 2'b10));
            use_high = valid && (selected_mode == 2'b10);

            low_xor = valid ? (value[3:0] ^ {4{negative}}) : 4'd0;
            low_result = {1'b0, low_xor} + {4'd0, negative};
            mid_xor = use_mid ? (value[7:4] ^ {4{negative}}) : 4'd0;
            mid_result = {1'b0, mid_xor} + {4'd0, (use_mid && low_result[4])};
            high_xor = use_high ? (value[15:8] ^ {8{negative}}) : 8'd0;
            high_result = {1'b0, high_xor} + {8'd0, (use_high && mid_result[4])};

            // Magnitudes are zero-extended, not sign-extended. The minimum
            // negatives remain representable: -8->8, -128->128, -32768->32768.
            magnitude = {high_result[7:0], mid_result[3:0], low_result[3:0]};
        end
    endfunction
    assign a_mag = magnitude(mode, a_in, signs[1], signs[2]);
    assign b_mag = magnitude(mode, b_in, signs[0], signs[2]);

    // No changes are made to the product's final signed output formatting.
endmodule
