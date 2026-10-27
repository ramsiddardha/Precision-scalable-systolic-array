`timescale 1ns/1ps

module tb_csa_3to2;

    reg  [31:0] x, y, z;
    wire [31:0] sum, carry;

    // Three unsigned 32-bit inputs can need a 34-bit total.
    reg [33:0] expected, observed;
    integer checks = 0;
    integer errors = 0;

    csa_3to2 dut (
        .x(x), .y(y), .z(z),
        .sum(sum), .carry(carry)
    );

    // Apply one triple, wait for settling, then check its total.
    task check_case;
        input [31:0] test_x, test_y, test_z;
        begin
            x = test_x;
            y = test_y;
            z = test_z;
            #1;

            // Widen BEFORE adding to preserve all input carries.
            expected = {2'b00, x} + {2'b00, y} + {2'b00, z};

            // Insert a zero at the right of carry to shift it left.
            // The leading zeros make both terms 34 bits wide.
            observed = {2'b00, sum} + {1'b0, carry, 1'b0};
            checks = checks + 1;

            if (observed !== expected) begin
                errors = errors + 1;
                $display("FAIL case %0d: expected=%0d observed=%0d",
                         checks, expected, observed);
            end else begin
                $display("PASS case %0d: sum=%0d carry=%0d total=%0d",
                         checks, sum, carry, observed);
            end
        end
    endtask

    initial begin
        check_case(32'd0, 32'd0, 32'd0);
        check_case(32'd5, 32'd3, 32'd4);
        check_case(32'd1, 32'd1, 32'd1);
        check_case(32'hAAAAAAAA, 32'h55555555, 32'd0);
        check_case(32'hFFFFFFFF, 32'd1, 32'd0);
        check_case(32'h80000000, 32'h80000000, 32'd0);
        check_case(32'h80000000, 32'h80000000, 32'h80000000);
        check_case(32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF);

        if (errors != 0)
            $fatal(1, "FAIL: %0d of %0d CSA cases failed.", errors, checks);

        $display("PASS: all %0d CSA cases passed.", checks);
        $finish;
    end

endmodule
