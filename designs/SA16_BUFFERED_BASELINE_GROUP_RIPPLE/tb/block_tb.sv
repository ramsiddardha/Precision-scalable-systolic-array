`timescale 1ns/1fs

module block_tb;
    localparam int N = 16, WORDS = N*N, STEPS = 48, RESULT_BITS = 36;
    // Start + paired writes + mesh clear + compute + check + DONE-to-IDLE.
    localparam int FRAME_CYCLES = 1 + WORDS + 1 + STEPS + 1 + 1;
    localparam int CAPTURE_START = 4 + FRAME_CYCLES + 1;

    logic clk = 0, rst_n = 1, clear = 0, start = 0, input_valid = 0;
    logic [1:0] mode = 0;
    logic [15:0] a_data = 0, b_data = 0;
    wire start_ready, input_ready, busy, done, error;
    wire [RESULT_BITS*WORDS-1:0] result_data_flat;
    wire [WORDS-1:0] result_valid_flat;
    systolic_array_power_top dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .start(start), .mode(mode),
        .input_valid(input_valid), .a_data(a_data), .b_data(b_data),
        .start_ready(start_ready), .input_ready(input_ready), .busy(busy),
        .done(done), .error(error), .result_data_flat(result_data_flat),
        .result_valid_flat(result_valid_flat)
    );

    integer selected_mode = 0, num_frames = 10, completed_frames = 0;
    logic capture_ready = 0, capture_done = 0;
    longint unsigned clock_period_fs = 3333000;
    longint unsigned capture_begin_fs = 0, capture_end_fs = 0;
    logic [31:0] initial_random_seed = 32'h1a2b3c4d, rng_state;
    realtime period_ns = 3.333;
    integer signed matrix_a [0:N-1][0:N-1], matrix_b [0:N-1][0:N-1];

    initial begin
        if ($value$plusargs("CLOCK_PERIOD_NS=%f", period_ns)) begin end
        clock_period_fs = $rtoi(period_ns * 1.0e6 + 0.5);
        if (clock_period_fs != 3333000 && clock_period_fs != 3000000)
            $fatal(1, "Expected a 3.333 or 3.000 ns clock");
        forever #(period_ns / 2.0) clk = ~clk;
    end

    function automatic logic [31:0] next_word(input logic [31:0] state);
        logic [31:0] word;
        word = state ^ (state << 13);
        word = word ^ (word >> 17);
        next_word = word ^ (word << 5);
    endfunction

    function automatic integer signed decode(input logic [31:0] word);
        case (selected_mode)
            0: decode = $signed(word[3:0]);
            1: decode = $signed(word[7:0]);
            2: decode = $signed(word[15:0]);
            default: decode = 0;
        endcase
    endfunction

    function automatic logic [15:0] encode(input integer signed value);
        case (selected_mode)
            0: encode = {12'b0, value[3:0]};
            1: encode = {8'b0, value[7:0]};
            2: encode = value[15:0];
            default: encode = '0;
        endcase
    endfunction

    task automatic check_results(input int frame);
        longint signed expected, actual;
        if ({done, error, busy, start_ready} !== 4'b1010 ||
            result_valid_flat !== {WORDS{1'b1}})
            $fatal(1, "Frame %0d completion failed: done=%b error=%b busy=%b", frame, done, error, busy);
        for (int row = 0; row < N; row++) begin
            for (int col = 0; col < N; col++) begin
                expected = 0;
                for (int k = 0; k < N; k++) begin
                    expected += longint'(matrix_a[row][k]) * longint'(matrix_b[k][col]);
                end
                actual = $signed(result_data_flat[RESULT_BITS*(N*row+col) +: RESULT_BITS]);
                if (actual !== expected) begin
                    $fatal(1, "Frame %0d C[%0d,%0d] actual=%0d expected=%0d",
                           frame, row, col, actual, expected);
                end
            end
        end
    endtask

    // Entry and exit are falling edges. The final edge rearms start_ready.
    task automatic run_matrix(input int frame, input bit warmup);
        if (start_ready !== 1'b1) $fatal(1, "Frame %0d start not ready", frame);
        start = 1;
        @(posedge clk);
        #0.001;
        if ({busy, input_ready, error} !== 3'b110)
            $fatal(1, "Frame %0d did not enter LOAD", frame);
        for (int word_index = 0; word_index < WORDS; word_index++) begin
            @(negedge clk);
            start = 0;
            input_valid = 1;
            a_data = warmup ? 16'd0 : encode(matrix_a[word_index/N][word_index%N]);
            b_data = warmup ? 16'd0 : encode(matrix_b[word_index/N][word_index%N]);
            @(posedge clk);
            if (input_ready !== 1'b1) $fatal(1, "Frame %0d rejected pair %0d", frame, word_index);
        end
        @(negedge clk);
        input_valid = 0;
        a_data = 0;
        b_data = 0;
        @(posedge clk); // Mesh clear.
        repeat (STEPS) begin
            @(posedge clk);
            #0.001;
            if ({done, error, input_ready} !== 3'b000)
                $fatal(1, "Frame %0d protocol error during computation", frame);
        end
        @(posedge clk); // Completion check.
        #0.001;
        check_results(frame);
        @(posedge clk); // DONE -> IDLE.
        @(negedge clk);
    endtask

    initial begin
        if ($value$plusargs("POWER_MODE=%d", selected_mode)) begin end
        if ($value$plusargs("NUM_FRAMES=%d", num_frames)) begin end
        if ($value$plusargs("SEED=%h", initial_random_seed)) begin end
        if (selected_mode < 0 || selected_mode > 2 || num_frames < 1 || initial_random_seed == 0)
            $fatal(1, "Invalid workload configuration");
        rng_state = initial_random_seed;
        #0.001 rst_n = 0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        mode = 2;
        for (int row = 0; row < N; row++) begin
            for (int col = 0; col < N; col++) begin
                matrix_a[row][col] = 0;
                matrix_b[row][col] = 0;
            end
        end
        @(negedge clk);
        // Prime all physical buffer bits, including inactive slices, outside capture.
        run_matrix(-1, 1);
        mode = selected_mode[1:0];
        capture_ready = 1;
        @(negedge clk);
        capture_begin_fs = longint'($realtime * 1.0e6);
        for (int frame = 0; frame < num_frames; frame++) begin
            for (int row = 0; row < N; row++) begin
                for (int col = 0; col < N; col++) begin
                    rng_state = next_word(rng_state);
                    matrix_a[row][col] = decode(rng_state);
                    rng_state = next_word(rng_state);
                    matrix_b[row][col] = decode(rng_state);
                end
            end
            run_matrix(frame, 0);
            completed_frames++;
        end
        capture_end_fs = longint'($realtime * 1.0e6);
        if (capture_begin_fs != CAPTURE_START * clock_period_fs ||
            capture_end_fs - capture_begin_fs != FRAME_CYCLES * longint'(num_frames) * clock_period_fs)
            $fatal(1, "Unexpected capture window");
        capture_done = 1;
        $display("PASS mode=%0d matrices=%0d checked_outputs=%0d checked_macs=%0d",
                 selected_mode, completed_frames, WORDS*completed_frames,
                 N*WORDS*completed_frames);
        $finish;
    end
endmodule
