`timescale 1ns/1ps
`include "tiled_mac_vectors_config.vh"

// Two PEs, BASIC and HSM, see identical external streams. An independent token
// scoreboard tracks operand-hop -> product -> accumulator timing. Python supplies
// each actual product and running sum; it does not model forwarding/control.
module systolic_pe_signed_tb;
    reg clk = 0, rst_n = 1, clear = 0, advance = 0;
    reg [1:0] mode = 0;
    reg [15:0] a_in = 0, b_in = 0;
    reg a_valid_in = 0, b_valid_in = 0;
    wire signed [15:0] hsm_a, hsm_b, basic_a, basic_b;
    wire hsm_av, hsm_bv, basic_av, basic_bv;
    wire signed [35:0] hsm_acc, basic_acc;
    wire [1:0] hsm_acc_mode, basic_acc_mode;
    wire [4:0] hsm_count, basic_count;
    wire hsm_done, basic_done, hsm_error, basic_error;
    wire [15:0] hsm_tiles, basic_tiles;
    reg [103:0] vectors [0:`MAC_VECTOR_COUNT-1];

    // Expected forwarding state is separate from the two downstream stages.
    reg [15:0] expected_a = 0, expected_b = 0;
    reg [1:0] expected_a_mode = 0, expected_b_mode = 0;
    reg expected_av = 0, expected_bv = 0;
    reg [31:0] operand_product = 0, expected_product = 0;
    reg [35:0] operand_prefix = 0, pending_prefix = 0, expected_acc = 0;
    reg [1:0] expected_product_mode = 0, expected_acc_mode = 0, frame_mode = 0;
    reg expected_pending = 0, expected_error = 0;
    integer expected_count = 0, accepted_count = 0;
    integer clock_checks = 0, reset_checks = 0, completed_frames = 0;
    integer pair_checks = 0, committed_checks = 0, forwarding_checks = 0;
    integer stall_checks = 0, one_sided_checks = 0, error_checks = 0;
    integer frame_index, term_index, index;
    reg [1:0] padding, selected_mode;
    reg [15:0] selected_a, selected_b;
    reg [31:0] selected_product;
    reg [35:0] selected_prefix;

    systolic_pe_signed #(.USE_HSM(1)) dut_hsm (
        .clk(clk), .rst_n(rst_n), .clear(clear), .advance(advance), .mode(mode),
        .a_in(a_in), .b_in(b_in), .a_valid_in(a_valid_in), .b_valid_in(b_valid_in),
        .a_out(hsm_a), .b_out(hsm_b), .a_valid_out(hsm_av), .b_valid_out(hsm_bv),
        .acc_q(hsm_acc), .acc_mode_q(hsm_acc_mode), .term_count(hsm_count),
        .result_valid(hsm_done), .protocol_error(hsm_error), .tile_enabled(hsm_tiles)
    );
    systolic_pe_signed #(.USE_HSM(0)) dut_basic (
        .clk(clk), .rst_n(rst_n), .clear(clear), .advance(advance), .mode(mode),
        .a_in(a_in), .b_in(b_in), .a_valid_in(a_valid_in), .b_valid_in(b_valid_in),
        .a_out(basic_a), .b_out(basic_b), .a_valid_out(basic_av), .b_valid_out(basic_bv),
        .acc_q(basic_acc), .acc_mode_q(basic_acc_mode), .term_count(basic_count),
        .result_valid(basic_done), .protocol_error(basic_error), .tile_enabled(basic_tiles)
    );
    always #5 clk = ~clk;

    function automatic mode_ok(input [1:0] selected);
        case (selected) 0, 1, 2: mode_ok = 1; default: mode_ok = 0; endcase
    endfunction
    function automatic [15:0] tile_mask(input [1:0] selected);
        case (selected) 0: tile_mask = 16'h0001; 1: tile_mask = 16'h0033;
            2: tile_mask = 16'hffff; default: tile_mask = 0; endcase
    endfunction
    function automatic [15:0] decode(input [1:0] selected, input [15:0] word);
        integer width, value;
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
    task automatic reset_scoreboard;
        begin
            expected_a = 0; expected_b = 0; expected_a_mode = 0; expected_b_mode = 0;
            expected_av = 0; expected_bv = 0; operand_product = 0; operand_prefix = 0;
            expected_product = 0; expected_product_mode = 0; expected_pending = 0;
            pending_prefix = 0; expected_acc = 0; expected_acc_mode = 0;
            expected_error = 0; expected_count = 0; accepted_count = 0; frame_mode = 0;
        end
    endtask
    task automatic check_outputs(input string description);
        begin
            if (hsm_a !== expected_a || basic_a !== expected_a ||
                hsm_b !== expected_b || basic_b !== expected_b ||
                hsm_av !== expected_av || basic_av !== expected_av ||
                hsm_bv !== expected_bv || basic_bv !== expected_bv ||
                dut_hsm.a_mode_q !== expected_a_mode || dut_basic.a_mode_q !== expected_a_mode ||
                dut_hsm.b_mode_q !== expected_b_mode || dut_basic.b_mode_q !== expected_b_mode)
                $fatal(1, "%s: operand forwarding/data/mode/valid differs from one-hop expectation", description);
            if (hsm_acc !== expected_acc || basic_acc !== expected_acc ||
                hsm_acc_mode !== expected_acc_mode || basic_acc_mode !== expected_acc_mode ||
                hsm_count !== expected_count[4:0] || basic_count !== expected_count[4:0] ||
                hsm_done !== (expected_count == 16) || basic_done !== (expected_count == 16) ||
                hsm_error !== expected_error || basic_error !== expected_error)
                $fatal(1, "%s: expected sum=%0d count=%0d error=%b; HSM sum=%0d count=%0d error=%b; BASIC sum=%0d count=%0d error=%b",
                       description, $signed(expected_acc), expected_count, expected_error,
                       hsm_acc, hsm_count, hsm_error, basic_acc, basic_count, basic_error);
            if (dut_hsm.mac.product_q !== expected_product || dut_basic.mac.product_q !== expected_product ||
                dut_hsm.mac.product_mode_q !== expected_product_mode ||
                dut_basic.mac.product_mode_q !== expected_product_mode ||
                dut_hsm.mac.product_valid_q !== expected_pending ||
                dut_basic.mac.product_valid_q !== expected_pending)
                $fatal(1, "%s: operand/product/accumulator stage alignment failed", description);
        end
    endtask

    task automatic cycle(input bit clr, adv, av, bv, input [1:0] selected,
                         input [15:0] word_a, word_b, input [31:0] golden_product,
                         input [35:0] golden_prefix, input string description);
        bit old_pair, can_accept, accepted, next_error;
        reg [15:0] expected_tiles;
        begin
            @(negedge clk);
            clear = clr; advance = adv; mode = selected;
            a_in = word_a; b_in = word_b; a_valid_in = av; b_valid_in = bv;
            old_pair = expected_av && expected_bv;
            can_accept = !clr && adv && mode_ok(expected_a_mode) &&
                         accepted_count < 16 && (accepted_count == 0 || expected_a_mode == frame_mode);
            accepted = old_pair && expected_a_mode == expected_b_mode && !expected_error && can_accept;
            expected_tiles = accepted ? tile_mask(expected_a_mode) : 16'd0;
            #1;
            check_outputs({description, " before the sampling edge"});
            if (hsm_tiles !== expected_tiles || basic_tiles !== expected_tiles)
                $fatal(1, "%s: incorrect active tile mask before edge", description);
            if (accepted && (dut_hsm.mac.multiplier_product !== operand_product ||
                             dut_basic.mac.multiplier_product !== operand_product))
                $fatal(1, "%s: registered-operand product differs from Python", description);
            if (!accepted && (dut_hsm.mac.multiplier_product !== 32'd0 ||
                              dut_basic.mac.multiplier_product !== 32'd0))
                $fatal(1, "%s: inactive multiplier not isolated", description);

            if (clr) reset_scoreboard();
            else if (adv) begin
                // Model every stage from OLD token state, then install new input.
                next_error = expected_error || ((av || bv) && !mode_ok(selected)) ||
                             (old_pair && (expected_a_mode != expected_b_mode || !can_accept));
                if (expected_pending) begin
                    expected_acc = pending_prefix; expected_count = expected_count + 1;
                    expected_acc_mode = expected_product_mode; committed_checks = committed_checks + 1;
                end
                expected_pending = accepted;
                if (accepted) begin
                    if (accepted_count == 0) frame_mode = expected_a_mode;
                    accepted_count = accepted_count + 1; pair_checks = pair_checks + 1;
                    expected_product = operand_product; expected_product_mode = expected_a_mode;
                    pending_prefix = operand_prefix;
                end
                expected_error = next_error;
                expected_av = av && mode_ok(selected); expected_bv = bv && mode_ok(selected);
                if (expected_av) begin
                    expected_a = decode(selected, word_a); expected_a_mode = selected;
                    forwarding_checks = forwarding_checks + 1;
                end
                if (expected_bv) begin
                    expected_b = decode(selected, word_b); expected_b_mode = selected;
                    forwarding_checks = forwarding_checks + 1;
                end
                operand_product = golden_product; operand_prefix = golden_prefix;
                if (av != bv) one_sided_checks = one_sided_checks + 1;
            end else stall_checks = stall_checks + 1;
            @(posedge clk); #1;
            check_outputs(description); clock_checks = clock_checks + 1;
            if (expected_error) error_checks = error_checks + 1;
        end
    endtask
    task automatic load_vector(input integer vector_index);
        begin
            {padding, selected_mode, selected_a, selected_b, selected_product, selected_prefix} = vectors[vector_index];
            if (padding !== 0 || !mode_ok(selected_mode)) $fatal(1, "Malformed Python vector");
        end
    endtask
    task automatic async_reset;
        begin
            @(negedge clk); #2; rst_n = 0; reset_scoreboard();
            #1; check_outputs("PE asynchronous assertion before next clock");
            if (hsm_tiles !== 0 || basic_tiles !== 0) $fatal(1, "Reset did not isolate multiplier");
            reset_checks = reset_checks + 1;
            @(posedge clk); #1; check_outputs("PE reset held at rising edge"); reset_checks = reset_checks + 1;
            @(negedge clk); rst_n = 1; clear = 0; advance = 0;
            a_valid_in = 0; b_valid_in = 0; mode = 0; a_in = 0; b_in = 0;
        end
    endtask

    initial begin
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("systolic_pe_signed.vcd"); $dumpvars(0, systolic_pe_signed_tb);
        end
        $readmemh(`MAC_VECTOR_FILE, vectors);
        if (`MAC_VECTOR_COUNT != 16 * `MAC_FRAME_COUNT) $fatal(1, "Invalid frame size");
        for (index = 0; index < `MAC_VECTOR_COUNT; index = index + 1)
            if ($isunknown(vectors[index])) $fatal(1, "Missing Python vector %0d", index);
        async_reset();
        cycle(0, 1, 1, 1, 0, 0, 0, 0, 0, "Zero captures at the operand hop");
        cycle(0, 1, 0, 0, 3, 0, 0, 0, 0, "Zero moves to product register");
        cycle(0, 1, 0, 0, 3, 0, 0, 0, 0, "Valid zero counts at accumulator");
        cycle(1, 0, 1, 1, 2, 16'hffff, 16'hffff, 0, 0, "Clear overrides stall and new operands");

        // Unknown upper fields must be ignored before both forwarding and MAC.
        cycle(0, 1, 1, 1, 0, {12'hxxx, 4'hd}, {12'hzzz, 4'h5}, -32'sd15, -36'sd15, "INT4 signed forwarding");
        cycle(0, 1, 0, 0, 2'bxx, 16'hxxxx, 16'hxxxx, 0, 0, "Stored mode survives live-mode change");
        cycle(0, 1, 0, 0, 2'bxx, 16'hxxxx, 16'hxxxx, 0, 0, "Stored product drains under idle unknown mode");
        cycle(1, 1, 0, 0, 0, 0, 0, 0, 0, "New frame");
        cycle(0, 1, 1, 1, 1, {8'hxx, 8'hfd}, {8'hzz, 8'h05}, -32'sd15, -36'sd15, "INT8 signed forwarding");
        cycle(0, 0, 1, 1, 2'bxx, 16'hxxxx, 16'hzzzz, 0, 0, "Whole PE stalls with pending operands");
        cycle(0, 1, 0, 0, 3, 0, 0, 0, 0, "Pending product capture");
        async_reset();

        // Separate unpaired tokens pass onward but must not create a product.
        cycle(0, 1, 1, 0, 0, 16'hd, 16'hxxxx, 0, 0, "A-only forwarding");
        cycle(0, 1, 0, 1, 0, 16'hxxxx, 16'h5, 0, 0, "B-only forwarding");
        cycle(0, 1, 0, 0, 0, 0, 0, 0, 0, "No accidental pairing across cycles");
        cycle(0, 1, 0, 0, 0, 0, 0, 0, 0, "Unpaired streams drained");

        cycle(0, 1, 1, 0, 3, 1, 0, 0, 0, "Valid reserved-mode token flags error");
        cycle(0, 1, 1, 1, 0, 1, 1, 1, 1, "Error holds until clear");
        cycle(0, 1, 0, 0, 0, 0, 0, 0, 0, "Error blocks new local pairs");
        cycle(1, 0, 0, 0, 0, 0, 0, 0, 0, "Clear removes sticky error");
        cycle(0, 1, 0, 1, 2'bxx, 0, 16'hxxxx, 0, 0, "Valid unknown-mode token flags error");
        cycle(1, 1, 0, 0, 0, 0, 0, 0, 0, "Clear unknown-mode error");
        cycle(0, 1, 1, 1, 0, 1, 1, 1, 1, "First pair fixes precision");
        cycle(0, 1, 1, 1, 1, 2, 2, 4, 5, "Different precision enters forwarding stage");
        cycle(0, 1, 0, 0, 1, 0, 0, 0, 0, "Changed frame precision rejected locally");
        cycle(0, 1, 0, 0, 1, 0, 0, 0, 0, "Rejected product is not counted");
        async_reset();

        // Flush all three pending locations: accumulator + product + operands.
        load_vector(16);
        cycle(0, 1, 1, 1, selected_mode, selected_a, selected_b, selected_product, selected_prefix, "Flush probe input 1");
        load_vector(17);
        cycle(0, 1, 1, 1, selected_mode, selected_a, selected_b, selected_product, selected_prefix, "Flush probe input 2");
        load_vector(18);
        cycle(0, 1, 1, 1, selected_mode, selected_a, selected_b, selected_product, selected_prefix, "All three stages occupied");
        cycle(1, 0, 1, 1, selected_mode, 1, 1, 0, 0, "Clear flushes every stage");
        cycle(0, 1, 0, 0, 0, 0, 0, 0, 0, "No ghost product after clear");

        for (frame_index = 0; frame_index < `MAC_FRAME_COUNT; frame_index = frame_index + 1) begin
            load_vector(16 * frame_index);
            cycle(1, frame_index[0], 0, 0, selected_mode, 0, 0, 0, 0, "Start Python dot product");
            for (term_index = 0; term_index < 16; term_index = term_index + 1) begin
                load_vector(16 * frame_index + term_index);
                if (term_index == 3 || term_index == 13)
                    cycle(0, 0, 1, 1, 2'bxx, 16'hxxxx, 16'hzzzz, 0, 0, "Global stall retains every stage");
                if (term_index == 6)
                    cycle(0, 1, 0, 0, 3, 16'hxxxx, 16'hxxxx, 0, 0, "Advancing bubble drains pending work");
                if (term_index == 9) begin
                    cycle(0, 1, 1, 0, selected_mode, selected_a, 16'hxxxx, 0, 0, "Forward A-only fill token");
                    cycle(0, 1, 0, 1, selected_mode, 16'hxxxx, selected_b, 0, 0, "Forward B-only drain token");
                end
                cycle(0, 1, 1, 1, selected_mode, selected_a, selected_b,
                      selected_product, selected_prefix, "Python product/prefix through complete PE");
            end
            cycle(0, 1, 0, 0, selected_mode, 0, 0, 0, 0, "Drain operand stage into product stage");
            cycle(0, 1, 0, 0, selected_mode, 0, 0, 0, 0, "Drain sixteenth product and complete result");
            if (expected_count != 16) $fatal(1, "Frame did not consume sixteen products");
            cycle(0, 0, 1, 1, 2'bxx, 16'hxxxx, 16'hzzzz, 0, 0, "Completed result holds during stall");
            cycle(0, 1, 0, 0, selected_mode, 0, 0, 0, 0, "Completed result holds during idle");
            completed_frames = completed_frames + 1;
        end
        // The PE stream cannot retry: an extra aligned pair is an explicit error.
        cycle(0, 1, 1, 1, selected_mode, 1, 1, 1, 0, "Offer seventeenth aligned input");
        cycle(0, 1, 0, 0, selected_mode, 0, 0, 0, 0, "Reject over-capacity pair without changing sum");
        cycle(1, 1, 0, 0, 0, 0, 0, 0, 0, "Clear completed frame and overflow error");
        $display("SINGLE PE PYTHON/RTL TEST PASSED (HSM AND BASIC)");
        $display("Completed dot products: %0d; Python input pairs: %0d", completed_frames, `MAC_VECTOR_COUNT);
        $display("Clocked checks=%0d; reset checks=%0d; local pairs=%0d; commits=%0d; forwarded operands=%0d",
                 clock_checks, reset_checks, pair_checks, committed_checks, forwarding_checks);
        $display("Stall checks=%0d; one-sided stream checks=%0d; sticky-error checks=%0d",
                 stall_checks, one_sided_checks, error_checks);
        $finish;
    end
    initial begin #100000; $fatal(1, "Single PE test timed out"); end
endmodule
