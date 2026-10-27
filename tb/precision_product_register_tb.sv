`timescale 1ns/1ps

// Standalone tests for product storage and pipeline control.
// These are register tests, not additional exhaustive multiplier tests.
module precision_product_register_tb;
    reg clk = 1'b0;
    reg rst_n = 1'b1;
    reg clear = 1'b0;
    reg advance = 1'b0;
    reg in_valid = 1'b0;
    reg [1:0] mode = 2'b00;
    reg signed [31:0] product_in = 32'sd0;

    wire signed [31:0] product_q;
    wire [1:0] product_mode_q;
    wire product_valid_q;

    reg signed [31:0] expected_product = 32'sd0;
    reg [1:0] expected_mode = 2'b00;
    reg expected_valid = 1'b0;
    integer clock_checks = 0;
    integer reset_checks = 0;
    integer stability_checks = 0;
    integer captures_int4 = 0;
    integer captures_int8 = 0;
    integer captures_int16 = 0;
    integer stall_checks = 0;
    integer bubble_checks = 0;
    integer reserved_checks = 0;
    integer clear_checks = 0;
    integer seed = 32'h25a0beef;
    integer i, j;
    reg [31:0] walking_bit;
    reg [31:0] random_control, random_product;

    precision_product_register dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .advance(advance),
        .in_valid(in_valid), .mode(mode), .product_in(product_in),
        .product_q(product_q), .product_mode_q(product_mode_q),
        .product_valid_q(product_valid_q)
    );

    // A convenient 10 ns functional-test clock; this does not set the project's
    // 300 MHz timing target or model cell delays. Genus checks timing separately.
    always #5 clk = ~clk;

    function automatic valid_mode(input [1:0] selected_mode);
        begin
            case (selected_mode)
                2'b00, 2'b01, 2'b10: valid_mode = 1'b1;
                default: valid_mode = 1'b0;
            endcase
        end
    endfunction

    // Independent numeric interpretation rather than the DUT's concatenations.
    // For narrow modes, upper input bits are deliberately ignored.
    function automatic signed [31:0] reference_product(
        input [1:0] selected_mode,
        input [31:0] value
    );
        integer decoded;
        begin
            case (selected_mode)
                2'b00: begin
                    decoded = $unsigned(value[7:0]);
                    if (decoded >= 128) decoded = decoded - 256;
                    reference_product = decoded;
                end
                2'b01: begin
                    decoded = $unsigned(value[15:0]);
                    if (decoded >= 32768) decoded = decoded - 65536;
                    reference_product = decoded;
                end
                2'b10: reference_product = value;
                default: reference_product = 32'sd0;
            endcase
        end
    endfunction

    task automatic check_outputs(input string description);
        begin
            if (product_q !== expected_product ||
                product_mode_q !== expected_mode ||
                product_valid_q !== expected_valid)
                $fatal(1,
                    "%s: expected product=%h mode=%b valid=%b; got product=%h mode=%b valid=%b",
                    description, expected_product, expected_mode, expected_valid,
                    product_q, product_mode_q, product_valid_q);
        end
    endtask

    // Drive before the sampling edge, then check after nonblocking updates.
    task automatic step(
        input bit selected_clear,
        input bit selected_advance,
        input bit selected_valid,
        input [1:0] selected_mode,
        input [31:0] selected_product,
        input string description
    );
        reg [31:0] previous_storage;
        bit accepted;
        begin
            @(negedge clk);
            clear = selected_clear;
            advance = selected_advance;
            in_valid = selected_valid;
            mode = selected_mode;
            product_in = selected_product;
            previous_storage = {dut.high_q, dut.mid_q, dut.low_q};
            accepted = selected_advance && selected_valid && valid_mode(selected_mode);

            if (selected_clear) begin
                expected_product = 32'sd0;
                expected_mode = 2'b00;
                expected_valid = 1'b0;
                clear_checks = clear_checks + 1;
            end else if (!selected_advance) begin
                // A stall retains the pending transaction, including valid.
                stall_checks = stall_checks + 1;
            end else if (accepted) begin
                expected_product = reference_product(selected_mode, selected_product);
                expected_mode = selected_mode;
                expected_valid = 1'b1;
                case (selected_mode)
                    2'b00: captures_int4 = captures_int4 + 1;
                    2'b01: captures_int8 = captures_int8 + 1;
                    2'b10: captures_int16 = captures_int16 + 1;
                endcase
            end else begin
                expected_valid = 1'b0;
                if (selected_valid && !valid_mode(selected_mode))
                    reserved_checks = reserved_checks + 1;
                else
                    bubble_checks = bubble_checks + 1;
            end

            @(posedge clk);
            #1;
            check_outputs(description);
            clock_checks = clock_checks + 1;

            // Verify the power-control contract as well as the external number:
            // storage slices outside the active width must retain their bits.
            if (selected_clear) begin
                if ({dut.high_q, dut.mid_q, dut.low_q} !== 32'd0)
                    $fatal(1, "%s: clear did not zero every data slice", description);
            end else if (!accepted) begin
                if ({dut.high_q, dut.mid_q, dut.low_q} !== previous_storage)
                    $fatal(1, "%s: held data changed during stall/bubble/reserved mode", description);
            end else begin
                if (selected_mode == 2'b00 &&
                    {dut.high_q, dut.mid_q} !== previous_storage[31:8])
                    $fatal(1, "%s: INT4 changed an unused data slice", description);
                if (selected_mode == 2'b01 && dut.high_q !== previous_storage[31:16])
                    $fatal(1, "%s: INT8 changed the unused upper slice", description);
            end
        end
    endtask

    task automatic asynchronous_reset;
        begin
            // Assert strictly between rising edges. Checking before the next
            // rising edge distinguishes asynchronous reset from a sync reset.
            @(negedge clk);
            #2;
            rst_n = 1'b0;
            expected_product = 32'sd0;
            expected_mode = 2'b00;
            expected_valid = 1'b0;
            #1;
            check_outputs("Asynchronous assertion before next rising edge");
            if ({dut.high_q, dut.mid_q, dut.low_q} !== 32'd0)
                $fatal(1, "Asynchronous reset did not zero every storage slice");
            reset_checks = reset_checks + 1;

            // Reset must also dominate any presented transaction at an edge.
            @(posedge clk);
            #1;
            check_outputs("Reset held across rising edge");
            reset_checks = reset_checks + 1;

            // Functional simulation release is kept away from a sampling edge.
            // Hardware must provide properly synchronized reset deassertion.
            @(negedge clk);
            clear = 1'b0;
            advance = 1'b0;
            in_valid = 1'b0;
            mode = 2'b00;
            product_in = 32'sd0;
            rst_n = 1'b1;
        end
    endtask

    initial begin
        asynchronous_reset();

        // Wide -> narrow transitions prime unused slices with nonzero data.
        // A positive narrow capture after a negative one also tests sign cleanup.
        step(0, 1, 1, 2'b10, 32'h12345678, "Prime all data slices");
        step(0, 1, 1, 2'b00, -32'sd15, "INT4 negative after INT16");
        step(0, 1, 1, 2'b01, -32'sd961, "INT8 negative -31 times 31");
        step(0, 1, 1, 2'b00, 32'd42, "INT4 positive with stale upper slices");
        step(0, 1, 1, 2'b10, 32'h40000000, "Largest positive signed INT16 product");
        step(0, 1, 1, 2'b10, 32'hc0008000, "Negative signed INT16 boundary product");
        step(0, 1, 1, 2'b01, 32'd0, "Valid zero product");

        // Bubble: data is held, but valid must drop. Stall: valid must hold too.
        step(0, 1, 0, 2'b10, 32'hdeadbeef, "Advancing bubble");
        step(0, 1, 1, 2'b01, -32'sd12, "Pending product before stalls");
        step(0, 0, 0, 2'b11, 32'hffffffff, "Stall holds pending valid product");
        step(0, 0, 1, 2'b00, 32'd7, "Stall rejects offered replacement");
        step(0, 1, 1, 2'b11, 32'hcafef00d, "Reserved mode inserts bubble");
        step(0, 0, 1, 2'b10, 32'd8, "Stall retains invalid flag");

        // Verify reset/clear precedence independently of ordinary captures.
        step(0, 1, 1, 2'b10, 32'h55aa33cc, "Prime before clear");
        step(1, 0, 1, 2'b10, 32'hffffffff, "Clear overrides stall");
        step(1, 1, 1, 2'b01, -32'sd8, "Clear overrides valid input");

        // In contrast to rst_n, clear must wait for the next rising edge.
        step(0, 1, 1, 2'b10, 32'h12345678, "Prime before synchronous-clear timing check");
        @(negedge clk);
        clear = 1'b1;
        advance = 1'b0;
        #1;
        check_outputs("Synchronous clear waits for the rising edge");
        stability_checks = stability_checks + 1;
        @(posedge clk);
        #1;
        expected_product = 32'sd0;
        expected_mode = 2'b00;
        expected_valid = 1'b0;
        check_outputs("Synchronous clear takes effect at the rising edge");
        if ({dut.high_q, dut.mid_q, dut.low_q} !== 32'd0)
            $fatal(1, "Synchronous clear did not zero every storage slice");
        clock_checks = clock_checks + 1;
        clear_checks = clear_checks + 1;

        step(0, 1, 1, 2'b10, 32'h76543210, "Prime before async reset");
        step(0, 0, 1, 2'b00, 32'd9, "Hold while reset is about to assert");
        asynchronous_reset();

        // Every active data bit is exercised at both polarities. Upper input
        // noise in narrow modes must not change the decoded product value.
        for (j = 0; j < 3; j = j + 1) begin
            for (i = 0; i < ((j == 0) ? 8 : ((j == 1) ? 16 : 32)); i = i + 1) begin
                walking_bit = 32'd1 << i;
                step(0, 1, 1, j[1:0], walking_bit, "Walking one");
                step(0, 1, 1, j[1:0], ~walking_bit, "Walking zero");
            end
        end

        // Four-state checks: unused input fields may even be unknown.
        step(0, 1, 1, 2'b10, 32'ha5a55a5a, "Prime slices before ignored-field tests");
        step(0, 1, 1, 2'b00, {24'hxxxxxx, 8'hf1}, "INT4 ignores unknown upper bits");
        step(0, 1, 1, 2'b01, {16'hzzzz, 16'hfc3f}, "INT8 ignores unknown upper bits");
        step(0, 1, 0, 2'b10, 32'hxxxxxxxx, "Bubble ignores unknown product");
        step(0, 0, 1, 2'b10, 32'hzzzzzzzz, "Stall ignores high-impedance product");
        step(0, 1, 1, 2'bx1, 32'hxxxxxxxx, "Unknown mode inserts bubble");

        // Changes between sampling edges must not alter stored data or mode.
        step(0, 1, 1, 2'b01, -32'sd961, "Prime before between-edge check");
        product_in = 32'h12345678;
        mode = 2'b10;
        #1;
        check_outputs("Input changes before next rising edge");
        stability_checks = stability_checks + 1;

        // Reproducible control/data traffic mixes precision changes, bubbles,
        // stalls, clears and reserved inputs rather than only data captures.
        for (i = 0; i < 1024; i = i + 1) begin
            random_control = $random(seed);
            random_product = $random(seed);
            step(&random_control[3:0],
                 |random_control[5:4],
                 |random_control[7:6],
                 random_control[9:8], random_product,
                 "Reproducible mixed traffic");
        end

        // Finish with a nonempty pipeline and a final off-edge reset.
        step(0, 1, 1, 2'b10, 32'hfedcba98, "Final pending product");
        asynchronous_reset();

        $display("PRODUCT REGISTER TEST PASSED");
        $display("Clocked transactions: %0d", clock_checks);
        $display("Async/held-reset checks: %0d; between-edge stability checks: %0d",
                 reset_checks, stability_checks);
        $display("Captures INT4=%0d INT8=%0d INT16=%0d; stalls=%0d bubbles=%0d reserved=%0d clears=%0d",
                 captures_int4, captures_int8, captures_int16, stall_checks,
                 bubble_checks, reserved_checks, clear_checks);
        $finish;
    end

    // Fail instead of hanging if clock/event sequencing is broken.
    initial begin
        #100000;
        $fatal(1, "Product register test timed out");
    end
endmodule
