`timescale 1ns/1ps

// Test the final adder separately and after both complete unsigned bank/tree paths.
// Wide arithmetic provides an independent reference for the active product width.
module precision_final_adder_tb;
    reg [1:0] mode;
    reg enable;
    reg [31:0] csa_sum, csa_carry;
    wire [31:0] magnitude_product;
    integer adder_checks = 0;
    integer bank_checks = 0;
    integer i, j, k;
    integer seed = 32'h72513abc;
    reg [31:0] random_word, generated_carry, generated_sum;
    reg [63:0] remaining;
    reg [15:0] boundary [0:7];

    reg [1:0] bank_mode;
    reg bank_enable;
    reg [15:0] a_mag, b_mag;
    wire [511:0] hsm_rows, basic_rows;
    wire [15:0] hsm_enabled, basic_enabled;
    wire [31:0] hsm_sum, hsm_carry, basic_sum, basic_carry;
    wire [31:0] hsm_product, basic_product;

    precision_final_adder dut (
        .mode(mode), .enable(enable), .csa_sum(csa_sum), .csa_carry(csa_carry),
        .magnitude_product(magnitude_product)
    );
    tile_product_bank #(.USE_HSM(1)) bank_hsm (
        .mode(bank_mode), .enable(bank_enable), .a_mag(a_mag), .b_mag(b_mag),
        .tile_enabled(hsm_enabled), .partial_products(hsm_rows)
    );
    tile_product_bank #(.USE_HSM(0)) bank_basic (
        .mode(bank_mode), .enable(bank_enable), .a_mag(a_mag), .b_mag(b_mag),
        .tile_enabled(basic_enabled), .partial_products(basic_rows)
    );
    csa_tree_16x32 tree_hsm (
        .mode(bank_mode), .enable(bank_enable), .partial_products(hsm_rows),
        .sum(hsm_sum), .carry(hsm_carry)
    );
    csa_tree_16x32 tree_basic (
        .mode(bank_mode), .enable(bank_enable), .partial_products(basic_rows),
        .sum(basic_sum), .carry(basic_carry)
    );
    precision_final_adder adder_hsm (
        .mode(bank_mode), .enable(bank_enable), .csa_sum(hsm_sum), .csa_carry(hsm_carry),
        .magnitude_product(hsm_product)
    );
    precision_final_adder adder_basic (
        .mode(bank_mode), .enable(bank_enable), .csa_sum(basic_sum), .csa_carry(basic_carry),
        .magnitude_product(basic_product)
    );

    task check_adder;
        input [1:0] selected_mode;
        input selected_enable;
        input [31:0] selected_sum, selected_carry;
        reg [63:0] expected;
        reg expected_low_enable, expected_high_enable;
        begin
            mode = selected_mode;
            enable = selected_enable;
            csa_sum = selected_sum;
            csa_carry = selected_carry;
            #1;
            expected = 0;
            expected_low_enable = selected_enable &&
                                  ((selected_mode == 2'b01) || (selected_mode == 2'b10));
            expected_high_enable = selected_enable && (selected_mode == 2'b10);
            if (selected_enable) begin
                case (selected_mode)
                    2'b00: expected = {56'd0, selected_sum[7:0]};
                    2'b01: begin
                        expected = {48'd0, selected_sum[15:0]} +
                                   ({48'd0, selected_carry[15:0]} << 1);
                        if (expected > 64'hffff)
                            $fatal(1, "Invalid test: INT8 result must fit in 16 bits");
                    end
                    2'b10: begin
                        expected = {32'd0, selected_sum} + ({32'd0, selected_carry} << 1);
                        if (expected > 64'hffffffff)
                            $fatal(1, "Invalid test: INT16 result must fit in 32 bits");
                    end
                    default: expected = 0;
                endcase
            end
            if (magnitude_product !== expected[31:0])
                $fatal(1, "Adder mismatch case=%0d mode=%b enable=%b S=%h C=%h expected=%h result=%h",
                       adder_checks, mode, enable, csa_sum, csa_carry,
                       expected[31:0], magnitude_product);
            if (dut.low_enable !== expected_low_enable ||
                dut.high_enable !== expected_high_enable)
                $fatal(1, "Adder section enable mismatch");
            if (!expected_low_enable && {dut.low_a, dut.low_b} !== 32'd0)
                $fatal(1, "Inactive lower-section operands are not isolated");
            if (!expected_high_enable && {dut.high_a, dut.high_b, dut.high_cin} !== 33'd0)
                $fatal(1, "Inactive upper-section operands/carry are not isolated");
            adder_checks = adder_checks + 1;
        end
    endtask

    task check_bank;
        input [1:0] selected_mode;
        input selected_enable;
        input [15:0] selected_a, selected_b;
        reg [63:0] reference_a, reference_b, expected;
        begin
            bank_mode = selected_mode;
            bank_enable = selected_enable;
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
            if (hsm_product !== expected[31:0] || basic_product !== expected[31:0])
                $fatal(1, "Unsigned path mismatch case=%0d mode=%b A=%h B=%h expected=%h HSM=%h BASIC=%h",
                       bank_checks, bank_mode, a_mag, b_mag,
                       expected[31:0], hsm_product, basic_product);
            if (!(selected_enable && selected_mode == 2'b10)) begin
                if ({adder_hsm.high_a, adder_hsm.high_b, adder_hsm.high_cin,
                     adder_basic.high_a, adder_basic.high_b, adder_basic.high_cin} !== 66'd0)
                    $fatal(1, "Inactive upper sections are not isolated in the full path");
            end
            bank_checks = bank_checks + 1;
        end
    endtask

    initial begin
        mode = 2'b11;
        enable = 0;
        csa_sum = 0;
        csa_carry = 0;
        bank_mode = 2'b11;
        bank_enable = 0;
        a_mag = 0;
        b_mag = 0;

        // INT4 bypass: all possible eight-bit fields, even with carry noise.
        for (i = 0; i < 256; i = i + 1)
            check_adder(2'b00, 1'b1, i[31:0], 32'hffffffff);
        check_adder(2'b00, 1'b1, {24'hxxxxxx, 8'he1}, 32'hxxxxxxxx);

        // INT8 uses only a sixteen-bit product and ignores upper-field noise.
        check_adder(2'b01, 1'b1, 32'd0, 32'd0);
        check_adder(2'b01, 1'b1, 32'hffff, 32'd0);
        check_adder(2'b01, 1'b1, 32'd1, 32'h7fff);
        check_adder(2'b01, 1'b1, 32'hfff0, 32'd7);
        check_adder(2'b01, 1'b1, 32'h0101, 32'h007f);
        check_adder(2'b01, 1'b1, 32'hffff1234, 32'hffff0067);
        check_adder(2'b01, 1'b1, {16'hxxxx, 16'h1234}, {16'hxxxx, 16'h0067});

        // INT16 includes carry transfer across the two sixteen-bit sections.
        check_adder(2'b10, 1'b1, 32'd0, 32'd0);
        check_adder(2'b10, 1'b1, 32'hffffffff, 32'd0);
        check_adder(2'b10, 1'b1, 32'd1, 32'h7fffffff);
        check_adder(2'b10, 1'b1, 32'h0000ffff, 32'd1);
        check_adder(2'b10, 1'b1, 32'h00008000, 32'h00004000);
        check_adder(2'b10, 1'b1, 32'h80000000, 32'h3fffffff);
        check_adder(2'b10, 1'b1, 32'd0, 32'h40000000);
        check_adder(2'b10, 1'b1, 32'h00ffffff, 32'h7f800000);

        // Generate valid pairs whose exact sum fits the selected product width.
        for (k = 1; k <= 2; k = k + 1)
            for (i = 0; i < 512; i = i + 1) begin
                random_word = $random(seed);
                generated_carry = (k == 1) ? (random_word & 32'h7fff)
                                           : (random_word & 32'h7fffffff);
                remaining = (k == 1) ? 64'hffff : 64'hffffffff;
                remaining = remaining - ({32'd0, generated_carry} << 1);
                random_word = $random(seed);
                generated_sum = {32'd0, random_word} % (remaining + 64'd1);
                check_adder(k[1:0], 1'b1, generated_sum, generated_carry);
            end
        for (k = 0; k < 4; k = k + 1)
            check_adder(k[1:0], 1'b0, 32'hffffffff, 32'hffffffff);
        check_adder(2'b11, 1'b1, 32'hffffffff, 32'hffffffff);
        check_adder(2'b10, 1'b0, 32'hxxxxxxxx, 32'hzzzzzzzz);

        // Integration: exhaustive unsigned nibble and byte input pairs.
        for (i = 0; i < 16; i = i + 1)
            for (j = 0; j < 16; j = j + 1)
                check_bank(2'b00, 1'b1, i[15:0], j[15:0]);
        for (i = 0; i < 256; i = i + 1)
            for (j = 0; j < 256; j = j + 1)
                check_bank(2'b01, 1'b1, i[15:0], j[15:0]);

        // Full-width unsigned boundary products and reproducible random pairs.
        boundary[0] = 16'd0;
        boundary[1] = 16'd1;
        boundary[2] = 16'd15;
        boundary[3] = 16'd16;
        boundary[4] = 16'd255;
        boundary[5] = 16'd256;
        boundary[6] = 16'd32768;
        boundary[7] = 16'd65535;
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                check_bank(2'b10, 1'b1, boundary[i], boundary[j]);
        for (i = 0; i < 2048; i = i + 1) begin
            generated_sum = $random(seed);
            generated_carry = $random(seed);
            check_bank(2'b10, 1'b1, generated_sum[15:0], generated_carry[15:0]);
        end
        for (k = 0; k < 4; k = k + 1)
            check_bank(k[1:0], 1'b0, 16'hffff, 16'hffff);
        check_bank(2'b11, 1'b1, 16'hffff, 16'hffff);
        check_bank(2'b10, 1'b0, 16'hxxxx, 16'hzzzz);

        $display("ALL %0d FINAL ADDER / ISOLATION TESTS PASSED", adder_checks);
        $display("ALL %0d UNSIGNED BANK + CSA + FINAL ADDER TESTS PASSED (HSM AND BASIC)", bank_checks);
        $finish;
    end
endmodule
