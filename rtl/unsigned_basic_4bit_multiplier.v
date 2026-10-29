// Combinational unsigned 4-bit x 4-bit multiplier.
// Each input ranges from 0 to 15; the product ranges from 0 to 225.
module basic_unsigned_4x4 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output wire [7:0] product
);

    // Eight output bits retain the complete multiplication result.
    // No clock or registers: the output depends on the current inputs.
    assign product = a * b;

endmodule
