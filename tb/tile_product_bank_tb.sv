`timescale 1ns/1ps

// Verify wiring, precision masks and isolation for both bank architectures.
// These are unsigned bank tests; signed input decoding is a separate block.
module tile_product_bank_tb;
    reg [1:0] mode;
    reg enable;
    reg [15:0] a_mag, b_mag;
    wire [15:0] hsm_enabled, basic_enabled;
    wire [511:0] hsm_rows, basic_rows;
    integer checks = 0;
    integer a_index, b_index, mode_index, row_index, column_index;
    integer seed = 32'h13572468;
    reg [15:0] random_a, random_b;
    reg [15:0] directed [0:7];

    tile_product_bank #(.USE_HSM(1)) dut_hsm (
        .mode(mode), .enable(enable), .a_mag(a_mag), .b_mag(b_mag),
        .tile_enabled(hsm_enabled), .partial_products(hsm_rows)
    );
    tile_product_bank #(.USE_HSM(0)) dut_basic (
        .mode(mode), .enable(enable), .a_mag(a_mag), .b_mag(b_mag),
        .tile_enabled(basic_enabled), .partial_products(basic_rows)
    );

    task check;
        input [1:0] selected_mode;
        input selected_enable;
        input [15:0] selected_a, selected_b;
        integer chunks, i, j, t;
        reg [15:0] expected_mask;
        reg [63:0] reference_a, reference_b, expected_total;
        reg [63:0] digit_a, digit_b, expected_row;
        reg [63:0] hsm_total, basic_total;
        begin
            mode = selected_mode;
            enable = selected_enable;
            a_mag = selected_a;
            b_mag = selected_b;
            #1;

            // Independently interpret the active low field as unsigned.
            case (selected_mode)
                2'b00: begin
                    chunks = 1;
                    reference_a = selected_a & 16'h000f;
                    reference_b = selected_b & 16'h000f;
                end
                2'b01: begin
                    chunks = 2;
                    reference_a = selected_a & 16'h00ff;
                    reference_b = selected_b & 16'h00ff;
                end
                2'b10: begin
                    chunks = 4;
                    reference_a = selected_a;
                    reference_b = selected_b;
                end
                default: begin
                    chunks = 0;
                    reference_a = 0;
                    reference_b = 0;
                end
            endcase
            if (!selected_enable) begin
                reference_a = 0;
                reference_b = 0;
            end
            expected_total = reference_a * reference_b;

            expected_mask = 16'd0;
            hsm_total = 0;
            basic_total = 0;
            for (i = 0; i < 4; i = i + 1) begin
                for (j = 0; j < 4; j = j + 1) begin
                    t = 4*i + j;
                    expected_mask[t] = selected_enable &&
                                       (i < chunks) && (j < chunks);
                    expected_row = 0;
                    if (expected_mask[t]) begin
                        digit_a = (reference_a >> (4*i)) & 64'hf;
                        digit_b = (reference_b >> (4*j)) & 64'hf;
                        expected_row = digit_a * digit_b;
                        expected_row = expected_row * (64'd1 << (4*(i+j)));
                    end

                    // Check every row's value and its assigned location.
                    if (hsm_rows[32*t +: 32] !== expected_row[31:0] ||
                        basic_rows[32*t +: 32] !== expected_row[31:0])
                        $fatal(1, "Row mismatch: case=%0d mode=%b tile=%0d A=%h B=%h expected=%h HSM=%h BASIC=%h",
                               checks, mode, t, a_mag, b_mag,
                               expected_row[31:0], hsm_rows[32*t +: 32],
                               basic_rows[32*t +: 32]);

                    // A wide independent sum detects misplaced or lost bits.
                    hsm_total = hsm_total + {32'd0, hsm_rows[32*t +: 32]};
                    basic_total = basic_total + {32'd0, basic_rows[32*t +: 32]};
                end
            end
            if (hsm_enabled !== expected_mask || basic_enabled !== expected_mask)
                $fatal(1, "Tile enable mask mismatch");
            if (hsm_total !== expected_total || basic_total !== expected_total)
                $fatal(1, "Weighted sum mismatch: expected=%0d HSM=%0d BASIC=%0d",
                       expected_total, hsm_total, basic_total);
            checks = checks + 1;
        end
    endtask

    initial begin
        // Hand-calculated example: 19*18 = 6 + 48 + 32 + 256 = 342.
        check(2'b01, 1'b1, 16'h0013, 16'h0012);
        if (hsm_rows[0*32 +: 32] !== 32'd6 ||
            hsm_rows[1*32 +: 32] !== 32'd48 ||
            hsm_rows[4*32 +: 32] !== 32'd32 ||
            hsm_rows[5*32 +: 32] !== 32'd256)
            $fatal(1, "Hand-calculated row example failed");

        // Exhaust all unsigned low-nibble and low-byte input combinations.
        for (a_index = 0; a_index < 16; a_index = a_index + 1)
            for (b_index = 0; b_index < 16; b_index = b_index + 1)
                check(2'b00, 1'b1, a_index[15:0], b_index[15:0]);
        for (a_index = 0; a_index < 256; a_index = a_index + 1)
            for (b_index = 0; b_index < 256; b_index = b_index + 1)
                check(2'b01, 1'b1, a_index[15:0], b_index[15:0]);

        // Exercise chunk boundaries and the highest possible unsigned bits.
        directed[0] = 16'd0;
        directed[1] = 16'd1;
        directed[2] = 16'd15;
        directed[3] = 16'd16;
        directed[4] = 16'd255;
        directed[5] = 16'd256;
        directed[6] = 16'd32768;
        directed[7] = 16'd65535;
        for (a_index = 0; a_index < 8; a_index = a_index + 1)
            for (b_index = 0; b_index < 8; b_index = b_index + 1)
                check(2'b10, 1'b1, directed[a_index], directed[b_index]);
        for (a_index = 0; a_index < 1024; a_index = a_index + 1) begin
            random_a = $random(seed);
            random_b = $random(seed);
            check(2'b10, 1'b1, random_a, random_b);
        end

        // Activate one nonzero chunk pair at a time, covering all 16 tiles.
        for (row_index = 0; row_index < 4; row_index = row_index + 1)
            for (column_index = 0; column_index < 4; column_index = column_index + 1)
                check(2'b10, 1'b1, 16'd15 << (4*row_index),
                      16'd15 << (4*column_index));

        // Disable, reserved mode, unused upper bits and unknown input isolation.
        for (mode_index = 0; mode_index < 4; mode_index = mode_index + 1)
            check(mode_index[1:0], 1'b0, 16'hffff, 16'hffff);
        check(2'b11, 1'b1, 16'hffff, 16'hffff);
        check(2'b10, 1'b0, 16'hxxxx, 16'hzzzz);
        check(2'b00, 1'b1, 16'hfff3, 16'haaa2);
        check(2'b01, 1'b1, 16'hff13, 16'haa12);

        $display("ALL %0d TILE PRODUCT BANK TESTS PASSED (HSM AND BASIC)", checks);
        $finish;
    end
endmodule
