`timescale 1ns/1ps

// Delay lane i by i accepted mesh steps. Both operand streams use one valid
// pipeline. Scalar, named stage registers can be recorded directly in a VCD.
module sa_input_skewer (
    input wire clk, rst_n, clear, advance, input_valid,
    input wire [255:0] a_vector, b_vector,
    output wire [255:0] a_west_flat, b_north_flat,
    output wire [15:0] lane_valid
);
    reg [15:1] valid_q;
    wire [15:0] stage_valid = {valid_q, input_valid};
    wire [15:1] stage_clock;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_q <= 15'd0;
        else if (clear)
            valid_q <= 15'd0;
        else if (advance)
            valid_q <= stage_valid[14:0];
    end

    genvar stage, lane, delay;
    generate
        // Every lane that has stage j consumes a vector from the same cycle.
        // Share the gate across those lanes and hold their data on invalid steps.
        for (stage = 1; stage < 16; stage = stage + 1) begin : g_stage_clock
            precision_icg gate (
                .clk(clk), .enable(advance && stage_valid[stage-1]),
                .test_enable(1'b0), .gclk(stage_clock[stage])
            );
        end

        for (lane = 0; lane < 16; lane = lane + 1) begin : g_lane
            wire [16*(lane+1)-1:0] a_path, b_path;
            assign a_path[15:0] = a_vector[16*lane +: 16];
            assign b_path[15:0] = b_vector[16*lane +: 16];

            for (delay = 1; delay <= lane; delay = delay + 1) begin : g_delay
                reg [15:0] a_q, b_q;
                always @(posedge stage_clock[delay] or negedge rst_n) begin
                    if (!rst_n) begin
                        a_q <= 16'd0;
                        b_q <= 16'd0;
                    end else begin
                        a_q <= a_path[16*(delay-1) +: 16];
                        b_q <= b_path[16*(delay-1) +: 16];
                    end
                end
                assign a_path[16*delay +: 16] = a_q;
                assign b_path[16*delay +: 16] = b_q;
            end

            assign lane_valid[lane] = advance && stage_valid[lane];
            assign a_west_flat[16*lane +: 16] = lane_valid[lane] ?
                a_path[16*lane +: 16] : 16'd0;
            assign b_north_flat[16*lane +: 16] = lane_valid[lane] ?
                b_path[16*lane +: 16] : 16'd0;
        end
    endgenerate
endmodule
