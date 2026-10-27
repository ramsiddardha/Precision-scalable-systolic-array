`timescale 1ns/1ps

// Check the same input isolation contract for both tile architectures.
module tile4_unsigned_tb;
    reg enable;
    reg [3:0] a_chunk, b_chunk;
    wire [7:0] hsm_product, basic_product;
    integer a_index, b_index, enable_index;
    integer checks = 0;

    tile4_unsigned #(.USE_HSM(1)) dut_hsm (
        .enable(enable), .a_chunk(a_chunk), .b_chunk(b_chunk),
        .product(hsm_product)
    );

    tile4_unsigned #(.USE_HSM(0)) dut_basic (
        .enable(enable), .a_chunk(a_chunk), .b_chunk(b_chunk),
        .product(basic_product)
    );

    task check_outputs;
        input selected_enable;
        input [3:0] selected_a, selected_b;
        integer expected_product;
        integer repeat_index;
        reg [3:0] expected_a, expected_b;
        begin
            enable = selected_enable;
            a_chunk = selected_a;
            b_chunk = selected_b;
            #10;

            // Repeated addition is an independent multiplication oracle.
            // When disabled, the expected result and core inputs are zero.
            expected_product = 0;
            expected_a = 4'd0;
            expected_b = 4'd0;
            if (selected_enable) begin
                expected_a = selected_a;
                expected_b = selected_b;
                for (repeat_index = 0; repeat_index < selected_b;
                     repeat_index = repeat_index + 1)
                    expected_product = expected_product + selected_a;
            end

            if (hsm_product !== expected_product[7:0] ||
                basic_product !== expected_product[7:0])
                $fatal(1, "Product mismatch: enable=%b a=%h b=%h expected=%0d HSM=%h BASIC=%h",
                       enable, a_chunk, b_chunk, expected_product,
                       hsm_product, basic_product);

            // Check isolation itself, rather than only observing a zero output.
            if (dut_hsm.a_isolated !== expected_a ||
                dut_hsm.b_isolated !== expected_b ||
                dut_basic.a_isolated !== expected_a ||
                dut_basic.b_isolated !== expected_b)
                $fatal(1, "Multiplier inputs are not isolated correctly");

            checks = checks + 1;
        end
    endtask

    initial begin
        // All 256 operand pairs in both enabled and disabled states.
        for (enable_index = 0; enable_index < 2; enable_index = enable_index + 1)
            for (a_index = 0; a_index < 16; a_index = a_index + 1)
                for (b_index = 0; b_index < 16; b_index = b_index + 1)
                    check_outputs(enable_index[0], a_index[3:0], b_index[3:0]);

        // Disabled input selectors must also block unknown incoming bits.
        check_outputs(1'b0, 4'bxxxx, 4'bzzzz);

        $display("ALL %0d TILE WRAPPER TESTS PASSED (HSM AND BASIC)", checks);
        $finish;
    end
endmodule
