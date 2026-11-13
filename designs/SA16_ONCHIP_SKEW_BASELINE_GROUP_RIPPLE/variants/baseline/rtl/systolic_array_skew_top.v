`timescale 1ns/1ps

// On each input_ready edge, the source supplies A[:,k] and B[k,:] together.
// The controller consumes k=0..15 on the first sixteen enabled RUN edges.
module systolic_array_skew_top (
    input wire clk, rst_n, start, step_enable,
    input wire [1:0] mode,
    input wire [255:0] a_vector, b_vector,
    output wire start_ready, start_accepted, input_ready, busy, done, error,
    output wire [9215:0] result_data_flat,
    output wire [255:0] result_valid_flat
);
    wire mesh_clear, mesh_advance, feed_active, mesh_all_done, mesh_any_error;
    wire [1:0] mode_q;
    wire [5:0] compute_step;
    wire [255:0] a_west_flat, b_north_flat;
    wire [15:0] lane_valid;

    assign input_ready = feed_active && compute_step < 6'd16;

    systolic_mesh_controller controller (
        .clk(clk), .rst_n(rst_n), .start(start), .step_enable(step_enable), .mode(mode),
        .mesh_all_done(mesh_all_done), .mesh_any_error(mesh_any_error),
        .start_ready(start_ready), .start_accepted(start_accepted), .busy(busy),
        .done(done), .error(error), .mode_q(mode_q), .mesh_clear(mesh_clear),
        .mesh_advance(mesh_advance), .feed_active(feed_active), .compute_step(compute_step)
    );

    sa_input_skewer skewer (
        .clk(clk), .rst_n(rst_n), .clear(mesh_clear), .advance(feed_active),
        .input_valid(input_ready), .a_vector(a_vector), .b_vector(b_vector),
        .a_west_flat(a_west_flat), .b_north_flat(b_north_flat), .lane_valid(lane_valid)
    );

    systolic_mesh_16x16 mesh (
        .clk(clk), .rst_n(rst_n), .clear(mesh_clear), .advance(mesh_advance), .mode(mode_q),
        .a_west_flat(a_west_flat), .b_north_flat(b_north_flat),
        .a_valid_west(lane_valid), .b_valid_north(lane_valid),
        .a_east_flat(), .b_south_flat(), .a_valid_east(), .b_valid_south(),
        .result_data_flat(result_data_flat), .result_valid_flat(result_valid_flat),
        .error_flat(), .all_done(mesh_all_done), .any_error(mesh_any_error)
    );
endmodule
