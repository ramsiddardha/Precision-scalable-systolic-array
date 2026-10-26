`timescale 1ns/1ps

// One registered systolic operand hop. Instantiate once for A and once for B.
// INT4 writes four data bits, INT8 eight, and INT16 all sixteen data bits.
// The common output bus reconstructs the selected signed value. This is ordinary
// register-enable RTL; it does not create a gated clock or a power-gated domain.
module precision_operand_register (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               clear,
    input  wire               advance,
    input  wire               in_valid,
    input  wire [1:0]         mode,
    input  wire [15:0]        data_in,
    output reg  signed [15:0] data_q,
    output reg  [1:0]         mode_q,
    output reg                valid_q
);
    reg [3:0] low_q;
    reg [3:0] mid_q;
    reg [7:0] high_q;

    // Reset asserts immediately; clear starts a new frame at a clock edge.
    // A stall retains data AND metadata. A bubble retains data but clears valid.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            low_q   <= 4'd0;
            mid_q   <= 4'd0;
            high_q  <= 8'd0;
            mode_q  <= 2'b00;
            valid_q <= 1'b0;
        end else if (clear) begin
            low_q   <= 4'd0;
            mid_q   <= 4'd0;
            high_q  <= 8'd0;
            mode_q  <= 2'b00;
            valid_q <= 1'b0;
        end else if (advance) begin
            valid_q <= 1'b0;
            if (in_valid) begin
                case (mode)
                    2'b00, 2'b01, 2'b10: begin
                        low_q <= data_in[3:0];
                        if ((mode == 2'b01) || (mode == 2'b10))
                            mid_q <= data_in[7:4];
                        if (mode == 2'b10)
                            high_q <= data_in[15:8];
                        mode_q  <= mode;
                        valid_q <= 1'b1;
                    end
                    default: begin
                        // Reserved/unknown mode inserts a bubble. The PE parent
                        // also records a protocol error if a valid token had it.
                    end
                endcase
            end
        end
    end

    // Stored precision travels with the operand. Stale upper storage cannot
    // affect a narrow value, and ignored upper input bits may contain X/Z in TB.
    always @* begin
        case (mode_q)
            2'b00: data_q = {{12{low_q[3]}}, low_q};
            2'b01: data_q = {{8{mid_q[3]}}, mid_q, low_q};
            2'b10: data_q = {high_q, mid_q, low_q};
            default: data_q = 16'sd0;
        endcase
    end
endmodule
