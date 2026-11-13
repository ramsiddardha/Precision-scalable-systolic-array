// One unsigned 4x4 tile with input operand isolation.
module tile4_unsigned (
    input  wire       enable,
    input  wire [3:0] a_chunk,
    input  wire [3:0] b_chunk,
    output wire [7:0] product
);

    // These wires connect the input selectors to the multiplier.
    wire [3:0] a_isolated;
    wire [3:0] b_isolated;

    // Enabled: pass both chunks through to the multiplier.
    // Disabled: hold both multiplier inputs at zero.
    // Changes on a_chunk/b_chunk then do not propagate into the core.
    assign a_isolated = enable ? a_chunk : 4'd0;
    assign b_isolated = enable ? b_chunk : 4'd0;

    // Every enabled tile uses the supplied Wallace compression/prefix core.
    wallace_unsigned_4x4 multiplier (
        .a(a_isolated),
        .b(b_isolated),
        .product(product)
    );

endmodule
