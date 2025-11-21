/*******************************************************************************
* Module: tb_fft_butterfly
*
* Description:
*   Testbench for the Radix-2 FFT Butterfly module.
*   It verifies the DUT logic handles complex arithmetic correctly.
*
*   NOTE ON PRECISION:
*   Since the RTL uses truncation (floor) for bit-shifting and the Q-format
*   cannot represent exactly +1.0, output values may differ by +/- 1 LSB 
*   from ideal integer calculations. This testbench includes a tolerance check.
*******************************************************************************/

`timescale 1ns / 1ps


module tb_fft_butterfly;

    // -------------------------------------------------------------------------
    // Testbench Parameters
    // -------------------------------------------------------------------------
    parameter DATA_WIDTH    = 24;
    parameter TWIDDLE_WIDTH = 24;
    parameter CLK_PERIOD    = 10; // 100 MHz

    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------
    reg                                  clk;
    reg                                  reset;
    reg                                  i_start;
    reg signed [DATA_WIDTH*2-1:0]        i_data_a;
    reg signed [DATA_WIDTH*2-1:0]        i_data_b;
    reg signed [TWIDDLE_WIDTH*2-1:0]     i_twiddle;

    wire signed [DATA_WIDTH*2-1:0]       o_data_a_out;
    wire signed [DATA_WIDTH*2-1:0]       o_data_b_out;
    wire                                 o_valid;
    
    // Verification counters
    integer test_count = 0;
    integer errors = 0;
    
    // -------------------------------------------------------------------------
    // DUT Instance
    // -------------------------------------------------------------------------
    fft_butterfly #(
        .DATA_WIDTH(DATA_WIDTH),
        .TWIDDLE_WIDTH(TWIDDLE_WIDTH)
    ) uut (
        .clk(clk),
        .reset(reset),
        .i_start(i_start),
        .i_data_a(i_data_a),
        .i_data_b(i_data_b),
        .i_twiddle(i_twiddle),
        .o_data_a_out(o_data_a_out),
        .o_data_b_out(o_data_b_out),
        .o_valid(o_valid)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Main Process
    // -------------------------------------------------------------------------
    initial begin
        $display("--- Starting Simulation for fft_butterfly ---");
        
        // Initialize
        reset = 1'b1;
        i_start = 1'b0;
        i_data_a = 0; i_data_b = 0; i_twiddle = 0;

        // Reset Pulse
        repeat (2) @(posedge clk);
        reset = 1'b0;
        $display("[%0t] Reset released.", $time);
        @(posedge clk);

        // --- TEST 1: Identity (Twiddle ~ 1) ---
        // Note: In Q1.23, max value is 0.99999988, not 1.0.
        // Multiplication truncation will cause result to be 1 less than ideal.
        apply_and_check(
            10,  20,   // A
            5,    8,   // B
            (1 << (TWIDDLE_WIDTH-1)) - 1, 0, // W = 0.999...
            7,   14,   // Expected A' (Ideal)
            2,    6    // Expected B' (Ideal)
        );
        
        // --- TEST 2: -90 Degree Rotation (Twiddle = -j) ---
        // -1.0 is exactly representable, so this usually matches perfectly.
        apply_and_check(
            100,  50,  // A
            20,  -30,  // B
            0, -(1 << (TWIDDLE_WIDTH-1)), // W = -j
            35,   15,  // Expected A'
            65,   35   // Expected B'
        );

        // --- TEST 3: -45 Degree Rotation ---
        // Complex rounding errors expected.
        apply_and_check(
            -100, -50, // A
            80,   60,  // B
            5932525, -5932525, // W (approx 0.707)
            -1,  -32,  // Expected A'
            -100, -18  // Expected B'
        );

        // --- Completion ---
        @(posedge clk);
        if (errors == 0)
            $display("--- SIMULATION SUCCESS: All tests passed (within tolerance). ---");
        else
            $display("--- SIMULATION FAILED: %0d errors found. ---", errors);
        
        $finish;
    end
    
    // -------------------------------------------------------------------------
    // Task: Apply inputs and Check outputs with Tolerance
    // -------------------------------------------------------------------------
    task apply_and_check;
        input signed [DATA_WIDTH-1:0]    a_re_in, a_im_in;
        input signed [DATA_WIDTH-1:0]    b_re_in, b_im_in;
        input signed [TWIDDLE_WIDTH-1:0] w_re_in, w_im_in;
        input signed [DATA_WIDTH-1:0]    exp_a_re, exp_a_im;
        input signed [DATA_WIDTH-1:0]    exp_b_re, exp_b_im;
        
        reg signed [DATA_WIDTH-1:0] res_a_re, res_a_im;
        reg signed [DATA_WIDTH-1:0] res_b_re, res_b_im;
        
    begin
        test_count = test_count + 1;
        $display("----------------------------------------------------------");
        $display("[%0t] Starting Test %0d", $time, test_count);
        
        // Drive Inputs
        i_data_a  = {a_re_in, a_im_in};
        i_data_b  = {b_re_in, b_im_in};
        i_twiddle = {w_re_in, w_im_in};
        i_start   = 1'b1;
        
        @(posedge clk);
        i_start = 1'b0;
        
        // Wait Latency (3 cycles)
        repeat (2) @(posedge clk);
        #1; // Delta cycle delay for monitoring
        
        if (o_valid !== 1'b1) begin
            $display("ERROR: o_valid not asserted.");
            errors = errors + 1;
        end else begin
            // Capture Results
            res_a_re = o_data_a_out[DATA_WIDTH*2-1 -: DATA_WIDTH];
            res_a_im = o_data_a_out[DATA_WIDTH-1   -: DATA_WIDTH];
            res_b_re = o_data_b_out[DATA_WIDTH*2-1 -: DATA_WIDTH];
            res_b_im = o_data_b_out[DATA_WIDTH-1   -: DATA_WIDTH];
            
            // --- CHECK A' (Real) ---
            if (!check_val(res_a_re, exp_a_re)) begin
                $display("ERROR: A_re mismatch. Got %d, Exp %d", res_a_re, exp_a_re);
                errors = errors + 1;
            end
            // --- CHECK A' (Imag) ---
            if (!check_val(res_a_im, exp_a_im)) begin
                $display("ERROR: A_im mismatch. Got %d, Exp %d", res_a_im, exp_a_im);
                errors = errors + 1;
            end
            // --- CHECK B' (Real) ---
            if (!check_val(res_b_re, exp_b_re)) begin
                $display("ERROR: B_re mismatch. Got %d, Exp %d", res_b_re, exp_b_re);
                errors = errors + 1;
            end
            // --- CHECK B' (Imag) ---
            if (!check_val(res_b_im, exp_b_im)) begin
                $display("ERROR: B_im mismatch. Got %d, Exp %d", res_b_im, exp_b_im);
                errors = errors + 1;
            end
        end
        
        if (errors == 0) $display("Test %0d OK.", test_count);
        @(posedge clk);
    end
    endtask

    // -------------------------------------------------------------------------
    // Function to check value with +/- 1 LSB Tolerance
    // -------------------------------------------------------------------------
    // FIX: Changed return type from 'boolean' (invalid) to 'reg' (1-bit)
    function automatic reg check_val; 
        input signed [DATA_WIDTH-1:0] val;
        input signed [DATA_WIDTH-1:0] exp;
        reg signed [DATA_WIDTH-1:0] diff;
    begin
        diff = val - exp;
        // Check absolute difference <= 1
        if (diff >= -1 && diff <= 1) begin
            check_val = 1'b1; // Pass
        end else begin
            check_val = 1'b0; // Fail
        end
    end
    endfunction

endmodule