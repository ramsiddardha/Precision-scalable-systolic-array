`timescale 1ns/1fs

// Compare the complete optimized PE with the earlier BASIC_ICG PE.
// Independent signed 64-bit arithmetic generates product and prefix vectors;
// a separate token scoreboard checks forwarding, pipeline timing and protocol.
module pe_combined_equivalence_tb;
    localparam integer MAC_FRAME_COUNT=90;
    localparam integer MAC_VECTOR_COUNT=16*MAC_FRAME_COUNT;
    reg clk = 0, rst_n = 1, clear = 0, advance = 0;
    reg [1:0] mode = 0;
    reg [15:0] a_in = 0, b_in = 0;
    reg a_valid_in = 0, b_valid_in = 0;
    wire signed [15:0] ref_a, ref_b, opt_a, opt_b;
    wire ref_av, ref_bv, opt_av, opt_bv;
    wire signed [35:0] ref_acc, opt_acc;
    wire [1:0] ref_acc_mode, opt_acc_mode;
    wire [4:0] ref_count, opt_count;
    wire ref_done, opt_done, ref_error, opt_error;
    wire [15:0] ref_tiles, opt_tiles;
    reg [103:0] vectors [0:MAC_VECTOR_COUNT-1];

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

    systolic_pe_signed_reference #(.USE_HSM(0)) dut_reference (
        .clk(clk), .rst_n(rst_n), .clear(clear), .advance(advance), .mode(mode),
        .a_in(a_in), .b_in(b_in), .a_valid_in(a_valid_in), .b_valid_in(b_valid_in),
        .a_out(ref_a), .b_out(ref_b), .a_valid_out(ref_av), .b_valid_out(ref_bv),
        .acc_q(ref_acc), .acc_mode_q(ref_acc_mode), .term_count(ref_count),
        .result_valid(ref_done), .protocol_error(ref_error), .tile_enabled(ref_tiles)
    );
    systolic_pe_signed #(.USE_HSM(0)) dut_candidate (
        .clk(clk), .rst_n(rst_n), .clear(clear), .advance(advance), .mode(mode),
        .a_in(a_in), .b_in(b_in), .a_valid_in(a_valid_in), .b_valid_in(b_valid_in),
        .a_out(opt_a), .b_out(opt_b), .a_valid_out(opt_av), .b_valid_out(opt_bv),
        .acc_q(opt_acc), .acc_mode_q(opt_acc_mode), .term_count(opt_count),
        .result_valid(opt_done), .protocol_error(opt_error), .tile_enabled(opt_tiles)
    );
    always #1.6665 clk = ~clk;

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
            if (ref_a !== expected_a || opt_a !== expected_a ||
                ref_b !== expected_b || opt_b !== expected_b ||
                ref_av !== expected_av || opt_av !== expected_av ||
                ref_bv !== expected_bv || opt_bv !== expected_bv ||
                dut_reference.a_mode_q !== expected_a_mode || dut_candidate.a_mode_q !== expected_a_mode ||
                dut_reference.b_mode_q !== expected_b_mode || dut_candidate.b_mode_q !== expected_b_mode)
                $fatal(1, "%s: operand forwarding/data/mode/valid differs from one-hop expectation", description);
            if (ref_acc !== expected_acc || opt_acc !== expected_acc ||
                ref_acc_mode !== expected_acc_mode || opt_acc_mode !== expected_acc_mode ||
                ref_count !== expected_count[4:0] || opt_count !== expected_count[4:0] ||
                ref_done !== (expected_count == 16) || opt_done !== (expected_count == 16) ||
                ref_error !== expected_error || opt_error !== expected_error)
                $fatal(1, "%s: expected sum=%0d count=%0d error=%b; REFERENCE sum=%0d count=%0d error=%b; CANDIDATE sum=%0d count=%0d error=%b",
                       description, $signed(expected_acc), expected_count, expected_error,
                       ref_acc, ref_count, ref_error, opt_acc, opt_count, opt_error);
            if (dut_reference.mac.product_q !== expected_product || dut_candidate.mac.product_q !== expected_product ||
                dut_reference.mac.product_mode_q !== expected_product_mode ||
                dut_candidate.mac.product_mode_q !== expected_product_mode ||
                dut_reference.mac.product_valid_q !== expected_pending ||
                dut_candidate.mac.product_valid_q !== expected_pending)
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
            #0.001;
            check_outputs({description, " before the sampling edge"});
            if (ref_tiles !== expected_tiles || opt_tiles !== expected_tiles)
                $fatal(1, "%s: incorrect active tile mask before edge", description);
            if (accepted && (dut_reference.mac.multiplier_product !== operand_product ||
                             dut_candidate.mac.multiplier_product !== operand_product))
                $fatal(1, "%s: registered-operand product differs from the arithmetic oracle", description);
            if (!accepted && (dut_reference.mac.multiplier_product !== 32'd0 ||
                              dut_candidate.mac.multiplier_product !== 32'd0))
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
            @(posedge clk); #0.001;
            check_outputs(description); clock_checks = clock_checks + 1;
            if (expected_error) error_checks = error_checks + 1;
        end
    endtask
    task automatic load_vector(input integer vector_index);
        begin
            {padding, selected_mode, selected_a, selected_b, selected_product, selected_prefix} = vectors[vector_index];
            if (padding !== 0 || !mode_ok(selected_mode)) $fatal(1, "Malformed golden arithmetic vector");
        end
    endtask
    task automatic async_reset;
        begin
            @(negedge clk); #0.100; rst_n = 0; reset_scoreboard();
            #0.001; check_outputs("PE asynchronous assertion before next clock");
            if (ref_tiles !== 0 || opt_tiles !== 0) $fatal(1, "Reset did not isolate multiplier");
            reset_checks = reset_checks + 1;
            @(posedge clk); #0.001; check_outputs("PE reset held at rising edge"); reset_checks = reset_checks + 1;
            @(negedge clk); rst_n = 1; clear = 0; advance = 0;
            a_valid_in = 0; b_valid_in = 0; mode = 0; a_in = 0; b_in = 0;
        end
    endtask

    function automatic [31:0] next_random(input [31:0] value);
        reg [31:0] t;
        begin t=value^(value<<13);t=t^(t>>17);next_random=t^(t<<5);end
    endfunction
    task automatic generate_vectors;
        integer f,t,minimum,maximum;
        reg [1:0] precision;
        reg [31:0] rng;
        reg [15:0] aa,bb;
        longint signed va,vb,p,acc;
        begin
            rng=32'h16b4d9a3;
            for(f=0;f<MAC_FRAME_COUNT;f++)begin
                precision=f%3;acc=0;
                case(precision)
                    0:begin minimum=-8;maximum=7;end
                    1:begin minimum=-128;maximum=127;end
                    default:begin minimum=-32768;maximum=32767;end
                endcase
                for(t=0;t<16;t++)begin
                    rng=next_random(rng);aa=rng[15:0];
                    rng=next_random(rng);bb=rng[15:0];
                    va=$signed(decode(precision,aa));vb=$signed(decode(precision,bb));
                    case(t)
                        0:begin va=0;vb=maximum;end
                        1:begin va=minimum;vb=minimum;end
                        2:begin va=minimum;vb=maximum;end
                        3:begin va=maximum;vb=maximum;end
                        4:begin va=-1;vb=1;end
                        default:begin end
                    endcase
                    p=va*vb;acc=acc+p;
                    vectors[16*f+t]={2'd0,precision,va[15:0],vb[15:0],p[31:0],acc[35:0]};
                end
            end
        end
    endtask

    initial begin
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("systolic_pe_signed.vcd"); $dumpvars(0, pe_combined_equivalence_tb);
        end
        generate_vectors();
        if (MAC_VECTOR_COUNT != 16 * MAC_FRAME_COUNT) $fatal(1, "Invalid frame size");
        for (index = 0; index < MAC_VECTOR_COUNT; index = index + 1)
            if ($isunknown(vectors[index])) $fatal(1, "Missing golden arithmetic vector %0d", index);
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

        for (frame_index = 0; frame_index < MAC_FRAME_COUNT; frame_index = frame_index + 1) begin
            load_vector(16 * frame_index);
            cycle(1, frame_index[0], 0, 0, selected_mode, 0, 0, 0, 0, "Start golden arithmetic dot product");
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
                      selected_product, selected_prefix, "golden arithmetic product/prefix through complete PE");
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
        $display("COMBINED OPTIMIZED PE EQUIVALENCE TEST PASSED (USE_HSM=0)");
        $display("Completed dot products: %0d; golden arithmetic input pairs: %0d", completed_frames, MAC_VECTOR_COUNT);
        $display("Clocked checks=%0d; reset checks=%0d; local pairs=%0d; commits=%0d; forwarded operands=%0d",
                 clock_checks, reset_checks, pair_checks, committed_checks, forwarding_checks);
        $display("Stall checks=%0d; one-sided stream checks=%0d; sticky-error checks=%0d",
                 stall_checks, one_sided_checks, error_checks);
        $finish;
    end
    initial begin #100000; $fatal(1, "Single PE test timed out"); end
endmodule
