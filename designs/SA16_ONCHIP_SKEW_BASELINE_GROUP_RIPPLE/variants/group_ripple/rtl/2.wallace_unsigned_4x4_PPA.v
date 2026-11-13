// Unsigned 4x4 Wallace compression tree with an eight-bit prefix final adder.
// Directly instantiated by every tile; all arithmetic helper modules are below.
module wallace_unsigned_4x4 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output wire [7:0] product
);
    // pp_j[i] has binary weight i+j. These four vectors contain 16 ANDs.
    wire [3:0] pp0, pp1, pp2, pp3;
    assign pp0 = a & {4{b[0]}};
    assign pp1 = a & {4{b[1]}};
    assign pp2 = a & {4{b[2]}};
    assign pp3 = a & {4{b[3]}};

    // A sum stays in its column; a carry moves to the NEXT column.
    wire s1_col2, c1_col2;
    wire s1_col3, c1_col3;
    wire s1_col4, c1_col4;
    wire s2_col3, c2_col3;
    wire s2_col5, c2_col5;
    wire s3_col4, c3_col4;
    wire [7:0] row_a, row_b;

    // Wallace level 1: compress all available triples in columns 2, 3, 4.
    wallace4_full_adder level1_col2 (
        .x(pp0[2]), .y(pp1[1]), .z(pp2[0]),
        .sum(s1_col2), .carry(c1_col2)
    );
    wallace4_full_adder level1_col3 (
        .x(pp0[3]), .y(pp1[2]), .z(pp2[1]),
        .sum(s1_col3), .carry(c1_col3)
    );
    wallace4_full_adder level1_col4 (
        .x(pp1[3]), .y(pp2[2]), .z(pp3[1]),
        .sum(s1_col4), .carry(c1_col4)
    );

    // Wallace level 2: use ONLY outputs from the preceding level.
    wallace4_full_adder level2_col3 (
        .x(s1_col3), .y(c1_col2), .z(pp3[0]),
        .sum(s2_col3), .carry(c2_col3)
    );
    wallace4_full_adder level2_col5 (
        .x(pp2[3]), .y(pp3[2]), .z(c1_col4),
        .sum(s2_col5), .carry(c2_col5)
    );

    // Wallace level 3: the last triple is in column 4.
    wallace4_full_adder level3_col4 (
        .x(s1_col4), .y(c1_col3), .z(c2_col3),
        .sum(s3_col4), .carry(c3_col4)
    );

    // At most two bits remain per column. Carry weights are already aligned.
    assign row_a = {1'b0, pp3[3], s2_col5, s3_col4,
                   s2_col3, s1_col2, pp0[1], pp0[0]};
    assign row_b = {1'b0, c2_col5, c3_col4, 3'b000, pp1[0], 1'b0};

    // Explicit logarithmic carry network, with a zero carry input.
    wallace4_prefix_adder8 final_adder (
        .a(row_a), .b(row_b), .sum(product)
    );
endmodule

module wallace4_full_adder (
    input  wire x,
    input  wire y,
    input  wire z,
    output wire sum,
    output wire carry
);
    assign sum   = x ^ y ^ z;
    assign carry = (x & y) | (x & z) | (y & z);
endmodule

module wallace4_prefix_adder8 (
    input  wire [7:0] a,
    input  wire [7:0] b,
    output wire [7:0] sum
);
    wire [7:0] p0, g0;
    wire [7:0] p1, g1;
    wire [7:0] p2, g2;
    wire [7:0] g4;

    assign p0 = a ^ b;
    assign g0 = a & b;

    // Prefix distances 1, 2, 4. Missing lower groups use G=0, P=1.
    assign g1 = g0 | (p0 & {g0[6:0], 1'b0});
    assign p1 = p0 & {p0[6:0], 1'b1};
    assign g2 = g1 | (p1 & {g1[5:0], 2'b00});
    assign p2 = p1 & {p1[5:0], 2'b11};
    assign g4 = g2 | (p2 & {g2[3:0], 4'b0000});

    // carry[0]=0; carry[i] is the prefix generate through bit i-1.
    assign sum = p0 ^ {g4[6:0], 1'b0};
endmodule