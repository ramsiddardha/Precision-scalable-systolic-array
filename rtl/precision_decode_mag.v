`timescale 1ns/1ps

// STEP 1: interpret the selected signed fields before using unsigned tiles.
// This is combinational logic: it has no clock, storage, or multiplier.
// Both the BASIC and HSM tile implementations will share this decoder.
// mode 00 = INT4, 01 = INT8, 10 = INT16, 11 = reserved/inactive.
module precision_decode_mag (
    // A and B always arrive on 16-bit buses; mode selects their useful bits.
    input  wire [1:0]  mode,
    input  wire [15:0] a_in,
    input  wire [15:0] b_in,

    // Magnitudes are UNSIGNED, so 32768 can represent abs(-32768).
    output wire [15:0] a_mag,
    output wire [15:0] b_mag,
    output wire        product_negative,
    output reg         mode_valid
);
    // These signed temporary signals hold the interpreted operand values.
    // "reg" permits assignment inside always; it does not imply a register.
    reg signed [15:0] a_value;
    reg signed [15:0] b_value;

    // Recalculate whenever a signal read inside this block changes.
    // Defaults assign every output path and prevent inferred latches.
    always @* begin
        a_value = 16'sd0;
        b_value = 16'sd0;
        mode_valid = 1'b1;

        case (mode)
            2'b00: begin
                // Select bits 3:0 and repeat bit 3 to sign-extend to 16 bits.
                // Example: low nibble 1101 means -3, even if upper bits vary.
                a_value = {{12{a_in[3]}}, a_in[3:0]};
                b_value = {{12{b_in[3]}}, b_in[3:0]};
            end
            2'b01: begin
                // Select bits 7:0; bit 7 is the INT8 sign bit.
                a_value = {{8{a_in[7]}}, a_in[7:0]};
                b_value = {{8{b_in[7]}}, b_in[7:0]};
            end
            2'b10: begin
                // INT16 uses the complete input word; bit 15 is its sign bit.
                a_value = a_in;
                b_value = b_in;
            end
            default: begin
                // Reserved mode keeps both default operand values at zero.
                // Later control logic will also disable the multiplier tiles.
                mode_valid = 1'b0;
            end
        endcase
    end

    // For a negative operand, invert all 16 bits and add one to obtain abs().
    // Keep the result unsigned: -8 -> 8, -128 -> 128, -32768 -> 32768.
    assign a_mag = a_value[15] ? (~a_value + 16'd1) : a_value;
    assign b_mag = b_value[15] ? (~b_value + 16'd1) : b_value;

    // Remember whether the operand signs differ, using XOR (^).
    // Later we negate the full magnitude product when this flag is one.
    // A zero product remains zero even if this sign-restoration flag is one.
    assign product_negative = mode_valid && (a_value[15] ^ b_value[15]);
endmodule
