`timescale 1ns/1ps
// Full 16x16 SA around the accepted, unchanged EncodedShared mesh RTL.
// mode: 00 INT4, 01 INT8, 10 INT16, 11 rejected at start.
// Host presents A[row,col] and B[row,col] together in row-major order.
// A start edge accepts no data. The next 256 accepted pairs fill both matrices.
// Then the controller clears the mesh, advances 48 steps, and pulses done.
// No compute stalls. clear aborts a transaction. New start is accepted only idle.
// Result data/valid are the mesh's own outputs. Sample the full matrix on done.
// They may retain the prior matrix during a later load, until the mesh clear.
module systolic_array_power_top #(
    parameter integer AUX_CLOCK_GATING=1
) (
    input wire clk,rst_n,clear,start,
    input wire [1:0] mode,
    input wire input_valid,
    input wire [15:0] a_data,b_data,
    output wire start_ready,input_ready,busy,done,error,
    output wire [9215:0] result_data_flat,
    output wire [255:0] result_valid_flat
);
    wire start_accepted,load_accept,mesh_clear,mesh_advance,feed_active;
    wire [7:0] load_address;
    wire [1:0] mode_q;
    wire [2:0] phase;
    wire [5:0] step_index;
    wire [15:0] read_enable;
    wire [63:0] read_index;
    wire [255:0] a_read_data,b_read_data;
    wire [255:0] mesh_error;
    wire mesh_all_done,mesh_any_error,controller_error;
    assign error=controller_error || ((phase==3'd3 || phase==3'd4) && mesh_any_error);
    sa_controller #(.CLOCK_GATING(AUX_CLOCK_GATING)) controller (
        .clk(clk),.rst_n(rst_n),.clear(clear),.start(start),.mode(mode),
        .input_valid(input_valid),.mesh_all_done(mesh_all_done),.mesh_any_error(mesh_any_error),
        .step_index(step_index),.start_ready(start_ready),.start_accepted(start_accepted),
        .input_ready(input_ready),.load_accept(load_accept),.load_address(load_address),
        .mode_q(mode_q),.mesh_clear(mesh_clear),.mesh_advance(mesh_advance),
        .feed_active(feed_active),.busy(busy),.done(done),.protocol_error(controller_error),.phase(phase));
    sa_parallel_ab_buffers #(.CLOCK_GATING(AUX_CLOCK_GATING)) buffers (
        .clk(clk),.rst_n(rst_n),.write_enable(load_accept),.mode(mode_q),
        .write_address(load_address),.a_data(a_data),.b_data(b_data),
        .read_enable(read_enable),.read_index(read_index),
        .a_read_data(a_read_data),.b_read_data(b_read_data));
    sa_input_sequencer #(.CLOCK_GATING(AUX_CLOCK_GATING)) sequencer (
        .clk(clk),.rst_n(rst_n),.clear(clear),.mesh_clear(mesh_clear),.feed_active(feed_active),
        .step_index(step_index),.read_enable(read_enable),.read_index(read_index));
    systolic_mesh_16x16 mesh (
        .clk(clk),.rst_n(rst_n),.clear(mesh_clear),.advance(mesh_advance),.mode(mode_q),
        .a_west_flat(a_read_data),.b_north_flat(b_read_data),
        .a_valid_west(read_enable),.b_valid_north(read_enable),
        .a_east_flat(),.b_south_flat(),.a_valid_east(),.b_valid_south(),
        .result_data_flat(result_data_flat),.result_valid_flat(result_valid_flat),
        .error_flat(mesh_error),.all_done(mesh_all_done),.any_error(mesh_any_error));
endmodule
