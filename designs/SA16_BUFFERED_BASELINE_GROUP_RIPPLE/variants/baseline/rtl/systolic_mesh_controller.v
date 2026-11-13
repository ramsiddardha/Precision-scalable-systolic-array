`timescale 1ns/1ps

// Compute-only controller: no operand buffers and no hardware input skewer.
// N=16: start edge, one mesh-clear edge, 48 advancing run edges,
// then one check edge. Unpaused operations therefore occupy 51 clock periods
// from the beginning of the start cycle through the end of the check cycle.
// Boundary sources supply the skewed data for the advertised compute_step.
// step_enable pauses the entire mesh and the run counter together.
// done pulses on BOTH successful completion and detected failure; error
// distinguishes failure. Results are usable only after done && !error.
module systolic_mesh_controller #(
    parameter integer N = 16
) (
    input wire clk, rst_n, start, step_enable,
    input wire [1:0] mode,
    input wire mesh_all_done, mesh_any_error,
    output wire start_ready, start_accepted, busy,
    output reg done, error,
    output reg [1:0] mode_q,
    output wire mesh_clear, mesh_advance, feed_active,
    output wire [5:0] compute_step
);
    localparam [1:0] IDLE=2'd0, CLEAR=2'd1, RUN=2'd2, CHECK=2'd3;
    localparam [5:0] LAST_STEP=2*N+15;
    reg [1:0] state;
    reg [5:0] step_q;
    function mode_is_valid;
        input [1:0] selected_mode;
        begin
            case(selected_mode)
                2'b00,2'b01,2'b10: mode_is_valid=1'b1;
                default: mode_is_valid=1'b0;
            endcase
        end
    endfunction
    // Continuous evaluation also covers a mode held at constant INT4 from
    // time zero; a procedural decoder must not depend on an initial toggle.
    wire legal_mode=mode_is_valid(mode);
    assign start_ready = rst_n && (state==IDLE);
    assign start_accepted = start_ready && start && legal_mode;
    assign busy = rst_n && (state!=IDLE);
    assign mesh_clear = rst_n && (state==CLEAR);
    assign feed_active = rst_n && (state==RUN) && step_enable;
    assign mesh_advance = mesh_clear || feed_active;
    assign compute_step = feed_active ? step_q : 6'd0;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; step_q<=0; mode_q<=0; done<=0; error<=0;
        end else begin
            done<=1'b0;
            case(state)
                IDLE: begin
                    if(start_accepted) begin
                        mode_q<=mode;
                        step_q<=0;
                        error<=0;
                        state<=CLEAR;
                    end else if(start && !legal_mode) error<=1'b1;
                end
                CLEAR: state<=RUN;
                RUN: if(step_enable) begin
                    if(step_q==LAST_STEP) state<=CHECK;
                    else step_q<=step_q+6'd1;
                end
                CHECK: begin
                    // The final RUN edge has already updated the PE registers.
                    // Never sample all_done on that same edge and miss its NBA.
                    error<=mesh_any_error || !mesh_all_done;
                    done<=1'b1;
                    state<=IDLE;
                end
                default: begin state<=IDLE; done<=1'b1; error<=1'b1; end
            endcase
        end
    end
endmodule

// Integration top synthesized by the supplied Genus flow.
// The 20 supplied newer PE/mesh RTL files are kept byte-for-byte unchanged.
// The supplied PE default ENCODED_LINKS=1 is used by the unchanged mesh.
// a_east/b_south therefore contain encoded narrow fields, NOT sign-extended
// signed 16-bit values. Final 36-bit matrix results remain signed as before.
// Runtime mode is sampled once on start_accepted and held for the operation.
// Pulse start; requests during busy are ignored. Do not reuse results after
// accepting another start (its following CLEAR edge invalidates the old mesh).
module systolic_mesh_control_top #(
    parameter integer N=16,
    parameter integer PE_CLOCK_GATING=1
) (
    input wire clk, rst_n, start, step_enable,
    input wire [1:0] mode,
    input wire [16*N-1:0] a_west_flat, b_north_flat,
    input wire [N-1:0] a_valid_west, b_valid_north,
    output wire start_ready, start_accepted, busy, done, error,
    output wire [1:0] mode_q,
    output wire feed_active,
    output wire [5:0] compute_step,
    output wire [16*N-1:0] a_east_flat, b_south_flat,
    output wire [N-1:0] a_valid_east, b_valid_south,
    output wire [36*N*N-1:0] result_data_flat,
    output wire [N*N-1:0] result_valid_flat, error_flat,
    output wire all_done, any_error
);
    wire mesh_clear,mesh_advance;
    wire [N-1:0] active_a,active_b;
    wire [16*N-1:0] isolated_a,isolated_b;
    assign active_a=a_valid_west & {N{feed_active}};
    assign active_b=b_valid_north & {N{feed_active}};
    genvar lane;
    generate for(lane=0;lane<N;lane=lane+1) begin:g_boundary_isolation
        assign isolated_a[16*lane+:16]=active_a[lane]?a_west_flat[16*lane+:16]:16'd0;
        assign isolated_b[16*lane+:16]=active_b[lane]?b_north_flat[16*lane+:16]:16'd0;
    end endgenerate
    systolic_mesh_controller #(.N(N)) controller (
        .clk(clk),.rst_n(rst_n),.start(start),.step_enable(step_enable),.mode(mode),
        .mesh_all_done(all_done),.mesh_any_error(any_error),
        .start_ready(start_ready),.start_accepted(start_accepted),.busy(busy),
        .done(done),.error(error),.mode_q(mode_q),.mesh_clear(mesh_clear),
        .mesh_advance(mesh_advance),.feed_active(feed_active),.compute_step(compute_step)
    );
    systolic_mesh_16x16 #(.N(N),.PE_CLOCK_GATING(PE_CLOCK_GATING)) mesh (
        .clk(clk),.rst_n(rst_n),.clear(mesh_clear),.advance(mesh_advance),.mode(mode_q),
        .a_west_flat(isolated_a),.b_north_flat(isolated_b),
        .a_valid_west(active_a),.b_valid_north(active_b),
        .a_east_flat(a_east_flat),.b_south_flat(b_south_flat),
        .a_valid_east(a_valid_east),.b_valid_south(b_valid_south),
        .result_data_flat(result_data_flat),.result_valid_flat(result_valid_flat),
        .error_flat(error_flat),.all_done(all_done),.any_error(any_error)
    );
endmodule
