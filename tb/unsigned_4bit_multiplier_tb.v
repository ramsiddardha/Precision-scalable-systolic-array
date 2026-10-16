`timescale 1ns/1ps

// Simulation testbench: compare the BASIC and HSM unsigned 4x4 tiles.
// Both designs receive the same inputs and must match the expected product.
// This file is for simulation only; do not synthesize it in Genus.
module unsigned_4x4_compare_tb;
    // The testbench drives a and b; each multiplier drives its own output.
    reg [3:0] a;
    reg [3:0] b;
    wire [7:0] product_basic;
    wire [7:0] product_hsm;

    integer i, j;
    integer expected;
    integer checks;
    integer errors;

    // Two alternative circuits connected to the SAME input signals.
    basic_unsigned_4x4 dut_basic (
        .a(a),
        .b(b),
        .product(product_basic)
    );

    hsm_unsigned_4x4 dut_hsm (
        .a(a),
        .b(b),
        .product(product_hsm)
    );

    initial begin
        a = 0;
        b = 0;
        checks = 0;
        errors = 0;

        // Try every pair: A = 0..15 and B = 0..15, giving 256 cases.
        // The expected answer uses repeated addition, independently of
        // BASIC's '*' operator and HSM's square-based arithmetic.
        for (i = 0; i < 16; i = i + 1) begin
            expected = 0;
            for (j = 0; j < 16; j = j + 1) begin
                a = i[3:0];
                b = j[3:0];

                // Allow the combinational simulation to settle.
                // This wait does not measure the physical circuit delay.
                #1;

                // Check EACH design against the mathematical expectation.
                // !== also catches unknown (X) or high-impedance (Z) bits.
                if (product_basic !== expected[7:0] ||
                    product_hsm !== expected[7:0]) begin
                    $display("FAIL: A=%0d B=%0d expected=%0d BASIC=%0d HSM=%0d",
                             a, b, expected, product_basic, product_hsm);
                    errors = errors + 1;
                end
                checks = checks + 1;

                // For the same A, the next B increases A*B by A.
                // Thus expectations are 0, A, 2A, ... up to 15A.
                expected = expected + i;
            end
        end

        if (errors != 0)
            $fatal(1, "FAIL: %0d mismatching cases out of %0d.", errors, checks);

        $display("PASS: all %0d input pairs matched for BASIC and HSM.", checks);
        $finish;
    end
endmodule
