module tile_enable_decode (
    input  wire [1:0]  mode,
    input  wire        enable,
    output reg  [15:0] tile_enable
);

    always @* begin
        // Default: no tile is enabled.
        tile_enable = 16'h0000;

        if (enable) begin
            case (mode)
                2'b00: tile_enable = 16'h0001; // INT4: one tile
                2'b01: tile_enable = 16'h0033; // INT8: four tiles
                2'b10: tile_enable = 16'hFFFF; // INT16: sixteen tiles
                default: tile_enable = 16'h0000;
            endcase
        end
    end

endmodule