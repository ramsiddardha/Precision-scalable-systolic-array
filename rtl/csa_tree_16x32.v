// Grouped reduction matching the four 2x2 quadrants of the tile bank.
// Each local group reduces FOUR weighted tile products to TWO rows.
// Four local groups give eight rows, then a shared tree reduces eight to two.
// Intended for tile_product_bank: the nonnegative total must fit in 32 bits.
// Carry outputs are unshifted; align each carry once at its next input.
module csa_tree_16x32 (
    input  wire [511:0] partial_products,
    output wire [31:0]  sum,
    output wire [31:0]  carry
);

    // Two CSAs per local group: first 3 -> 2, then combine the fourth row.
    wire [31:0] local_sum_first [0:3];
    wire [31:0] local_carry_first [0:3];
    wire [31:0] group_sum [0:3];
    wire [31:0] group_carry [0:3];
    wire [31:0] shared_input [0:7];

    // Shared reduction levels: eight -> six -> four -> three -> two.
    wire [31:0] level1 [0:5];
    wire [31:0] level2 [0:3];
    wire [31:0] level3 [0:2];
    wire [31:0] carry1 [0:1];
    wire [31:0] carry2 [0:1];
    wire [31:0] carry3;

    // All rows already have the tile-product weights assigned by the bank.
    // Only the CSA carries need further left shifts here.
    genvar g;
    generate
        // Quadrants: {0,1,4,5}, {2,3,6,7}, {8,9,12,13}, {10,11,14,15}.
        // Group 0 is exactly the four tiles enabled in INT8 mode.
        for (g = 0; g < 4; g = g + 1) begin : g_local
            localparam integer A_BASE = 2 * (g / 2);
            localparam integer B_BASE = 2 * (g % 2);
            localparam integer TILE_00 = 4*A_BASE + B_BASE;
            localparam integer TILE_01 = TILE_00 + 1;
            localparam integer TILE_10 = TILE_00 + 4;
            localparam integer TILE_11 = TILE_00 + 5;

            // First local CSA consumes three of this quadrant's products.
            csa_3to2 first (
                .x(partial_products[32*TILE_00 +: 32]),
                .y(partial_products[32*TILE_01 +: 32]),
                .z(partial_products[32*TILE_10 +: 32]),
                .sum(local_sum_first[g]), .carry(local_carry_first[g])
            );

            // Second local CSA combines those two rows with product four.
            csa_3to2 second (
                .x(local_sum_first[g]),
                .y({local_carry_first[g][30:0], 1'b0}),
                .z(partial_products[32*TILE_11 +: 32]),
                .sum(group_sum[g]), .carry(group_carry[g])
            );

            // Present both local outputs as aligned rows to the shared tree.
            assign shared_input[2*g] = group_sum[g];
            assign shared_input[2*g+1] = {group_carry[g][30:0], 1'b0};
        end

        // SHARED LEVEL 1: two CSAs plus two pass-through rows: eight -> six.
        for (g = 0; g < 2; g = g + 1) begin : g_level1
            csa_3to2 reduce (
                .x(shared_input[3*g]),
                .y(shared_input[3*g+1]),
                .z(shared_input[3*g+2]),
                .sum(level1[2*g]), .carry(carry1[g])
            );
            assign level1[2*g+1] = {carry1[g][30:0], 1'b0};
        end

        // SHARED LEVEL 2: two CSAs consume all six rows: six -> four.
        for (g = 0; g < 2; g = g + 1) begin : g_level2
            csa_3to2 reduce (
                .x(level1[3*g]), .y(level1[3*g+1]), .z(level1[3*g+2]),
                .sum(level2[2*g]), .carry(carry2[g])
            );
            assign level2[2*g+1] = {carry2[g][30:0], 1'b0};
        end
    endgenerate

    // Preserve the two ungrouped rows from the first shared level.
    assign level1[4] = shared_input[6];
    assign level1[5] = shared_input[7];

    // SHARED LEVEL 3: one CSA plus one pass-through row: four -> three.
    csa_3to2 level3_reduce (
        .x(level2[0]), .y(level2[1]), .z(level2[2]),
        .sum(level3[0]), .carry(carry3)
    );
    assign level3[1] = {carry3[30:0], 1'b0};
    assign level3[2] = level2[3];

    // SHARED LEVEL 4: the last CSA produces the two output rows.
    // Keep the final carry UNSHIFTED, matching csa_3to2's interface.
    csa_3to2 level4_reduce (
        .x(level3[0]), .y(level3[1]), .z(level3[2]),
        .sum(sum), .carry(carry)
    );

    // Eight local CSAs plus six shared CSAs give fourteen in total.
    // Under the input bound, all discarded carry[31] bits are zero.
    // Precision-dependent bypass/isolation of the shared tree is a later step.
    // Next block: magnitude_product = sum + (carry shifted left by one).
endmodule
