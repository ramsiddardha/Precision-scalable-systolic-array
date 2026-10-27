`timescale 1ns/1ps

// Check the input/forwarding register independently of multiplier arithmetic.
module precision_operand_register_tb;
    reg clk = 0, rst_n = 1, clear = 0, advance = 0, in_valid = 0;
    reg [1:0] mode = 0;
    reg [15:0] data_in = 0;
    wire signed [15:0] data_q;
    wire [1:0] mode_q;
    wire valid_q;
    reg [15:0] expected_data = 0;
    reg [1:0] expected_mode = 0;
    reg expected_valid = 0;
    integer clock_checks = 0, reset_checks = 0;
    integer captures = 0, stalls = 0, bubbles = 0, clears = 0;
    integer seed = 32'h26a0b016;
    integer i;
    reg [31:0] control_word, random_word;

    precision_operand_register dut (.*);
    always #5 clk = ~clk;

    function automatic mode_ok(input [1:0] selected);
        case (selected)
            0, 1, 2: mode_ok = 1;
            default: mode_ok = 0;
        endcase
    endfunction

    // Numeric subtraction implements signed decoding independently of the
    // concatenation/sign-extension expressions in the DUT.
    function automatic [15:0] decode(input [1:0] selected, input [15:0] word);
        integer value, width;
        begin
            case (selected)
                0: begin width = 4; value = $unsigned(word[3:0]); end
                1: begin width = 8; value = $unsigned(word[7:0]); end
                2: begin width = 16; value = $unsigned(word); end
                default: begin width = 16; value = 0; end
            endcase
            if (value >= (1 << (width - 1))) value = value - (1 << width);
            decode = value;
        end
    endfunction

    task automatic check_outputs(input string description);
        if (data_q !== expected_data || mode_q !== expected_mode || valid_q !== expected_valid)
            $fatal(1, "%s: expected data=%h mode=%b valid=%b; got %h %b %b",
                   description, expected_data, expected_mode, expected_valid, data_q, mode_q, valid_q);
    endtask

    task automatic cycle(input bit clr, adv, valid, input [1:0] selected,
                         input [15:0] word, input string description);
        reg [15:0] previous_storage;
        bit captured;
        begin
            @(negedge clk);
            clear = clr; advance = adv; in_valid = valid; mode = selected; data_in = word;
            previous_storage = {dut.high_q, dut.mid_q, dut.low_q};
            captured = !clr && adv && valid && mode_ok(selected);
            #1; check_outputs("Live inputs must not change registered output before clock");
            if (clr) begin
                expected_data = 0; expected_mode = 0; expected_valid = 0;
                clears = clears + 1;
            end else if (!adv) stalls = stalls + 1;
            else if (captured) begin
                expected_data = decode(selected, word);
                expected_mode = selected; expected_valid = 1;
                captures = captures + 1;
            end else begin
                expected_valid = 0; bubbles = bubbles + 1;
            end
            @(posedge clk); #1;
            check_outputs(description);
            clock_checks = clock_checks + 1;
            if (clr) begin
                if ({dut.high_q, dut.mid_q, dut.low_q} !== 16'd0)
                    $fatal(1, "Clear did not zero the operand slices");
            end else if (!captured) begin
                if ({dut.high_q, dut.mid_q, dut.low_q} !== previous_storage)
                    $fatal(1, "%s: data storage changed without capture", description);
            end else begin
                if (selected == 0 && {dut.high_q, dut.mid_q} !== previous_storage[15:4])
                    $fatal(1, "INT4 wrote unused operand slices");
                if (selected == 1 && dut.high_q !== previous_storage[15:8])
                    $fatal(1, "INT8 wrote the unused operand slice");
            end
        end
    endtask

    task automatic async_reset;
        begin
            @(negedge clk); #2; rst_n = 0;
            expected_data = 0; expected_mode = 0; expected_valid = 0;
            #1; check_outputs("Asynchronous assertion before clock");
            if ({dut.high_q, dut.mid_q, dut.low_q} !== 16'd0)
                $fatal(1, "Operand reset is not asynchronous");
            reset_checks = reset_checks + 1;
            @(posedge clk); #1; check_outputs("Reset held at clock");
            reset_checks = reset_checks + 1;
            @(negedge clk);
            rst_n = 1; clear = 0; advance = 0; in_valid = 0; mode = 0; data_in = 0;
        end
    endtask

    initial begin
        async_reset();
        cycle(0, 1, 1, 0, 0, "Constant INT4 zero startup");
        for (i = 0; i < 16; i = i + 1)
            cycle(0, 1, 1, 0, 16'ha5f0 | i, "Every INT4 encoding; ignored upper bits");
        for (i = 0; i < 256; i = i + 1)
            cycle(0, 1, 1, 1, 16'ha500 | i, "Every INT8 encoding; ignored upper bits");
        for (i = 0; i < 16; i = i + 1) begin
            cycle(0, 1, 1, 2, 16'd1 << i, "INT16 walking one");
            cycle(0, 1, 1, 2, ~(16'd1 << i), "INT16 walking zero");
        end
        cycle(0, 1, 1, 2, 16'h8000, "INT16 minimum");
        cycle(0, 1, 1, 2, 16'h7fff, "INT16 maximum");
        cycle(0, 1, 1, 0, {12'hxxx, 4'hd}, "INT4 ignores X upper input");
        cycle(0, 1, 1, 1, {8'hzz, 8'h80}, "INT8 ignores Z upper input");
        cycle(0, 0, 1, 2'bxx, 16'hxxxx, "Stall holds data mode and valid");
        cycle(0, 1, 0, 2'bxx, 16'hxxxx, "Bubble keeps data and clears valid");
        cycle(0, 1, 1, 3, 16'hffff, "Reserved mode drops valid");
        cycle(0, 1, 1, 2'bxx, 16'hffff, "Unknown mode drops valid");
        cycle(1, 0, 1, 2, 16'hffff, "Clear overrides stall and offered operand");
        for (i = 0; i < 1024; i = i + 1) begin
            control_word = $random(seed); random_word = $random(seed);
            cycle(control_word[8:4] == 0, control_word[3:2] != 0,
                  control_word[1:0] != 0, control_word[10:9], random_word[15:0],
                  "Reproducible mixed-control register test");
        end
        cycle(0, 1, 1, 2, 16'habcd, "Nonzero pending data before reset");
        async_reset();
        $display("OPERAND REGISTER TEST PASSED: %0d clocked checks; %0d reset checks", clock_checks, reset_checks);
        $display("Captures=%0d; stalls=%0d; bubbles/reserved=%0d; clears=%0d", captures, stalls, bubbles, clears);
        $finish;
    end
    initial begin #30000; $fatal(1, "Operand register test timed out"); end
endmodule
