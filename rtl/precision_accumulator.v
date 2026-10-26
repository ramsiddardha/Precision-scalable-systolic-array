`timescale 1ns/1ps

// Accumulate up to sixteen products of one precision, starting from zero.
// One shared state bank has 12 + 8 + 16 separately enabled data bits.
// clear starts a new dot product; precision stays fixed until clear/reset.
module precision_accumulator (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               clear,
    input  wire               advance,
    input  wire               product_valid,
    input  wire [1:0]         product_mode,
    input  wire signed [31:0] product_in,
    output reg  signed [35:0] acc_q,
    output reg  [1:0]         acc_mode_q,
    output reg  [4:0]         term_count,
    output reg                result_valid,
    output reg                protocol_error
);
    reg [11:0] low_q;
    reg [7:0] mid_q;
    reg [15:0] high_q;
    wire product_mode_valid;
    wire operation_allowed;
    wire consume;
    wire signed [35:0] next_sum;

    // A continuous function decode is evaluated even if mode stays constant
    // from time zero. case/default rejects reserved and unknown mode patterns.
    function mode_is_valid;
        input [1:0] selected_mode;
        begin
            case (selected_mode)
                2'b00, 2'b01, 2'b10: mode_is_valid = 1'b1;
                default: mode_is_valid = 1'b0;
            endcase
        end
    endfunction
    assign product_mode_valid = mode_is_valid(product_mode);

    // The first consumed product establishes the precision of this dot product.
    // Later products must match it, and a seventeenth product is rejected.
    assign operation_allowed = product_mode_valid && (term_count < 5'd16) &&
                               ((term_count == 5'd0) || (product_mode == acc_mode_q));
    assign consume = rst_n && !clear && advance && product_valid && operation_allowed;

    precision_accumulator_adder adder (
        .enable(consume), .mode(product_mode), .acc_in(acc_q),
        .product_in(product_in), .sum_out(next_sum)
    );

    // Both state and metadata share reset, clear and pipeline-stall semantics.
    // Reset asserts asynchronously; its release is conditioned by the system.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            low_q          <= 12'd0;
            mid_q          <= 8'd0;
            high_q         <= 16'd0;
            acc_mode_q     <= 2'b00;
            term_count     <= 5'd0;
            result_valid   <= 1'b0;
            protocol_error <= 1'b0;
        end else if (clear) begin
            low_q          <= 12'd0;
            mid_q          <= 8'd0;
            high_q         <= 16'd0;
            acc_mode_q     <= 2'b00;
            term_count     <= 5'd0;
            result_valid   <= 1'b0;
            protocol_error <= 1'b0;
        end else if (advance && product_valid) begin
            if (operation_allowed) begin
                low_q <= next_sum[11:0];
                if ((product_mode == 2'b01) || (product_mode == 2'b10))
                    mid_q <= next_sum[19:12];
                if (product_mode == 2'b10)
                    high_q <= next_sum[35:20];

                acc_mode_q   <= product_mode;
                term_count   <= term_count + 5'd1;
                result_valid <= (term_count == 5'd15);
            end else begin
                // A rejected product does not change the sum or count.
                // This sticky diagnostic clears only with clear/reset.
                protocol_error <= 1'b1;
            end
        end
        // Stalls and bubbles retain the running sum, count and completion flag.
    end

    // Reconstruct the active signed accumulator width; upper stored bits hold.
    // The zero-term state is explicitly zero before a precision is established.
    always @* begin
        acc_q = 36'sd0;
        if (term_count != 5'd0) begin
            case (acc_mode_q)
                2'b00: acc_q = {{24{low_q[11]}}, low_q};
                2'b01: acc_q = {{16{mid_q[7]}}, mid_q, low_q};
                2'b10: acc_q = {high_q, mid_q, low_q};
                default: acc_q = 36'sd0;
            endcase
        end
    end
endmodule
