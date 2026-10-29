`timescale 1ns/1ps

// Positive-edge clock-gating model: capture enable only while clk is low.
// The held enable cannot create an extra clock edge while clk is high.
// Registers using gclk keep their own asynchronous reset; the latch has none.
// Genus may implement this as latch + AND or recognize a library ICG cell.
// Verify the mapped implementation before claiming a particular library cell.
module precision_icg (
    input  wire clk,
    input  wire enable,
    input  wire test_enable,
    output wire gclk
);
    reg enable_latched;

    always @* begin
        if (!clk)
            enable_latched = enable | test_enable;
    end

    assign gclk = clk & enable_latched;
endmodule
