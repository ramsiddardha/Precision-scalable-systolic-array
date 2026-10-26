// Complete combinational signed INT4 / INT8 / INT16 tiled multiplier.
// USE_HSM is selected at elaboration: 1 = HSM tiles, 0 = BASIC tiles.
// mode is a runtime input: 00 = INT4, 01 = INT8, 10 = INT16, 11 = reserved.
module tiled_multiplier_signed #(
    parameter integer USE_HSM = 1
) (
    input  wire [1:0]         mode,
    input  wire               enable,
    input  wire [15:0]        a_in,
    input  wire [15:0]        b_in,
    output wire signed [31:0] product,
    output wire               mode_valid,
    output wire [15:0]        tile_enabled
);

    // No clocks or registers here: all stages are combinational connections.
    wire [15:0] decoder_a, decoder_b;
    wire [15:0] a_mag, b_mag;
    wire product_negative;
    wire operation_enable;
    wire [511:0] partial_products;
    wire [31:0] csa_sum, csa_carry;
    wire [31:0] magnitude_product;

    // Stop disabled input changes before they reach even the sign decoder.
    // mode_valid still describes the mode, independently of enable.
    assign decoder_a = enable ? a_in : 16'd0;
    assign decoder_b = enable ? b_in : 16'd0;
    precision_decode_mag decode (
        .mode(mode), .a_in(decoder_a), .b_in(decoder_b),
        .a_mag(a_mag), .b_mag(b_mag),
        .product_negative(product_negative), .mode_valid(mode_valid)
    );
    assign operation_enable = enable && mode_valid;

    // The bank contains sixteen unsigned 4x4 tiles; mode enables 1 / 4 / 16.
    tile_product_bank #(.USE_HSM(USE_HSM)) bank (
        .mode(mode), .enable(operation_enable), .a_mag(a_mag), .b_mag(b_mag),
        .tile_enabled(tile_enabled), .partial_products(partial_products)
    );

    // Four local groups followed by the shared tree, with precision bypasses.
    csa_tree_16x32 reduce (
        .mode(mode), .enable(operation_enable), .partial_products(partial_products),
        .sum(csa_sum), .carry(csa_carry)
    );

    // Carry remains unshifted on this connection; the final adder aligns it.
    precision_final_adder final_add (
        .mode(mode), .enable(operation_enable),
        .csa_sum(csa_sum), .csa_carry(csa_carry),
        .magnitude_product(magnitude_product)
    );

    // Restore the remembered sign, then sign-extend the active product field.
    precision_sign_restore restore_sign (
        .enable(operation_enable), .mode(mode), .negative(product_negative),
        .magnitude_product(magnitude_product), .product(product)
    );
endmodule
