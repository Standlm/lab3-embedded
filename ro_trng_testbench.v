
`timescale 1ns / 1ps

module ro_trng_testbench;

    // 50 MHz clock
    reg clk = 0;
    reg rst_n = 0;

    always #10 clk = ~clk;

    // Main RNG outputs
    wire [31:0] rng_word;
    wire [31:0] rng_valid;
    wire [31:0] trip_cnt;
    
    // Comparing two sets of rng.v
    wire [31:0] trials;
    wire [31:0] over;

    // Boundary test inputs and outputs
    reg [31:0] test_word = 0;
    reg test_valid = 0;

    wire [31:0] test_trials;
    wire [31:0] test_over;

    // Internal signals for observation
    wire [31:0] trng_word;
    wire trng_valid;
    wire [31:0] lfsr_word;

    // Testbench bookkeeping
    integer words_seen = 0;
    integer errors = 0;
    integer expected_trials = 0;
    integer expected_over = 0;
    integer cycles_since_word = 0;
    integer last_interval = 0;
    integer lfsr_checks = 0;

    reg [31:0] expected_lfsr;
    reg [31:0] expected_mixed;
    reg [32:0] expected_sum;
    reg [31:0] expected_main_over = 0;

    // -------------------------------------------------
    // Main RNG
    // -------------------------------------------------

    rng dut_rng (
        .clk(clk),
        .rst_n(rst_n),
        .out_word(rng_word),
        .out_valid(rng_valid),
        .trip_cnt(trip_cnt)
    );

    // // 
    assign trng_word = dut_rng.truerng_out;
    assign trng_valid = dut_rng.valid;
    assign lfsr_word = dut_rng.pseudorng_out;

    // -------------------------------------------------
    // Main Monte Carlo counter
    // -------------------------------------------------

    mc_pi dut_mc (
        .clk(clk),
        .rst_n(rst_n),
        .in_word(rng_word),
        .in_valid(rng_valid[0]),
        .trials(trials),
        .over(over)
    );

    // -------------------------------------------------
    // Independent boundary-test Monte Carlo counter
    // -------------------------------------------------

    mc_pi boundary_mc (
        .clk(clk),
        .rst_n(rst_n),
        .in_word(test_word),
        .in_valid(test_valid),
        .trials(test_trials),
        .over(test_over)
    );

    // -------------------------------------------------
    // LFSR reference function
    // -------------------------------------------------

    function [31:0] lfsr_next;
        input [31:0] q;
        reg feedback;
        begin
            feedback = q[31] ^ q[21] ^ q[1] ^ q[0];
            lfsr_next = {q[30:0], feedback};
        end
    endfunction

    // -------------------------------------------------
    // Boundary test task
    // -------------------------------------------------

    task check_boundary;
        input [31:0] word;
        input [32:0] correct_sum;
        input correct_over;

        begin
            @(negedge clk);

            test_word = word;
            test_valid = 1'b1;

            #1;

            if (boundary_mc.result !== correct_sum) begin
                $display(
                    "FAIL SUM: word=%h expected=%h actual=%h",
                    word,
                    correct_sum,
                    boundary_mc.result
                );
                errors = errors + 1;
            end

            if (boundary_mc.result[32] !== correct_over) begin
                $display("FAIL CLASSIFICATION: %h", word);
                errors = errors + 1;
            end

            @(posedge clk);
            #1;

            expected_trials = expected_trials + 1;
            expected_over = expected_over + correct_over;

            if (test_trials !== expected_trials ||
                test_over !== expected_over) begin

                $display(
                    "FAIL COUNTERS: word=%h trials=%0d over=%0d",
                    word,
                    test_trials,
                    test_over
                );

                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS BOUNDARY: %h sum=%h trials=%0d over=%0d",
                    word,
                    boundary_mc.result,
                    test_trials,
                    test_over
                );
            end

            @(negedge clk);
            test_valid = 1'b0;
        end
    endtask

    // -------------------------------------------------
    // Check first eight LFSR values
    // -------------------------------------------------

    initial begin
        expected_lfsr = 32'h00000001;

        wait (rst_n == 1'b1);

        // Check the first value immediately after reset
        #1;

        for (integer i = 0; i < 8; i = i + 1) begin

            if (lfsr_word !== expected_lfsr) begin
                $display(
                    "FAIL LFSR %0d: expected=%h actual=%h",
                    i,
                    expected_lfsr,
                    lfsr_word
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS LFSR %0d: %h",
                    i,
                    lfsr_word
                );
            end

            lfsr_checks = lfsr_checks + 1;
            expected_lfsr = lfsr_next(expected_lfsr);

            @(posedge clk);
            #1;
        end
    end

    // -------------------------------------------------
    // Monitor every valid random word
    // -------------------------------------------------

    always @(posedge clk) begin
        if (!rst_n) begin
            words_seen <= 0;
            cycles_since_word <= 0;
            expected_main_over <= 0;
        end
        else begin
            cycles_since_word <= cycles_since_word + 1;

            if (trng_valid) begin

                words_seen <= words_seen + 1;
                last_interval <= cycles_since_word + 1;
                cycles_since_word <= 0;

                expected_mixed = trng_word ^ lfsr_word;

                if (rng_word !== expected_mixed) begin
                    $display("FAIL XOR MIXER");
                    errors = errors + 1;
                end

                expected_sum =
                    {1'b0, dut_mc.x2} +
                    {1'b0, dut_mc.y2};

                if (dut_mc.result !== expected_sum) begin
                    $display("FAIL MONTE CARLO SUM");
                    errors = errors + 1;
                end

                if (dut_mc.result[32])
                    expected_main_over <= expected_main_over + 1;

                $display("");
                $display("------------- WORD %0d -------------",
                         words_seen + 1);

                $display("TRNG word  = %h", trng_word);
                $display("LFSR word  = %h", lfsr_word);
                $display("XOR output = %h", rng_word);

                $display("x          = %h", rng_word[31:16]);
                $display("y          = %h", rng_word[15:0]);
                $display("x squared  = %h", dut_mc.x2);
                $display("y squared  = %h", dut_mc.y2);
                $display("sum        = %h", dut_mc.result);

                $display("over?      = %b", dut_mc.result[32]);
                $display("interval   = %0d clocks",
                         cycles_since_word + 1);

                $display("------------------------------------");
            end
        end
    end

    // -------------------------------------------------
    // Main simulation
    // -------------------------------------------------

    initial begin

        $display("Starting TRNG Monte Carlo simulation");

        // Apply reset for five cycles
        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        // Checking bit boundaries
        check_boundary(
            32'h00000000,
            33'h000000000,
            1'b0
        );

        check_boundary(
            32'hFFFF0000,
            33'h0FFFE0001,
            1'b0
        );

        check_boundary(
            32'h80008000,
            33'h080000000,
            1'b0
        );

        check_boundary(
            32'hB504B504,
            33'h0FFFD5020,
            1'b0
        );

        check_boundary(
            32'hB505B505,
            33'h100002432,
            1'b1
        );

        check_boundary(
            32'hFFFFFFFF,
            33'h1FFFC0002,
            1'b1
        );

        // Wait for at least 20 valid TRNG words
        wait (words_seen >= 20);

        @(negedge clk);
        #1;

        $display("");
        $display("========== FINAL RESULTS ==========");
        $display("Words seen     = %0d", words_seen);
        $display("Trials         = %0d", trials);
        $display("Over           = %0d", over);
        $display("Trip count     = %0d", trip_cnt);
        $display("LFSR checks    = %0d", lfsr_checks);
        $display("Boundary trials= %0d", test_trials);
        $display("Boundary over  = %0d", test_over);

        if (trials !== words_seen) begin
            $display("FAIL: trial count mismatch");
            errors = errors + 1;
        end

        if (over !== expected_main_over) begin
            $display("FAIL: over count mismatch");
            errors = errors + 1;
        end

        if (test_trials !== 6 || test_over !== 2) begin
            $display("FAIL: boundary totals incorrect");
            errors = errors + 1;
        end

        if (lfsr_checks !== 8) begin
            $display("FAIL: missing LFSR checks");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d errors", errors);

        $finish;
    end

    // Simulation timeout
    initial begin
        #100000000;
        $display("TIMEOUT: only %0d words received", words_seen);
        $finish;
    end

endmodule
