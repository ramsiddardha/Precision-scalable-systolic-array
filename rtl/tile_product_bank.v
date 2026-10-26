// Sixteen unsigned 4x4 multiplier tiles and their weighted product rows.
// a_mag and b_mag are unsigned magnitudes from precision_decode_mag.
// mode: 00 = INT4, 01 = INT8, 10 = INT16, 11 = inactive.
// USE_HSM chooses one tile architecture for the whole bank at elaboration.
module tile_product_bank #(
    parameter integer USE_HSM = 1
) (
    input  wire [1:0]   mode,
    input  wire         enable,
    input  wire [15:0]  a_mag,
    input  wire [15:0]  b_mag,
    output wire [15:0]  tile_enabled,
    output wire [511:0] partial_products
);

    // Keep each tile's original eight-bit output visible for simulation.
    wire [7:0] tile_product [0:15];

    // Reuse the decoder: enable 1, 4 or 16 tiles for the selected precision.
    // A global disable or reserved mode disables every tile.
    tile_enable_decode control (
        .mode(mode),
        .enable(enable),
        .tile_enable(tile_enabled)
    );

    // This loop creates sixteen parallel hardware instances.
    genvar t;
    generate
        for (t = 0; t < 16; t = t + 1) begin : g_tiles
            localparam integer A_CHUNK = t / 4;
            localparam integer B_CHUNK = t % 4;
            localparam integer SHIFT = 4 * (A_CHUNK + B_CHUNK);

            // Chunk 0 is bits [3:0]; chunk 1 is bits [7:4], and so on.
            tile4_unsigned #(.USE_HSM(USE_HSM)) tile (
                .enable(tile_enabled[t]),
                .a_chunk(a_mag[4*A_CHUNK +: 4]),
                .b_chunk(b_mag[4*B_CHUNK +: 4]),
                .product(tile_product[t])
            );

            // Widen BEFORE shifting so that high product bits are retained.
            // The shift is constant for each instance: fixed bit wiring.
            // Row t occupies bits [32*t +: 32] of the 512-bit output bus.
            assign partial_products[32*t +: 32] =
                {24'd0, tile_product[t]} << SHIFT;
        end
    endgenerate

    // The next block will reduce these sixteen rows using our CSAs.
endmodule
