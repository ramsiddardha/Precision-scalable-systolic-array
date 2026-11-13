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
    // Split the low 12 bits into eight data bits and a four-bit upper field.
    // In INT4 the upper field changes only on an 8-bit carry/borrow event.
    reg [7:0] low_data_q;
    reg [3:0] low_guard_q;
    wire [11:0] low_q = {low_guard_q, low_data_q};
    reg [7:0] mid_q;
    reg [15:0] high_q;
    wire product_mode_valid;
    wire operation_allowed;
    wire consume;
    wire signed [35:0] next_sum;
    wire carry_out_8, write_low_guard;
    wire signed [35:0] stored_sum = {high_q, mid_q, low_q};

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

    precision_accumulator_adder #(.RAW_RESULT(1)) adder (
        .enable(consume), .mode(product_mode), .acc_in(stored_sum),
        .product_in(product_in), .sum_out(next_sum), .carry_out_8(carry_out_8)
    );

    wire clk_low, clk_guard, clk_mid, clk_high, clk_meta;

    // For signed INT4 products the upper product nibble is all sign bits.
    // high_next = high_now + carry8 - sign8 (modulo 16). If carry8 equals
    // sign8 the nibble is unchanged, so its clock can stay closed.
    // INT8/INT16 still update this nibble for every consumed product.
    assign write_low_guard = consume && ((product_mode != 2'b00) ||
                                        (carry_out_8 ^ product_in[7]));

    // Only a legal consumed product needs a data-bank clock. The metadata
    // clock also opens for rejected products to retain protocol diagnostics.
    precision_icg icg_low (.clk(clk), .enable(clear || consume),
        .test_enable(1'b0), .gclk(clk_low));
    precision_icg icg_guard (.clk(clk), .enable(clear || write_low_guard),
        .test_enable(1'b0), .gclk(clk_guard));
    precision_icg icg_mid (.clk(clk),
        .enable(clear || (consume && ((product_mode == 2'b01) || (product_mode == 2'b10)))),
        .test_enable(1'b0), .gclk(clk_mid));
    precision_icg icg_high (.clk(clk),
        .enable(clear || (consume && (product_mode == 2'b10))),
        .test_enable(1'b0), .gclk(clk_high));
    precision_icg icg_meta (.clk(clk), .enable(clear || (advance && product_valid)),
        .test_enable(1'b0), .gclk(clk_meta));

    // Active accumulation widths remain 12/20/36 bits. Clear clocks all banks;
    // asynchronous reset clears them without needing a gated clock pulse.
    always @(posedge clk_low or negedge rst_n) begin
        if (!rst_n) low_data_q <= 8'd0;
        else if (clear) low_data_q <= 8'd0;
        else if (consume) low_data_q <= next_sum[7:0];
    end
    always @(posedge clk_guard or negedge rst_n) begin
        if (!rst_n) low_guard_q <= 4'd0;
        else if (clear) low_guard_q <= 4'd0;
        else if (write_low_guard) low_guard_q <= next_sum[11:8];
    end
    always @(posedge clk_mid or negedge rst_n) begin
        if (!rst_n) mid_q <= 8'd0;
        else if (clear) mid_q <= 8'd0;
        else if (consume && ((product_mode == 2'b01) || (product_mode == 2'b10)))
            mid_q <= next_sum[19:12];
    end
    always @(posedge clk_high or negedge rst_n) begin
        if (!rst_n) high_q <= 16'd0;
        else if (clear) high_q <= 16'd0;
        else if (consume && (product_mode == 2'b10)) high_q <= next_sum[35:20];
    end

    // Count, completion and precision change on the same accepted term as
    // before; an invalid precision or extra term still sets the sticky error.
    always @(posedge clk_meta or negedge rst_n) begin
        if (!rst_n) begin
            acc_mode_q <= 2'b00;
            term_count <= 5'd0;
            result_valid <= 1'b0;
            protocol_error <= 1'b0;
        end else if (clear) begin
            acc_mode_q <= 2'b00;
            term_count <= 5'd0;
            result_valid <= 1'b0;
            protocol_error <= 1'b0;
        end else if (advance && product_valid) begin
            if (operation_allowed) begin
                acc_mode_q <= product_mode;
                term_count <= term_count + 5'd1;
                result_valid <= (term_count == 5'd15);
            end else begin
                protocol_error <= 1'b1;
            end
        end
    end

    // Only the external result is sign-extended. Internal feedback uses the
    // stored banks directly, before the output-format mux. The CLA isolation
    // masks stale upper storage in narrow modes. Clear/reset zero every bank.
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
