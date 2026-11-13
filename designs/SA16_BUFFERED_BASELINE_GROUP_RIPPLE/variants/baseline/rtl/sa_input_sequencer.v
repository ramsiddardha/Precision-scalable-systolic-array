`timescale 1ns/1ps
// No skew shift registers. Row/column lane l reads index k=step-l.
module sa_input_sequencer #(
    parameter integer CLOCK_GATING=1
) (
    input wire clk,rst_n,clear,mesh_clear,feed_active,
    output reg [5:0] step_index,
    output wire [15:0] read_enable,
    output wire [63:0] read_index
);
    wire step_clock;
    generate if(CLOCK_GATING!=0) begin : g_gate
        precision_icg step_gate(.clk(clk),.enable(clear || mesh_clear || feed_active),
            .test_enable(1'b0),.gclk(step_clock));
    end else begin : g_reference
        assign step_clock=clk;
    end endgenerate
    always @(posedge step_clock or negedge rst_n) begin
        if(!rst_n) step_index<=0;
        else if(clear || mesh_clear) step_index<=0;
        else if(feed_active && step_index!=6'd47) step_index<=step_index+6'd1;
    end
    genvar lane;
    generate for(lane=0;lane<16;lane=lane+1) begin : g_lane
        localparam [5:0] FIRST=lane,LIMIT=lane+16;
        wire active=rst_n && !clear && feed_active && step_index>=FIRST && step_index<LIMIT;
        wire [5:0] k=step_index-FIRST;
        assign read_enable[lane]=active;
        assign read_index[4*lane +: 4]=active ? k[3:0] : 4'd0;
    end endgenerate
endmodule
