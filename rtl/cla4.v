`timescale 1ns/1ps

// Four-bit carry-lookahead adder used by the accumulator's nine-block network.
// Carries inside this block are expanded directly, rather than chained from
// one full-adder instance to the next. There is no clock or storage here.
module cla4 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire       cin,
    output wire [3:0] sum,
    output wire       group_g,
    output wire       group_p
);
    wire [3:0] p, g;
    wire c1, c2, c3;

    // A bit generates a carry when both operands are one. XOR-propagate
    // identifies a bit that passes an incoming carry to the next position.
    assign p = a ^ b;
    assign g = a & b;
    assign c1 = g[0] | (p[0] & cin);
    assign c2 = g[1] | (p[1] & g[0]) | (p[1] & p[0] & cin);
    assign c3 = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) |
                (p[2] & p[1] & p[0] & cin);

    // These summaries depend only on a/b, independently of cin. The prefix
    // network combines them to calculate carries into all nine blocks.
    assign group_g = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) |
                     (p[3] & p[2] & p[1] & g[0]);
    assign group_p = &p;
    assign sum = p ^ {c3, c2, c1, cin};
endmodule
