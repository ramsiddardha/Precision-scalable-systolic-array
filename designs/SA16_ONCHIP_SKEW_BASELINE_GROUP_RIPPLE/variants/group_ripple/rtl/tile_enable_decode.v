// Tile (i,j) occupies enable bit 4*i+j: i is the A chunk, j the B chunk.
module tile_enable_decode (
    input  wire [1:0]  mode,
    input  wire        enable,
    output reg  [15:0] tile_enable
);
    always @* begin
        tile_enable = 16'h0000;

        if (enable) begin
            case (mode)
                2'b00: tile_enable = 16'h0001; // Tile (0,0).
                2'b01: tile_enable = 16'h0033; // (0,0), (0,1), (1,0), (1,1).
                2'b10: tile_enable = 16'hFFFF; // All sixteen tiles.
                default: tile_enable = 16'h0000;
            endcase
        end
    end
endmodule
