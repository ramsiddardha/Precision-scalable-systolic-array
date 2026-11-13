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

    // Two explicit operand paths share the same selected-mode sign decoder.
    dm_prefix_or_operand a_path (
        .mode(mode), .value(a_in), .negative(signs[1]), .valid(signs[2]), .magnitude(a_mag)
    );
    dm_prefix_or_operand b_path (
        .mode(mode), .value(b_in), .negative(signs[0]), .valid(signs[2]), .magnitude(b_mag)
    );
endmodule

// One 4+4+8-bit signed-to-unsigned-magnitude conversion path.
module dm_prefix_or_operand (
    input wire [1:0] mode,
    input wire [15:0] value,
    input wire negative, valid,
    output wire [15:0] magnitude
);
    wire use_mid, use_high;
    wire low_active, mid_active, high_active;
    wire [3:0] low_data, mid_data;
    wire [7:0] high_data;
    wire low_cin, mid_cin, high_cin;
    wire [4:0] low_result, mid_result;
    wire [8:0] high_result;
    assign use_mid = valid && ((mode == 2'b01) || (mode == 2'b10));
    assign use_high = valid && (mode == 2'b10);
    assign low_active = valid;
    assign mid_active = use_mid;
    assign high_active = use_high;
    assign low_cin = negative;
    assign mid_cin = mid_active && low_result[4];
    assign high_cin = high_active && mid_result[4];

    // Low field: explicit per-bit input isolation.
    assign low_data[0] = low_active & value[0];
    assign low_data[1] = low_active & value[1];
    assign low_data[2] = low_active & value[2];
    assign low_data[3] = low_active & value[3];
    dm_prefix_or_inc4 low_increment (
        .x(low_data), .cin(low_cin),
        .negative(negative), .active(low_active),
        .sum(low_result[3:0]), .cout(low_result[4])
    );

    // Mid field: explicit per-bit input isolation.
    assign mid_data[0] = mid_active & value[4];
    assign mid_data[1] = mid_active & value[5];
    assign mid_data[2] = mid_active & value[6];
    assign mid_data[3] = mid_active & value[7];
    dm_prefix_or_inc4 mid_increment (
        .x(mid_data), .cin(mid_cin),
        .negative(negative), .active(mid_active),
        .sum(mid_result[3:0]), .cout(mid_result[4])
    );

    // High field: explicit per-bit input isolation.
    assign high_data[0] = high_active & value[8];
    assign high_data[1] = high_active & value[9];
    assign high_data[2] = high_active & value[10];
    assign high_data[3] = high_active & value[11];
    assign high_data[4] = high_active & value[12];
    assign high_data[5] = high_active & value[13];
    assign high_data[6] = high_active & value[14];
    assign high_data[7] = high_active & value[15];
    dm_prefix_or_inc8 high_increment (
        .x(high_data), .cin(high_cin),
        .negative(negative), .active(high_active),
        .sum(high_result[7:0]), .cout(high_result[8])
    );

    // Magnitudes keep their active field and zero-fill all unused bits.
    assign magnitude[0] = low_result[0];
    assign magnitude[1] = low_result[1];
    assign magnitude[2] = low_result[2];
    assign magnitude[3] = low_result[3];
    assign magnitude[4] = mid_result[0];
    assign magnitude[5] = mid_result[1];
    assign magnitude[6] = mid_result[2];
    assign magnitude[7] = mid_result[3];
    assign magnitude[8] = high_result[0];
    assign magnitude[9] = high_result[1];
    assign magnitude[10] = high_result[2];
    assign magnitude[11] = high_result[3];
    assign magnitude[12] = high_result[4];
    assign magnitude[13] = high_result[5];
    assign magnitude[14] = high_result[6];
    assign magnitude[15] = high_result[7];
endmodule

// Conditional two's-complement OR-prefix; x is the isolated original field.
module dm_prefix_or_inc4 (
    input wire [3:0] x,
    input wire cin,
    input wire negative, active,
    output wire [3:0] sum,
    output wire cout
);
    // negative=0 passes x; negative=1 computes (~x)+cin.
    // active=0 is paired with x=0 and cin=0 by the operand wrapper.
    wire flip_from_lower;
    assign flip_from_lower = active & negative & ~cin;
    wire [3:0] prefix0;
    wire [3:0] prefix1;
    wire [3:0] prefix2;
    assign prefix0[0] = x[0];
    assign prefix0[1] = x[1];
    assign prefix0[2] = x[2];
    assign prefix0[3] = x[3];

    // Prefix row 1: 3 combine nodes.
    assign prefix1[0] = prefix0[0];
    assign prefix1[1] = prefix0[1] | prefix0[0];
    assign prefix1[2] = prefix0[2] | prefix0[1];
    assign prefix1[3] = prefix0[3] | prefix0[2];

    // Prefix row 2: 2 combine nodes.
    assign prefix2[0] = prefix1[0];
    assign prefix2[1] = prefix1[1];
    assign prefix2[2] = prefix1[2] | prefix1[0];
    assign prefix2[3] = prefix1[3] | prefix1[1];
    assign sum[0] = x[0] ^ flip_from_lower;
    assign sum[1] = x[1] ^ (flip_from_lower | (active & negative & prefix2[0]));
    assign sum[2] = x[2] ^ (flip_from_lower | (active & negative & prefix2[1]));
    assign sum[3] = x[3] ^ (flip_from_lower | (active & negative & prefix2[2]));
    assign cout = active & negative & cin & ~prefix2[3];
endmodule

// Conditional two's-complement OR-prefix; x is the isolated original field.
module dm_prefix_or_inc8 (
    input wire [7:0] x,
    input wire cin,
    input wire negative, active,
    output wire [7:0] sum,
    output wire cout
);
    // negative=0 passes x; negative=1 computes (~x)+cin.
    // active=0 is paired with x=0 and cin=0 by the operand wrapper.
    wire flip_from_lower;
    assign flip_from_lower = active & negative & ~cin;
    wire [7:0] prefix0;
    wire [7:0] prefix1;
    wire [7:0] prefix2;
    wire [7:0] prefix3;
    assign prefix0[0] = x[0];
    assign prefix0[1] = x[1];
    assign prefix0[2] = x[2];
    assign prefix0[3] = x[3];
    assign prefix0[4] = x[4];
    assign prefix0[5] = x[5];
    assign prefix0[6] = x[6];
    assign prefix0[7] = x[7];

    // Prefix row 1: 7 combine nodes.
    assign prefix1[0] = prefix0[0];
    assign prefix1[1] = prefix0[1] | prefix0[0];
    assign prefix1[2] = prefix0[2] | prefix0[1];
    assign prefix1[3] = prefix0[3] | prefix0[2];
    assign prefix1[4] = prefix0[4] | prefix0[3];
    assign prefix1[5] = prefix0[5] | prefix0[4];
    assign prefix1[6] = prefix0[6] | prefix0[5];
    assign prefix1[7] = prefix0[7] | prefix0[6];

    // Prefix row 2: 6 combine nodes.
    assign prefix2[0] = prefix1[0];
    assign prefix2[1] = prefix1[1];
    assign prefix2[2] = prefix1[2] | prefix1[0];
    assign prefix2[3] = prefix1[3] | prefix1[1];
    assign prefix2[4] = prefix1[4] | prefix1[2];
    assign prefix2[5] = prefix1[5] | prefix1[3];
    assign prefix2[6] = prefix1[6] | prefix1[4];
    assign prefix2[7] = prefix1[7] | prefix1[5];

    // Prefix row 3: 4 combine nodes.
    assign prefix3[0] = prefix2[0];
    assign prefix3[1] = prefix2[1];
    assign prefix3[2] = prefix2[2];
    assign prefix3[3] = prefix2[3];
    assign prefix3[4] = prefix2[4] | prefix2[0];
    assign prefix3[5] = prefix2[5] | prefix2[1];
    assign prefix3[6] = prefix2[6] | prefix2[2];
    assign prefix3[7] = prefix2[7] | prefix2[3];
    assign sum[0] = x[0] ^ flip_from_lower;
    assign sum[1] = x[1] ^ (flip_from_lower | (active & negative & prefix3[0]));
    assign sum[2] = x[2] ^ (flip_from_lower | (active & negative & prefix3[1]));
    assign sum[3] = x[3] ^ (flip_from_lower | (active & negative & prefix3[2]));
    assign sum[4] = x[4] ^ (flip_from_lower | (active & negative & prefix3[3]));
    assign sum[5] = x[5] ^ (flip_from_lower | (active & negative & prefix3[4]));
    assign sum[6] = x[6] ^ (flip_from_lower | (active & negative & prefix3[5]));
    assign sum[7] = x[7] ^ (flip_from_lower | (active & negative & prefix3[6]));
    assign cout = active & negative & cin & ~prefix3[7];
endmodule
