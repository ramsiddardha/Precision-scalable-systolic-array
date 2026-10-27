`timescale 1ns/1ps

module tile_enable_decode_tb;
    reg [1:0] mode;
    reg enable;
    wire [15:0] tile_enable;
    integer checks = 0;
    integer mode_index;

    tile_enable_decode dut (
        .mode(mode), .enable(enable), .tile_enable(tile_enable)
    );

    task check;
        input [1:0] selected_mode;
        input selected_enable;
        integer chunks, bit_index, active_count;
        reg [15:0] expected_mask;
        begin
            mode = selected_mode;
            enable = selected_enable;
            #10;

            // Independently derive permission from each tile's row/column.
            case (selected_mode)
                2'b00: chunks = 1;
                2'b01: chunks = 2;
                2'b10: chunks = 4;
                default: chunks = 0;
            endcase
            expected_mask = 16'd0;
            active_count = 0;
            for (bit_index = 0; bit_index < 16; bit_index = bit_index + 1) begin
                expected_mask[bit_index] = selected_enable &&
                    ((bit_index / 4) < chunks) && ((bit_index % 4) < chunks);
                if (expected_mask[bit_index]) active_count = active_count + 1;
            end

            if (tile_enable !== expected_mask)
                $fatal(1, "FAIL mode=%b enable=%b expected=%h output=%h",
                       mode, enable, expected_mask, tile_enable);
            checks = checks + 1;
            $display("PASS mode=%b enable=%b mask=%h enabled_tiles=%0d",
                     mode, enable, tile_enable, active_count);
        end
    endtask

    initial begin
        for (mode_index = 0; mode_index < 4; mode_index = mode_index + 1)
            check(mode_index[1:0], 1'b1);
        for (mode_index = 0; mode_index < 4; mode_index = mode_index + 1)
            check(mode_index[1:0], 1'b0);

        $display("ALL %0d TILE ENABLE TESTS PASSED", checks);
        $finish;
    end
endmodule
