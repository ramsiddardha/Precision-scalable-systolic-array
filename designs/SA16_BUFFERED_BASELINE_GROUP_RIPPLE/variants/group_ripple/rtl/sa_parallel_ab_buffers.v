`timescale 1ns/1ps
// Both matrices use row-major host writes. A is banked by row, B by column.
// Storage is 2*16*16*16=8192 bits, with no array reset or read registers.
// A legal full load precedes reads. Inactive precision slices retain old bits.
module sa_parallel_ab_buffers #(
    parameter integer CLOCK_GATING=1
) (
    input wire clk,rst_n,write_enable,
    input wire [1:0] mode,
    input wire [7:0] write_address,
    input wire [15:0] a_data,b_data,
    input wire [15:0] read_enable,
    input wire [63:0] read_index,
    output wire [255:0] a_read_data,b_read_data
);
    wire write_clock;
    generate if(CLOCK_GATING!=0) begin : g_write_gate
        precision_icg write_gate(.clk(clk),.enable(rst_n && write_enable),
            .test_enable(1'b0),.gclk(write_clock));
    end else begin : g_write_reference
        assign write_clock=clk;
    end endgenerate
    sa_matrix_banks #(.BANK_BY_COLUMN(0),.CLOCK_GATING(CLOCK_GATING)) a_buffer (
        .clk(write_clock),.rst_n(rst_n),.mode(mode),.write_enable(write_enable),
        .write_address(write_address),.write_data(a_data),
        .read_enable(read_enable),.read_index(read_index),.read_data(a_read_data));
    sa_matrix_banks #(.BANK_BY_COLUMN(1),.CLOCK_GATING(CLOCK_GATING)) b_buffer (
        .clk(write_clock),.rst_n(rst_n),.mode(mode),.write_enable(write_enable),
        .write_address(write_address),.write_data(b_data),
        .read_enable(read_enable),.read_index(read_index),.read_data(b_read_data));
endmodule

module sa_matrix_banks #(
    parameter integer BANK_BY_COLUMN=0,
    parameter integer CLOCK_GATING=1
) (
    input wire clk,rst_n,write_enable,
    input wire [1:0] mode,
    input wire [7:0] write_address,
    input wire [15:0] write_data,
    input wire [15:0] read_enable,
    input wire [63:0] read_index,
    output wire [255:0] read_data
);
    reg [2:0] slices;
    always @* case(mode)
        2'b00:slices=3'b001;
        2'b01:slices=3'b011;
        2'b10:slices=3'b111;
        default:slices=3'b000;
    endcase
    wire [7:0] safe_address=write_enable ? write_address : 8'd0;
    wire [3:0] write_bank=BANK_BY_COLUMN ? safe_address[3:0] : safe_address[7:4];
    wire [3:0] write_word=BANK_BY_COLUMN ? safe_address[7:4] : safe_address[3:0];
    genvar bank;
    generate for(bank=0;bank<16;bank=bank+1) begin : g_bank
        reg [3:0] low_mem[0:15];
        reg [3:0] mid_mem[0:15];
        reg [7:0] high_mem[0:15];
        wire bank_write=rst_n && write_enable && slices[0] && (write_bank==bank);
        wire mid_write=bank_write && slices[1];
        wire high_write=bank_write && slices[2];
        wire bank_clock,mid_clock,high_clock;
        // Hierarchical gates: only the selected bank clocks. Upper-slice gate
        // latches see that bank clock, rather than the global root clock.
        if(CLOCK_GATING!=0) begin : g_clock_gates
            precision_icg bank_gate(.clk(clk),.enable(bank_write),
                .test_enable(1'b0),.gclk(bank_clock));
            precision_icg mid_gate(.clk(bank_clock),.enable(slices[1]),
                .test_enable(1'b0),.gclk(mid_clock));
            precision_icg high_gate(.clk(bank_clock),.enable(slices[2]),
                .test_enable(1'b0),.gclk(high_clock));
        end else begin : g_reference
            assign bank_clock=clk;assign mid_clock=clk;assign high_clock=clk;
        end
        wire [3:0] low_data=bank_write ? write_data[3:0] : 4'd0;
        wire [3:0] mid_data=mid_write ? write_data[7:4] : 4'd0;
        wire [7:0] high_data=high_write ? write_data[15:8] : 8'd0;
        always @(posedge bank_clock) if(bank_write) low_mem[write_word]<=low_data;
        always @(posedge mid_clock) if(mid_write) mid_mem[write_word]<=mid_data;
        always @(posedge high_clock) if(high_write) high_mem[write_word]<=high_data;
        wire low_read=rst_n && read_enable[bank] && slices[0];
        wire mid_read=low_read && slices[1];
        wire high_read=low_read && slices[2];
        wire [3:0] low_index=low_read ? read_index[4*bank +: 4] : 4'd0;
        wire [3:0] mid_index=mid_read ? read_index[4*bank +: 4] : 4'd0;
        wire [3:0] high_index=high_read ? read_index[4*bank +: 4] : 4'd0;
        wire [3:0] low_value=low_read ? low_mem[low_index] : 4'd0;
        wire [3:0] mid_value=mid_read ? mid_mem[mid_index] : 4'd0;
        wire [7:0] high_value=high_read ? high_mem[high_index] : 8'd0;
        // Accepted EncodedShared PE decodes the active sign bit using mode.
        // Keep unused upper link bits at zero instead of broadcasting sign.
        assign read_data[16*bank +: 16]={high_value,mid_value,low_value};
    end endgenerate
endmodule
