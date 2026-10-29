`timescale 1ns/1fs

// Power-workload bench for ONE complete systolic PE, not the whole array.
// There are no vector-file or Python dependencies. The DUT RTL is unchanged.
// Vivado selects the runtime mode with -testplusarg POWER_MODE=0, 1 or 2.
// Keep USE_HSM and CLOCK_PERIOD_NS identical to the Genus configuration.
module systolic_pe_power_tb #(
    parameter integer USE_HSM = 0,
    parameter real CLOCK_PERIOD_NS = 3.333
);
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    reg advance = 1'b0;
    reg [1:0] mode = 2'b00;
    reg [15:0] a_in = 16'd0, b_in = 16'd0;
    reg a_valid_in = 1'b0, b_valid_in = 1'b0;
    wire signed [15:0] a_out, b_out;
    wire a_valid_out, b_valid_out;
    wire signed [35:0] acc_q;
    wire [1:0] acc_mode_q;
    wire [4:0] term_count;
    wire result_valid, protocol_error;
    wire [15:0] tile_enabled;

    // The Vivado script starts recording after reset, at 4*CLOCK_PERIOD_NS.
    // It includes each clear edge, sixteen inputs and both pipeline drain edges.
    reg capture_ready = 1'b0;
    reg capture_done = 1'b0;
    integer completed_frames = 0;
    integer selected_mode = 0;
    integer num_frames = 100;
    integer frame_index, term_index;
    integer signed value_a, value_b, minimum_value, maximum_value;
    integer committed_count;
    reg [31:0] random_state = 32'h1a2b3c4d;
    reg [15:0] raw_a, raw_b;
    reg [15:0] expected_tile_mask;
    longint signed product_reference;
    longint signed prefix_sum [0:16];
    string precision_name;

    systolic_pe_signed #(.USE_HSM(USE_HSM)) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .advance(advance),
        .mode(mode), .a_in(a_in), .b_in(b_in),
        .a_valid_in(a_valid_in), .b_valid_in(b_valid_in),
        .a_out(a_out), .b_out(b_out),
        .a_valid_out(a_valid_out), .b_valid_out(b_valid_out),
        .acc_q(acc_q), .acc_mode_q(acc_mode_q), .term_count(term_count),
        .result_valid(result_valid), .protocol_error(protocol_error),
        .tile_enabled(tile_enabled)
    );

    // Count data-bank clock edges to check that precision gating operates.
    // Clear clocks every bank once per frame; each active bank adds 16 writes.
    integer operand_low_edges = 0;
    always @(posedge dut.a_stage.clk_low)
        if (capture_ready) operand_low_edges = operand_low_edges + 1;
    integer operand_mid_edges = 0;
    always @(posedge dut.a_stage.clk_mid)
        if (capture_ready) operand_mid_edges = operand_mid_edges + 1;
    integer operand_high_edges = 0;
    always @(posedge dut.a_stage.clk_high)
        if (capture_ready) operand_high_edges = operand_high_edges + 1;
    integer product_low_edges = 0;
    always @(posedge dut.mac.product_stage.clk_low)
        if (capture_ready) product_low_edges = product_low_edges + 1;
    integer product_mid_edges = 0;
    always @(posedge dut.mac.product_stage.clk_mid)
        if (capture_ready) product_mid_edges = product_mid_edges + 1;
    integer product_high_edges = 0;
    always @(posedge dut.mac.product_stage.clk_high)
        if (capture_ready) product_high_edges = product_high_edges + 1;
    integer accumulator_low_edges = 0;
    always @(posedge dut.mac.accumulate.clk_low)
        if (capture_ready) accumulator_low_edges = accumulator_low_edges + 1;
    integer accumulator_mid_edges = 0;
    always @(posedge dut.mac.accumulate.clk_mid)
        if (capture_ready) accumulator_mid_edges = accumulator_mid_edges + 1;
    integer accumulator_high_edges = 0;
    always @(posedge dut.mac.accumulate.clk_high)
        if (capture_ready) accumulator_high_edges = accumulator_high_edges + 1;

    // The optimized accumulator gates its upper four low-bank bits on
    // carry/borrow. Predict required changes from independent signed addition.
    integer guard_edges=0, expected_guard_edges=0;
    reg signed [35:0] expected_next_sum;
    always @(posedge dut.mac.accumulate.clk_guard)
        if (capture_ready) guard_edges++;
    always @(posedge clk) begin
        if (capture_ready) begin
            if (clear) expected_guard_edges++;
            else if (advance && dut.mac.product_valid_q) begin
                expected_next_sum = $signed(acc_q) + $signed(dut.mac.product_q);
                if (dut.mac.product_mode_q != 2'b00 ||
                    expected_next_sum[11:8] != acc_q[11:8]) expected_guard_edges++;
            end
        end
    end

    always #(CLOCK_PERIOD_NS / 2.0) clk = ~clk;

    // A deterministic PRNG gives the same raw sequence for all three runs.
    // Only the selected signed field changes between INT4, INT8 and INT16.
    function automatic [31:0] next_random(input [31:0] state);
        reg [31:0] temp;
        begin
            temp = state ^ (state << 13);
            temp = temp ^ (temp >> 17);
            next_random = temp ^ (temp << 5);
        end
    endfunction

    function automatic integer signed signed_value(input [15:0] word);
        begin
            case (selected_mode)
                0: signed_value = $signed(word[3:0]);
                1: signed_value = $signed(word[7:0]);
                2: signed_value = $signed(word[15:0]);
                default: signed_value = 0;
            endcase
        end
    endfunction

    // All stimulus changes on falling edges, away from the sampling edge.
    // One time-unit settling delay is sufficient for this RTL simulation.
    task automatic drive_cycle(input bit do_clear, input bit valid_pair,
                               input [15:0] word_a, input [15:0] word_b);
        begin
            @(negedge clk);
            clear = do_clear;
            advance = 1'b1;
            a_valid_in = valid_pair;
            b_valid_in = valid_pair;
            a_in = word_a;
            b_in = word_b;
            @(posedge clk);
            #0.001;
            if (protocol_error !== 1'b0)
                $fatal(1, "Protocol error in frame %0d, mode %0d", frame_index, selected_mode);
        end
    endtask

    task automatic check_sum(input integer expected_count);
        longint signed observed;
        begin
            observed = $signed(acc_q);
            if (term_count !== expected_count[4:0] ||
                observed !== prefix_sum[expected_count] ||
                result_valid !== (expected_count == 16))
                $fatal(1, "Frame %0d: expected count=%0d sum=%0d; got count=%0d sum=%0d done=%b",
                       frame_index, expected_count, prefix_sum[expected_count],
                       term_count, observed, result_valid);
            if (expected_count > 0 && acc_mode_q !== selected_mode[1:0])
                $fatal(1, "Accumulator precision does not match the frame");
        end
    endtask

    // Portable validation only. Vivado exports VCD with the supplied Tcl script.
    // This guard is NOT enabled by the Vivado setup, avoiding two dump owners.
`ifdef PE_PORTABLE_DUMP
    string portable_vcd_file;
    initial begin
        if (!$value$plusargs("VCD_FILE=%s", portable_vcd_file))
            portable_vcd_file = "pe_portable.vcd";
        wait (capture_ready);
        @(negedge clk);
        $dumpfile(portable_vcd_file);
        $dumpvars(0, dut);
    end
`endif

    initial begin
        if ($value$plusargs("POWER_MODE=%d", selected_mode)) begin end
        if ($value$plusargs("NUM_FRAMES=%d", num_frames)) begin end
        if (selected_mode < 0 || selected_mode > 2 || num_frames < 1 ||
            CLOCK_PERIOD_NS <= 0.002)
            $fatal(1, "Use POWER_MODE=0/1/2, NUM_FRAMES>0 and a positive clock period");
        if (USE_HSM != 0)
            $fatal(1, "This PE_COMBINED_OPT workload requires USE_HSM=0");

        mode = selected_mode[1:0];
        case (selected_mode)
            0: begin
                precision_name = "INT4"; expected_tile_mask = 16'h0001;
                minimum_value = -8; maximum_value = 7;
            end
            1: begin
                precision_name = "INT8"; expected_tile_mask = 16'h0033;
                minimum_value = -128; maximum_value = 127;
            end
            2: begin
                precision_name = "INT16"; expected_tile_mask = 16'hffff;
                minimum_value = -32768; maximum_value = 32767;
            end
        endcase

        // Reset/warm-up is excluded from the exported activity interval.
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        capture_ready = 1'b1;
        $display("PE POWER START: %s USE_HSM=%0d clock=%0.6f ns frames=%0d",
                 precision_name, USE_HSM, CLOCK_PERIOD_NS, num_frames);

        for (frame_index = 0; frame_index < num_frames; frame_index = frame_index + 1) begin
            prefix_sum[0] = 0;
            drive_cycle(1'b1, 1'b0, 16'd0, 16'd0);
            check_sum(0);

            for (term_index = 0; term_index < 16; term_index = term_index + 1) begin
                random_state = next_random(random_state); raw_a = random_state[15:0];
                random_state = next_random(random_state); raw_b = random_state[15:0];
                value_a = signed_value(raw_a); value_b = signed_value(raw_b);

                // A few legal corner operands supplement the random workload.
                // Remaining frames cover the full signed range of each mode.
                if (frame_index == 0) begin
                    case (term_index)
                        0: begin value_a = 0; value_b = maximum_value; end
                        1: begin value_a = minimum_value; value_b = minimum_value; end
                        2: begin value_a = minimum_value; value_b = maximum_value; end
                        3: begin value_a = maximum_value; value_b = maximum_value; end
                        4: begin value_a = -1; value_b = 1; end
                        default: begin end
                    endcase
                end
                product_reference = value_a * value_b;
                prefix_sum[term_index + 1] = prefix_sum[term_index] + product_reference;
                drive_cycle(1'b0, 1'b1, value_a[15:0], value_b[15:0]);
                committed_count = (term_index >= 2) ? term_index - 1 : 0;
                check_sum(committed_count);
                if (a_out !== value_a[15:0] || b_out !== value_b[15:0] ||
                    a_valid_out !== 1'b1 || b_valid_out !== 1'b1 ||
                    tile_enabled !== expected_tile_mask)
                    $fatal(1, "Forwarding or multiplier tile mask differs in frame %0d", frame_index);
            end

            // The operand hop and product stage require two drain edges.
            drive_cycle(1'b0, 1'b0, 16'd0, 16'd0);
            check_sum(15);
            drive_cycle(1'b0, 1'b0, 16'd0, 16'd0);
            check_sum(16);
            if (tile_enabled !== 16'd0 || a_valid_out !== 1'b0 || b_valid_out !== 1'b0)
                $fatal(1, "The drained PE should have no active multiplier tiles");
            completed_frames = completed_frames + 1;
        end

        // Finish on a falling edge: exactly 19 clock periods per frame.
        @(negedge clk);
        if (guard_edges != expected_guard_edges)
            $fatal(1, "Accumulator guard clock edges: got %0d expected %0d",guard_edges,expected_guard_edges);
        $display("Accumulator guard clock edges: %0d",guard_edges);
        // In INT4, middle/high clocks pulse only for frame clear. In INT8,
        // high clocks do the same. INT16 opens all three data-bank clocks.
        if (operand_low_edges != 17*num_frames ||
            operand_mid_edges != ((selected_mode >= 1) ? 17*num_frames : num_frames) ||
            operand_high_edges != ((selected_mode == 2) ? 17*num_frames : num_frames))
            $fatal(1, "operand precision-gated clock edge count is incorrect");
        $display("operand clock edges low/mid/high: %0d/%0d/%0d",
                 operand_low_edges, operand_mid_edges, operand_high_edges);
        if (product_low_edges != 17*num_frames ||
            product_mid_edges != ((selected_mode >= 1) ? 17*num_frames : num_frames) ||
            product_high_edges != ((selected_mode == 2) ? 17*num_frames : num_frames))
            $fatal(1, "product precision-gated clock edge count is incorrect");
        $display("product clock edges low/mid/high: %0d/%0d/%0d",
                 product_low_edges, product_mid_edges, product_high_edges);
        if (accumulator_low_edges != 17*num_frames ||
            accumulator_mid_edges != ((selected_mode >= 1) ? 17*num_frames : num_frames) ||
            accumulator_high_edges != ((selected_mode == 2) ? 17*num_frames : num_frames))
            $fatal(1, "accumulator precision-gated clock edge count is incorrect");
        $display("accumulator clock edges low/mid/high: %0d/%0d/%0d",
                 accumulator_low_edges, accumulator_mid_edges, accumulator_high_edges);
        capture_done = 1'b1;
        $display("PE POWER TEST PASSED: %s USE_HSM=%0d frames=%0d products=%0d",
                 precision_name, USE_HSM, completed_frames, 16 * completed_frames);
        $display("Activity interval: %0.6f ns to %0.6f ns (clear + input + drain)",
                 4.0 * CLOCK_PERIOD_NS, (4.0 + 19.0 * num_frames) * CLOCK_PERIOD_NS);
        $finish;
    end
endmodule
