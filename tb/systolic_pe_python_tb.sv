`timescale 1ns/1fs

// Stimulus and ALL expected arithmetic/control values come from Python.
// This bench performs no reference multiplication or reference accumulation.
// Drive controls while clock is LOW: the DUT contains latch-based clock gates.
module systolic_pe_python_tb #(
    parameter integer USE_HSM = 0,
    parameter real CLOCK_PERIOD_NS = 3.333
);
    localparam integer PACK_BITS = 166;
    localparam integer STATE_BITS = 118;
    localparam real HALF_PERIOD = CLOCK_PERIOD_NS / 2.0;
    reg clk = 0, rst_n = 1, clear = 0, advance = 0;
    reg [1:0] mode = 0;
    reg [15:0] a_in = 0, b_in = 0;
    reg a_valid_in = 0, b_valid_in = 0;
    wire signed [15:0] a_out, b_out;
    wire a_valid_out, b_valid_out;
    wire signed [35:0] acc_q;
    wire [1:0] acc_mode_q;
    wire [4:0] term_count;
    wire result_valid, protocol_error;
    wire [15:0] tile_enabled;

    systolic_pe_signed #(.USE_HSM(USE_HSM)) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .advance(advance), .mode(mode),
        .a_in(a_in), .b_in(b_in), .a_valid_in(a_valid_in), .b_valid_in(b_valid_in),
        .a_out(a_out), .b_out(b_out), .a_valid_out(a_valid_out), .b_valid_out(b_valid_out),
        .acc_q(acc_q), .acc_mode_q(acc_mode_q), .term_count(term_count),
        .result_valid(result_valid), .protocol_error(protocol_error), .tile_enabled(tile_enabled)
    );

    // Order and widths match verification/reference_model.py:FIELDS exactly.
    wire [PACK_BITS-1:0] observed = {
        a_out, b_out, a_valid_out, b_valid_out, acc_q, acc_mode_q, term_count,
        result_valid, protocol_error, dut.mac.product_q, dut.mac.product_mode_q,
        dut.mac.product_valid_q, dut.a_mode_q, dut.b_mode_q, tile_enabled,
        dut.mac.multiplier_product
    };

    string vector_path, result_path, status_path, vcd_path, trailing;
    integer fd, results_fd, status_fd, row_count, parsed, row, vector_cycle;
    integer errors = 0, samples = 0, high_checks = 0;
    reg v_rst, v_clear, v_advance, v_av, v_bv, probe_high;
    reg [1:0] v_mode;
    reg [15:0] v_a, v_b;
    reg [PACK_BITS-1:0] expected_pre, expected_post;
    reg [STATE_BITS-1:0] state_after_edge;

    task automatic restore_inputs;
        begin
            rst_n = v_rst; clear = v_clear; advance = v_advance; mode = v_mode;
            a_in = v_a; b_in = v_b; a_valid_in = v_av; b_valid_in = v_bv;
        end
    endtask

    task automatic sample(input string phase_name, input reg [PACK_BITS-1:0] expected);
        begin
            $fwrite(results_fd, "%0d,%s,%042h,%0d,%0d,%0d,%0d,%0d,%0d\n",
                    row, phase_name, observed, a_out, b_out, acc_q, term_count,
                    result_valid, protocol_error);
            samples = samples + 1;
            // Four-state inequality also rejects ANY unexpected X or Z output.
            if (observed !== expected) begin
                errors = errors + 1;
                if (errors <= 12) begin
                    $display("MISMATCH cycle=%0d phase=%s sum=%0d count=%0d done=%b error=%b",
                             row, phase_name, acc_q, term_count, result_valid, protocol_error);
                    $display("  Python expected: %042h", expected);
                    $display("  RTL observed:    %042h", observed);
                end
            end
        end
    endtask

    task automatic check_high_state;
        begin
            high_checks = high_checks + 1;
            // Low 48 bits are combinational tile/product outputs, which may
            // legitimately change when controls change during this probe.
            if (observed[PACK_BITS-1:48] !== state_after_edge) begin
                errors = errors + 1;
                if (errors <= 12)
                    $display("MISMATCH cycle=%0d: stored state changed while clk stayed HIGH", row);
            end
        end
    endtask

    initial begin
        if (HALF_PERIOD <= 0.030) $fatal(1, "Clock period too small for TB sampling delays");
        if (!$value$plusargs("VECTORS=%s", vector_path)) vector_path = "vectors/vectors.txt";
        if (!$value$plusargs("RESULTS=%s", result_path)) result_path = "results/rtl_results.csv";
        if (!$value$plusargs("STATUS=%s", status_path)) status_path = "results/simulation_status.txt";
        if ($value$plusargs("VCD=%s", vcd_path)) begin
            $dumpfile(vcd_path);
            $dumpvars(0, systolic_pe_python_tb.dut);
        end
        fd = $fopen(vector_path, "r");
        results_fd = $fopen(result_path, "w");
        status_fd = $fopen(status_path, "w");
        if (!fd || !results_fd || !status_fd)
            $fatal(1, "Cannot open input/output file. Generate vectors and create results/ first.");
        $fwrite(status_fd, "RUNNING\n");
        $fflush(status_fd);
        $fwrite(results_fd, "cycle,phase,observed,a_signed,b_signed,acc_signed,term_count,result_valid,protocol_error\n");
        parsed = $fscanf(fd, "%d", row_count);
        if (parsed != 1 || row_count < 1 || row_count > 10000000)
            $fatal(1, "Invalid vector count");
        $display("PYTHON-GOLDEN PE TEST: USE_HSM=%0d cycles=%0d clock=%0.3f ns", USE_HSM, row_count, CLOCK_PERIOD_NS);

        for (row = 0; row < row_count; row = row + 1) begin
            parsed = $fscanf(fd, "%d %d %d %d %b %h %h %d %d %h %h %d",
                             vector_cycle, v_rst, v_clear, v_advance, v_mode, v_a, v_b,
                             v_av, v_bv, expected_pre, expected_post, probe_high);
            if (parsed != 12 || vector_cycle != row ||
                (^expected_pre === 1'bx) || (^expected_post === 1'bx))
                $fatal(1, "Malformed/incomplete Python vector at cycle %0d (fields=%0d)", row, parsed);
            clk = 0;
            #0.010;
            restore_inputs();
            #0.010;
            // A reset assertion is checked here BEFORE the next rising edge.
            sample("pre", expected_pre);
            #(HALF_PERIOD - 0.020);
            clk = 1;
            #0.010;
            sample("post", expected_post);
            state_after_edge = observed[PACK_BITS-1:48];

            if (probe_high) begin
                // Latch-based gating must not create a new rising clock edge
                // in storage when enables/control/data change while clk=1.
                clear = ~v_clear; advance = ~v_advance; mode = 2'b11;
                a_valid_in = 1; b_valid_in = 1; a_in = ~v_a; b_in = ~v_b;
                #0.002;
                check_high_state();
                restore_inputs();
                #0.002;
                check_high_state();
                #(HALF_PERIOD - 0.014);
            end else begin
                #(HALF_PERIOD - 0.010);
            end
            if ((row + 1) % 20000 == 0)
                $display("  checked %0d/%0d cycles; mismatches=%0d", row + 1, row_count, errors);
        end
        clk = 0;
        parsed = $fscanf(fd, "%s", trailing);
        if (parsed == 1) $fatal(1, "Extra content after declared vector count");
        $fclose(fd);
        $fclose(results_fd);
        $fclose(status_fd);
        status_fd = $fopen(status_path, "w");
        if (!status_fd) $fatal(1, "Cannot write final status");
        if (errors != 0) begin
            $fwrite(status_fd, "FAIL cycles=%0d samples=%0d high_checks=%0d errors=%0d USE_HSM=%0d\n",
                    row_count, samples, high_checks, errors, USE_HSM);
            $fclose(status_fd);
            $fatal(1, "PYTHON-GOLDEN PE TEST FAILED: %0d mismatches", errors);
        end
        $fwrite(status_fd, "PASS cycles=%0d samples=%0d high_checks=%0d errors=0 USE_HSM=%0d\n",
                row_count, samples, high_checks, USE_HSM);
        $fclose(status_fd);
        $display("PYTHON-GOLDEN PE TEST PASSED: cycles=%0d samples=%0d high_checks=%0d errors=0",
                 row_count, samples, high_checks);
        $finish;
    end
    initial begin
        #1000000000;
        $fatal(1, "PE test watchdog timeout");
    end
endmodule
