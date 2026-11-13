`timescale 1ns/1ps

// Conditional two's-complement sign restoration using lower-bit OR prefixes.
// -x keeps bits through the least-significant 1 and flips every higher bit:
// y[0]=x[0]; y[i]=x[i] XOR (negative AND OR(x[i-1:0])).
// The 8/8/16-bit sections isolate both data and prefix controls when unused.
module precision_sign_restore (
    input  wire              enable,
    input  wire [1:0]        mode,
    input  wire              negative,
    input  wire [31:0]       magnitude_product,
    output reg signed [31:0] product
);
    wire low_enable, mid_enable, high_enable;
    wire low_nonzero, mid_nonzero, high_nonzero;
    wire [7:0] low_result, mid_result;
    wire [15:0] high_result;
    function valid_precision;
        input [1:0] selected;
        begin
            case (selected)
                2'b00,2'b01,2'b10: valid_precision=1'b1;
                default: valid_precision=1'b0;
            endcase
        end
    endfunction
    assign low_enable = enable && valid_precision(mode);
    assign mid_enable = low_enable && ((mode==2'b01) || (mode==2'b10));
    assign high_enable = low_enable && (mode==2'b10);
    psr_or_section #(.WIDTH(8)) low_section (
        .active(low_enable), .negative(negative), .lower_nonzero(1'b0),
        .value(magnitude_product[7:0]), .result(low_result), .any_nonzero(low_nonzero)
    );
    psr_or_section #(.WIDTH(8)) mid_section (
        .active(mid_enable), .negative(negative), .lower_nonzero(low_nonzero),
        .value(magnitude_product[15:8]), .result(mid_result), .any_nonzero(mid_nonzero)
    );
    psr_or_section #(.WIDTH(16)) high_section (
        .active(high_enable), .negative(negative), .lower_nonzero(mid_nonzero),
        .value(magnitude_product[31:16]), .result(high_result), .any_nonzero(high_nonzero)
    );
    always @* begin
        product=32'sd0;
        if (enable) begin
            case (mode)
                2'b00: product={{24{low_result[7]}},low_result};
                2'b01: product={{16{mid_result[7]}},mid_result,low_result};
                2'b10: product={high_result,mid_result,low_result};
                default: product=32'sd0;
            endcase
        end
    end
endmodule

module psr_or_section #(
    parameter integer WIDTH=8,
    parameter integer LEVELS=$clog2(WIDTH)
) (
    input wire active, negative, lower_nonzero,
    input wire [WIDTH-1:0] value,
    output wire [WIDTH-1:0] result,
    output wire any_nonzero
);
    wire [WIDTH-1:0] x;
    wire [WIDTH-1:0] prefix [0:LEVELS];
    wire negate_active, lower_active;
    assign x=active ? value : {WIDTH{1'b0}};
    assign negate_active=active && negative;
    assign lower_active=active && lower_nonzero;
    // Positive products pass x directly; their negation prefix stays quiet.
    assign prefix[0]=negate_active ? x : {WIDTH{1'b0}};
    genvar level,bit_index;
    generate
        for (level=0;level<LEVELS;level=level+1) begin : g_level
            for (bit_index=0;bit_index<WIDTH;bit_index=bit_index+1) begin : g_bit
                if (bit_index >= (1<<level)) begin : g_combine
                    assign prefix[level+1][bit_index]=prefix[level][bit_index] |
                        prefix[level][bit_index-(1<<level)];
                end else begin : g_pass
                    assign prefix[level+1][bit_index]=prefix[level][bit_index];
                end
            end
        end
        for (bit_index=0;bit_index<WIDTH;bit_index=bit_index+1) begin : g_result
            if (bit_index==0) begin : g_first
                assign result[bit_index]=x[bit_index] ^ (negate_active && lower_active);
            end else begin : g_upper
                assign result[bit_index]=x[bit_index] ^
                    (negate_active && (lower_active || prefix[LEVELS][bit_index-1]));
            end
        end
    endgenerate
    assign any_nonzero=negate_active && (lower_active || prefix[LEVELS][WIDTH-1]);
endmodule
