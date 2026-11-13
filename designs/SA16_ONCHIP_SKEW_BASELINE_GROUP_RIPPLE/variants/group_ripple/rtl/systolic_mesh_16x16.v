`timescale 1ns/1ps

// Direct-input mesh. Boundary operand timing is supplied externally.
// N=16 is the production design; smaller N is used only for local regression.
module systolic_mesh_16x16 #(
    parameter integer N=16,
    parameter integer PE_CLOCK_GATING=1
) (
    input wire clk,rst_n,clear,advance,
    input wire [1:0] mode,
    input wire [16*N-1:0] a_west_flat,b_north_flat,
    input wire [N-1:0] a_valid_west,b_valid_north,
    output wire [16*N-1:0] a_east_flat,b_south_flat,
    output wire [N-1:0] a_valid_east,b_valid_south,
    output wire [36*N*N-1:0] result_data_flat,
    output wire [N*N-1:0] result_valid_flat,error_flat,
    output wire all_done,any_error
);
    wire [15:0] a_link [0:N-1][0:N];
    wire [15:0] b_link [0:N][0:N-1];
    wire a_valid [0:N-1][0:N];
    wire b_valid [0:N][0:N-1];
    // Internal observation wires add no registers or external output loads.
    wire signed [35:0] acc_internal [0:N*N-1];
    wire [4:0] count_internal [0:N*N-1];
    wire [1:0] mode_internal [0:N*N-1];
    wire [15:0] tiles_internal [0:N*N-1];
    wire [N*N-1:0] raw_done,pe_clocks;

    genvar r,c;
    generate
        for(r=0;r<N;r=r+1) begin : g_row
            assign a_link[r][0]=a_west_flat[16*r +: 16];
            assign a_valid[r][0]=a_valid_west[r];
            assign a_east_flat[16*r +: 16]=a_link[r][N];
            assign a_valid_east[r]=a_valid[r][N];
            for(c=0;c<N;c=c+1) begin : g_col
                localparam integer ID=r*N+c;
                mesh_pe_clock_cell #(.CLOCK_GATING(PE_CLOCK_GATING)) cell_unit (
                    .clk(clk),.rst_n(rst_n),.clear(clear),.advance(advance),.mode(mode),
                    .a_in(a_link[r][c]),.b_in(b_link[r][c]),
                    .a_valid_in(a_valid[r][c]),.b_valid_in(b_valid[r][c]),
                    .a_out(a_link[r][c+1]),.b_out(b_link[r+1][c]),
                    .a_valid_out(a_valid[r][c+1]),.b_valid_out(b_valid[r+1][c]),
                    .acc_q(acc_internal[ID]),.acc_mode_q(mode_internal[ID]),
                    .term_count(count_internal[ID]),.result_valid(raw_done[ID]),
                    .protocol_error(error_flat[ID]),.tile_enabled(tiles_internal[ID]),
                    .pe_clock(pe_clocks[ID])
                );
                assign result_valid_flat[ID]=raw_done[ID] && !error_flat[ID];
                // A result is observable when valid. Intermediate accumulations
                // stay local and do not toggle the external result bus.
                assign result_data_flat[36*ID +: 36]=result_valid_flat[ID]
                    ? acc_internal[ID] : 36'd0;
            end
        end
        for(c=0;c<N;c=c+1) begin : g_boundary
            assign b_link[0][c]=b_north_flat[16*c +: 16];
            assign b_valid[0][c]=b_valid_north[c];
            assign b_south_flat[16*c +: 16]=b_link[N][c];
            assign b_valid_south[c]=b_valid[N][c];
        end
    endgenerate
    assign any_error=|error_flat;
    assign all_done=(&result_valid_flat) && !any_error;
endmodule

// Hierarchical idle clock gating around one byte-identical supplied PE.
// Two activity-history bits retain the operand/product pipeline drain clocks.
// This is clock qualification, not an input scheduler or controller FSM.
module mesh_pe_clock_cell #(
    parameter integer CLOCK_GATING=1
) (
    input wire clk,rst_n,clear,advance,
    input wire [1:0] mode,
    input wire [15:0] a_in,b_in,
    input wire a_valid_in,b_valid_in,
    output wire signed [15:0] a_out,b_out,
    output wire a_valid_out,b_valid_out,
    output wire signed [35:0] acc_q,
    output wire [1:0] acc_mode_q,
    output wire [4:0] term_count,
    output wire result_valid,protocol_error,
    output wire [15:0] tile_enabled,
    output wire pe_clock
);
    generate
        if(CLOCK_GATING!=0) begin : g_clock_gate
            reg [1:0] active_history;
            wire input_active=a_valid_in || b_valid_in;
            wire [1:0] next_history={active_history[0],input_active};
            wire history_clock;
            precision_icg history_icg (
                .clk(clk),.enable(clear || (advance && (active_history!=next_history))),
                .test_enable(1'b0),.gclk(history_clock)
            );
            always @(posedge history_clock or negedge rst_n) begin
                if(!rst_n) active_history<=2'b00;
                else if(clear) active_history<=2'b00;
                else if(advance) active_history<=next_history;
            end
            precision_icg pe_icg (
                .clk(clk),.enable(clear || (advance && (input_active || (|active_history)))),
                .test_enable(1'b0),.gclk(pe_clock)
            );
        end else begin : g_ungated_reference
            assign pe_clock=clk;
        end
    endgenerate
    systolic_pe_signed pe (
        .clk(pe_clock),.rst_n(rst_n),.clear(clear),.advance(advance),.mode(mode),
        .a_in(a_in),.b_in(b_in),.a_valid_in(a_valid_in),.b_valid_in(b_valid_in),
        .a_out(a_out),.b_out(b_out),.a_valid_out(a_valid_out),.b_valid_out(b_valid_out),
        .acc_q(acc_q),.acc_mode_q(acc_mode_q),.term_count(term_count),
        .result_valid(result_valid),.protocol_error(protocol_error),.tile_enabled(tile_enabled)
    );
endmodule
