`timescale 1ns/1ps

// Three unsigned input rows become two output rows.
// Exact identity: x + y + z = sum + (carry shifted left by 1).
// carry is UNSHIFTED here; align it when connecting the next stage.
module csa_3to2 #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] x,
    input  wire [WIDTH-1:0] y,
    input  wire [WIDTH-1:0] z,
    output wire [WIDTH-1:0] sum,
    output wire [WIDTH-1:0] carry
);

    // XOR gives the sum bit for each column.
    assign sum = x ^ y ^ z;

    // A column produces a carry when at least two input bits are 1.
    assign carry = (x & y) | (x & z) | (y & z);

endmodule
