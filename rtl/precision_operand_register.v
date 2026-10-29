`timescale 1ns/1ps

// One registered systolic operand hop. Instantiate once for A and once for B.
// INT4 writes four data bits, INT8 eight, and INT16 all sixteen data bits.
// The common output bus reconstructs the selected signed value. Latch-based
// clock gating stops unused register-bank clocks; this is not power gating.
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

    wire valid_mode;
    wire write_operand;
    wire clk_low, clk_mid, clk_high, clk_meta;

    // Reject reserved/X precision just as the original case statement did.
    function mode_is_valid;
        input [1:0] selected_mode;
        begin
            case (selected_mode)
                2'b00, 2'b01, 2'b10: mode_is_valid = 1'b1;
                default: mode_is_valid = 1'b0;
            endcase
        end
    endfunction
    assign valid_mode = mode_is_valid(mode);
    assign write_operand = advance && in_valid && valid_mode;

    // Clear reaches every bank even during a stall. Metadata also clocks on
    // bubbles so valid clears; only an accepted operand/product updates data.
    precision_icg icg_low (.clk(clk), .enable(clear || write_operand),
        .test_enable(1'b0), .gclk(clk_low));
    precision_icg icg_mid (.clk(clk),
        .enable(clear || (write_operand && ((mode == 2'b01) || (mode == 2'b10)))),
        .test_enable(1'b0), .gclk(clk_mid));
    precision_icg icg_high (.clk(clk), .enable(clear || (write_operand && (mode == 2'b10))),
        .test_enable(1'b0), .gclk(clk_high));
    precision_icg icg_meta (.clk(clk), .enable(clear || advance),
        .test_enable(1'b0), .gclk(clk_meta));

    // Separate gated clocks stop the unused data-bank clock pins toggling.
    // Every storage bank still resets directly when rst_n falls.
    always @(posedge clk_low or negedge rst_n) begin
        if (!rst_n) low_q <= 4'd0;
        else if (clear) low_q <= 4'd0;
        else if (write_operand) low_q <= data_in[3:0];
    end
    always @(posedge clk_mid or negedge rst_n) begin
        if (!rst_n) mid_q <= 4'd0;
        else if (clear) mid_q <= 4'd0;
        else if (write_operand && ((mode == 2'b01) || (mode == 2'b10)))
            mid_q <= data_in[7:4];
    end
    always @(posedge clk_high or negedge rst_n) begin
        if (!rst_n) high_q <= 8'd0;
        else if (clear) high_q <= 8'd0;
        else if (write_operand && (mode == 2'b10)) high_q <= data_in[15:8];
    end

    // Precision travels with the data; stalls hold both mode and valid.
    always @(posedge clk_meta or negedge rst_n) begin
        if (!rst_n) begin
            mode_q <= 2'b00;
            valid_q <= 1'b0;
        end else if (clear) begin
            mode_q <= 2'b00;
            valid_q <= 1'b0;
        end else if (advance) begin
            valid_q <= 1'b0;
            if (write_operand) begin
                mode_q <= mode;
                valid_q <= 1'b1;
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
