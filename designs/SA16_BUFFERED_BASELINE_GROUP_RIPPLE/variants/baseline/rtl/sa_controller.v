`timescale 1ns/1ps
// Autonomous transaction: start, 256 paired writes, clear, 48 advances, check.
// No external combinational step-enable path enters the accepted mesh.
module sa_controller #(
    parameter integer CLOCK_GATING=1
) (
    input wire clk,rst_n,clear,start,
    input wire [1:0] mode,
    input wire input_valid,mesh_all_done,mesh_any_error,
    input wire [5:0] step_index,
    output wire start_ready,start_accepted,input_ready,load_accept,
    output wire [7:0] load_address,
    output reg [1:0] mode_q,
    output wire mesh_clear,mesh_advance,feed_active,busy,done,
    output reg protocol_error,
    output reg [2:0] phase
);
    localparam IDLE=3'd0,LOAD=3'd1,CLEAR_MESH=3'd2,RUN=3'd3,
               CHECK=3'd4,DONE=3'd5;
    reg [7:0] load_count;
    function valid_mode;
        input [1:0] m;
        begin case(m)
            2'b00,2'b01,2'b10: valid_mode=1'b1;
            default: valid_mode=1'b0;
        endcase end
    endfunction
    assign start_ready=rst_n && !clear && (phase==IDLE);
    assign start_accepted=start && start_ready && valid_mode(mode);
    assign input_ready=rst_n && !clear && (phase==LOAD);
    assign load_accept=input_valid && input_ready;
    assign load_address=load_count;
    assign mesh_clear=rst_n && (clear || phase==CLEAR_MESH);
    assign mesh_advance=rst_n && (clear || phase==CLEAR_MESH || phase==RUN);
    assign feed_active=rst_n && !clear && (phase==RUN);
    assign busy=(phase!=IDLE);
    assign done=rst_n && !clear && (phase==DONE);

    wire load_clock,mode_clock;
    generate if(CLOCK_GATING!=0) begin : g_gates
        precision_icg load_gate(.clk(clk),.enable(clear || start_accepted || load_accept),
            .test_enable(1'b0),.gclk(load_clock));
        precision_icg mode_gate(.clk(clk),.enable(clear || start_accepted),
            .test_enable(1'b0),.gclk(mode_clock));
    end else begin : g_reference
        assign load_clock=clk;assign mode_clock=clk;
    end endgenerate
    always @(posedge load_clock or negedge rst_n) begin
        if(!rst_n) load_count<=0;
        else if(clear || start_accepted) load_count<=0;
        else if(load_accept) load_count<=load_count+8'd1;
    end
    always @(posedge mode_clock or negedge rst_n) begin
        if(!rst_n) mode_q<=0;
        else if(clear) mode_q<=0;
        else if(start_accepted) mode_q<=mode;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin phase<=IDLE;protocol_error<=0;end
        else if(clear) begin phase<=IDLE;protocol_error<=0;end
        else case(phase)
            IDLE: begin
                if(start_accepted) begin phase<=LOAD;protocol_error<=0;end
                else if(start && !valid_mode(mode)) protocol_error<=1;
            end
            LOAD: if(load_accept && load_count==8'd255) phase<=CLEAR_MESH;
            CLEAR_MESH: phase<=RUN;
            RUN: if(step_index==6'd47) phase<=CHECK;
            CHECK: begin
                if(mesh_all_done && !mesh_any_error) phase<=DONE;
                else begin protocol_error<=1;phase<=IDLE;end
            end
            DONE: phase<=IDLE;
            default: begin protocol_error<=1;phase<=IDLE;end
        endcase
    end
endmodule
