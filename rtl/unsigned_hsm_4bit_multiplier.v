// Unsigned 4-bit x 4-bit HSM multiplier.
// Same external interface as basic_unsigned_4x4: a, b and product.
// This file includes both helper modules, so it has no extra RTL dependencies.
module hsm_unsigned_4x4 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output wire [7:0] product
);
    wire [4:0] sum_ab;
    wire [3:0] absolute_difference;
    wire [3:0] p, q;
    wire [7:0] p_squared, q_squared;
    wire [3:0] minimum_ab, correction;
    wire different_parity;
    wire [7:0] square_difference;

    // The sum needs five bits: 15 + 15 = 30.
    // Extend each input before addition so no carry is lost.
    assign sum_ab = {1'b0, a} + {1'b0, b};

    // Subtract the smaller operand from the larger one.
    // This keeps the difference nonnegative and within four bits.
    assign absolute_difference = (a >= b) ? (a - b) : (b - a);

    // Discard the least significant bit to divide by two and round down.
    // p = floor((a+b)/2); q = floor(abs(a-b)/2).
    assign p = sum_ab[4:1];
    assign q = {1'b0, absolute_difference[3:1]};

    // Two separate combinational squarers operate in parallel.
    // Their implementation below uses small square ROMs and a 2x2 cross term.
    hsm4_square_4bit square_p (.value(p), .square(p_squared));
    hsm4_square_4bit square_q (.value(q), .square(q_squared));

    // The low bit tells us whether an unsigned number is odd or even.
    // Different parity requires a correction equal to min(a,b).
    assign different_parity = a[0] ^ b[0];
    assign minimum_ab = (a <= b) ? a : b;
    assign correction = different_parity ? minimum_ab : 4'd0;

    // HSM identity: a*b = p^2 - q^2 + correction.
    // p >= q, so the square difference is nonnegative.
    // The final result is at most 225 and fits in eight bits.
    assign square_difference = p_squared - q_squared;
    assign product = square_difference + {4'b0000, correction};
endmodule


// Build the square of a four-bit unsigned number from smaller operations.
// value = 4*k + r, where k and r are each two bits.
// value^2 = 16*k^2 + 8*k*r + r^2.
module hsm4_square_4bit (
    input  wire [3:0] value,
    output wire [7:0] square
);
    wire [1:0] k, r;
    wire [3:0] k_squared, r_squared;
    wire [3:0] kr;
    wire [7:0] upper_term, cross_term, lower_term;

    // Separate the upper and lower two-bit fields.
    assign k = value[3:2];
    assign r = value[1:0];

    hsm4_rom_square_2bit square_k (.value(k), .square(k_squared));
    hsm4_rom_square_2bit square_r (.value(r), .square(r_squared));

    // Only this small 2-bit x 2-bit multiplication uses '*'.
    // Its maximum value is 3*3 = 9, which needs four bits.
    assign kr = k * r;

    // Concatenation implements fixed bit placement, with eight-bit terms.
    // Append four zeros for x16, or three zeros for x8.
    assign upper_term = {k_squared, 4'b0000};
    assign cross_term = {1'b0, kr, 3'b000};
    assign lower_term = {4'b0000, r_squared};

    assign square = upper_term + cross_term + lower_term;
endmodule


// Four-entry combinational lookup table for 0^2, 1^2, 2^2 and 3^2.
// This is ROM-style RTL; Genus can map it into ordinary logic gates.
// There is no clock, stored state or required physical memory macro.
module hsm4_rom_square_2bit (
    input  wire [1:0] value,
    output reg  [3:0] square
);
    always @* begin
        case (value)
            2'd0: square = 4'd0;
            2'd1: square = 4'd1;
            2'd2: square = 4'd4;
            2'd3: square = 4'd9;
            default: square = 4'd0;
        endcase
    end
endmodule
