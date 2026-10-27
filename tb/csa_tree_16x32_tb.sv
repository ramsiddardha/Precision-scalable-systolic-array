`timescale 1ns/1ps

// Check the tree independently and with both unsigned tile-bank architectures.
// The reference uses wide arithmetic addition/multiplication, not a CSA model.
module csa_tree_16x32_tb;
    reg [511:0] rows;
    wire [31:0] tree_sum, tree_carry;
    reg [1:0] mode;
    reg enable;
    reg [15:0] a_mag, b_mag;
    wire [511:0] hsm_rows, basic_rows;
    wire [15:0] hsm_enabled, basic_enabled;
    wire [31:0] hsm_sum, hsm_carry, basic_sum, basic_carry;
    integer tree_checks = 0;
    integer bank_checks = 0;
    integer i, j, k, bit_index, rotation;
    integer seed = 32'h24681357;
    reg [63:0] remaining, piece;
    reg [15:0] random_a, random_b;
    reg [15:0] boundary [0:7];

    csa_tree_16x32 dut (.partial_products(rows), .sum(tree_sum), .carry(tree_carry));

    tile_product_bank #(.USE_HSM(1)) bank_hsm (
        .mode(mode), .enable(enable), .a_mag(a_mag), .b_mag(b_mag),
        .tile_enabled(hsm_enabled), .partial_products(hsm_rows)
    );
    tile_product_bank #(.USE_HSM(0)) bank_basic (
        .mode(mode), .enable(enable), .a_mag(a_mag), .b_mag(b_mag),
        .tile_enabled(basic_enabled), .partial_products(basic_rows)
    );
    csa_tree_16x32 tree_hsm (
        .partial_products(hsm_rows), .sum(hsm_sum), .carry(hsm_carry)
    );
    csa_tree_16x32 tree_basic (
        .partial_products(basic_rows), .sum(basic_sum), .carry(basic_carry)
    );

    task check_tree;
        integer index, a_group, b_group, group_index, first_tile;
        reg [63:0] expected, observed, expected_group, observed_group;
        begin
            #1;
            expected = 0;
            for (index = 0; index < 16; index = index + 1)
                expected = expected + {32'd0, rows[32*index +: 32]};
            if (expected > 64'hffffffff)
                $fatal(1, "Test violates this 32-bit product tree's input bound");

            // Widen BEFORE shifting so that a lost high carry is detectable.
            observed = {32'd0, tree_sum} + ({32'd0, tree_carry} << 1);
            if (observed !== expected)
                $fatal(1, "Tree mismatch case=%0d expected=%h observed=%h sum=%h carry=%h",
                       tree_checks, expected, observed, tree_sum, tree_carry);

            // Check that each local tree contains exactly one 2x2 quadrant.
            // This catches a correct overall sum with the wrong local grouping.
            for (a_group = 0; a_group < 2; a_group = a_group + 1)
                for (b_group = 0; b_group < 2; b_group = b_group + 1) begin
                    group_index = 2*a_group + b_group;
                    first_tile = 8*a_group + 2*b_group;
                    expected_group = {32'd0, rows[32*first_tile +: 32]} +
                                     {32'd0, rows[32*(first_tile+1) +: 32]} +
                                     {32'd0, rows[32*(first_tile+4) +: 32]} +
                                     {32'd0, rows[32*(first_tile+5) +: 32]};
                    observed_group = {32'd0, dut.group_sum[group_index]} +
                                     ({32'd0, dut.group_carry[group_index]} << 1);
                    if (observed_group !== expected_group)
                        $fatal(1, "Local quadrant mismatch case=%0d group=%0d expected=%h observed=%h",
                               tree_checks, group_index, expected_group, observed_group);
                end
            tree_checks = tree_checks + 1;
        end
    endtask

    task check_bank;
        input [1:0] selected_mode;
        input selected_enable;
        input [15:0] selected_a, selected_b;
        reg [63:0] reference_a, reference_b, expected;
        reg [63:0] hsm_result, basic_result;
        begin
            mode = selected_mode;
            enable = selected_enable;
            a_mag = selected_a;
            b_mag = selected_b;
            #1;
            case (selected_mode)
                2'b00: begin
                    reference_a = selected_a & 16'h000f;
                    reference_b = selected_b & 16'h000f;
                end
                2'b01: begin
                    reference_a = selected_a & 16'h00ff;
                    reference_b = selected_b & 16'h00ff;
                end
                2'b10: begin
                    reference_a = selected_a;
                    reference_b = selected_b;
                end
                default: begin
                    reference_a = 0;
                    reference_b = 0;
                end
            endcase
            if (!selected_enable) begin
                reference_a = 0;
                reference_b = 0;
            end
            expected = reference_a * reference_b;
            hsm_result = {32'd0, hsm_sum} + ({32'd0, hsm_carry} << 1);
            basic_result = {32'd0, basic_sum} + ({32'd0, basic_carry} << 1);
            if (hsm_result !== expected || basic_result !== expected)
                $fatal(1, "Bank/tree mismatch case=%0d mode=%b enable=%b A=%h B=%h expected=%h HSM=%h BASIC=%h",
                       bank_checks, mode, enable, a_mag, b_mag,
                       expected, hsm_result, basic_result);
            bank_checks = bank_checks + 1;
        end
    endtask

    initial begin
        rows = 0;
        mode = 2'b11;
        enable = 0;
        a_mag = 0;
        b_mag = 0;
        check_tree;

        // Hand-calculated weighted rows for 19*18 = 342.
        rows[0*32 +: 32] = 6;
        rows[1*32 +: 32] = 48;
        rows[4*32 +: 32] = 32;
        rows[5*32 +: 32] = 256;
        check_tree;

        // Test every row path, including the rows bypassing some CSA levels.
        for (i = 0; i < 16; i = i + 1) begin
            rows = 0;
            rows[32*i +: 32] = 32'hffffffff;
            check_tree;
        end
        for (i = 0; i < 16; i = i + 1)
            for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
                rows = 0;
                rows[32*i +: 32] = 32'd1 << bit_index;
                check_tree;
            end

        // Carry-heavy totals up to the complete 32-bit unsigned limit.
        for (i = 0; i < 16; i = i + 1)
            rows[32*i +: 32] = 32'h0fffffff;
        check_tree;
        rows[32*15 +: 32] = 32'h1000000e;
        check_tree;
        rows = 0;
        rows[0 +: 32] = 32'h55555555;
        rows[32 +: 32] = 32'h55555555;
        rows[64 +: 32] = 32'h55555555;
        check_tree;
        for (i = 0; i < 16; i = i + 1)
            rows[32*i +: 32] = 32'h08000000;
        check_tree;

        // Random nonnegative partitions keep the exact total within 32 bits.
        // Rotate placement to distribute nonzero values across all row paths.
        for (k = 0; k < 1000; k = k + 1) begin
            remaining = {32'd0, $unsigned($random(seed))};
            rotation = k % 16;
            rows = 0;
            for (i = 0; i < 15; i = i + 1) begin
                piece = {32'd0, $unsigned($random(seed))} % (remaining + 64'd1);
                rows[32*((i+rotation)%16) +: 32] = piece[31:0];
                remaining = remaining - piece;
            end
            rows[32*((15+rotation)%16) +: 32] = remaining[31:0];
            check_tree;
        end

        // Integration: compare each complete bank/tree path with wide A*B.
        check_bank(2'b01, 1'b1, 16'd19, 16'd18);
        for (i = 0; i < 16; i = i + 1)
            for (j = 0; j < 16; j = j + 1)
                check_bank(2'b00, 1'b1, i[15:0], j[15:0]);

        boundary[0] = 16'd0;
        boundary[1] = 16'd1;
        boundary[2] = 16'd15;
        boundary[3] = 16'd16;
        boundary[4] = 16'd255;
        boundary[5] = 16'd256;
        boundary[6] = 16'd32768;
        boundary[7] = 16'd65535;
        for (k = 1; k <= 2; k = k + 1)
            for (i = 0; i < 8; i = i + 1)
                for (j = 0; j < 8; j = j + 1)
                    check_bank(k[1:0], 1'b1, boundary[i], boundary[j]);
        for (k = 0; k < 3; k = k + 1)
            for (i = 0; i < 512; i = i + 1) begin
                random_a = $random(seed);
                random_b = $random(seed);
                check_bank(k[1:0], 1'b1, random_a, random_b);
            end
        for (k = 0; k < 4; k = k + 1)
            check_bank(k[1:0], 1'b0, 16'hffff, 16'hffff);
        check_bank(2'b11, 1'b1, 16'hffff, 16'hffff);
        check_bank(2'b10, 1'b0, 16'hxxxx, 16'hzzzz);

        $display("ALL %0d STANDALONE CSA TREE TESTS PASSED", tree_checks);
        $display("ALL %0d BANK + CSA TREE TESTS PASSED (HSM AND BASIC)", bank_checks);
        $finish;
    end
endmodule
