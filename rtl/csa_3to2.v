// One combinational 3-to-2 carry-save adder for unsigned 32-bit vectors.
// The aligned tile products will occupy positions within a 32-bit product.
module csa_3to2 (
    input  wire [31:0] x,
    input  wire [31:0] y,
    input  wire [31:0] z,
    output wire [31:0] sum,
    output wire [31:0] carry
);

    // Each bit position operates independently, like one full adder.
    // XOR gives the sum bit: 1 when one or three input bits are 1.
    assign sum = x ^ y ^ z;

    // A carry is generated when at least two input bits are 1.
    // This carry vector is UNSHIFTED: carry[i] has weight 2^(i+1).
    assign carry = (x & y) | (y & z) | (z & x);

    // Exact identity: x + y + z = sum + 2*carry.
    // The receiving stage shifts carry left by one and preserves its top bit.
    // General three-input totals may need 34 bits; do not truncate them.
endmodule
