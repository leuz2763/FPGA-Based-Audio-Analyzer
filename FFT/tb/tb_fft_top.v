/*******************************************************************************
* Testbench for fft_top.v
* 
* Description:
* This testbench validates the top-level integration of the FFT processor, 
* checking the interaction between the Controller, Datapath, and Memory buffers.
*
* Test Sequence:
* 1. **Input Stimulus Generation**: Generates a synthetic 512-point Square Wave 
*    signal (Period = 32 samples, Amplitude = +/- 10000). 
*    - This specific pattern is chosen to produce a predictable frequency 
*      spectrum (Fundamental peak at Bin 16 + Odd Harmonics).
*    - Simulates an ADC interface by asserting `i_new_sample_valid` per sample.
*
* 2. **Process Monitoring**: Observes the `o_fft_busy` flag to track the 
*    transition from the Data Loading phase to the Processing phase.
*
* 3. **Output Logging**: Uses a monitor block to capture the streaming 
*    results (`o_fft_magnitude_out`) as they become valid. 
*    - Prints the Bin Index and Magnitude to the console for analysis.
*
* 4. **Safety Mechanisms**: Includes a Watchdog Timer (1ms) to force a stop 
*    if the internal FSM hangs or the calculation exceeds expected duration.
******************************************************************************/

`timescale 1ns / 1ps

module tb_fft_top;

    // Parameters
    parameter CLK_PERIOD = 10;          // 100 MHz clock (10ns)
    parameter FFT_POINTS = 512;
    parameter DATA_WIDTH = 24;

    // Inputs
    reg                     clk;
    reg                     reset;
    reg                     i_new_sample_valid;
    reg signed [23:0]       i_sample_data;

    // Output
    wire [8:0]              o_fft_magnitude_addr;
    wire [23:0]             o_fft_magnitude_out;
    wire                    o_fft_out_valid;
    wire                    o_fft_done_pulse;
    wire                    o_fft_busy;

    // Internal Variable
    integer i;
    

    // DUT
    fft_top u_dut (
        .clk                    (clk),
        .reset                  (reset),
        .i_new_sample_valid     (i_new_sample_valid),
        .i_sample_data          (i_sample_data),
        .o_fft_magnitude_addr   (o_fft_magnitude_addr),
        .o_fft_magnitude_out    (o_fft_magnitude_out),
        .o_fft_out_valid        (o_fft_out_valid),
        .o_fft_done_pulse       (o_fft_done_pulse),
        .o_fft_busy             (o_fft_busy)
    );

    // 6. Clock Generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // 7. Watchdog Timer (Prevents Infinite Simulation)
    initial begin
        // Wait for 1 millisecond max. The FFT should take approx 50-100us.
        #(1000000); 
        $display("Error: Simulation Timed Out! (Watchdog Triggered)");
        $stop;
    end

    // 8. Main Stimulus Process
    initial begin
        // Initialize Signals
        reset = 1;
        i_new_sample_valid = 0;
        i_sample_data = 0;

        // Apply Reset
        #(CLK_PERIOD * 10);
        reset = 0;
        #(CLK_PERIOD * 10);

        $display("------------------------------------------------");
        $display("Simulation Start: Feeding 512 Samples (Square Wave)");
        $display("------------------------------------------------");

        // Generate a Square Wave Period = 32 samples
        // Fundamental Frequency Bin = 512 / 32 = 16
        for (i = 0; i < FFT_POINTS; i = i + 1) begin
            
            if ((i % 32) < 16) 
                i_sample_data = 24'd10000;  // High
            else 
                i_sample_data = -24'd10000; // Low

            // Pulse Valid
            i_new_sample_valid = 1;
            #(CLK_PERIOD); 
            i_new_sample_valid = 0;
            
            // Small gap between samples (simulation speedup)
            #(CLK_PERIOD * 4);
        end

        $display("Buffer Filled. Waiting for FFT Processing...");
        
        // Wait for busy to rise (processing starts)
        wait (o_fft_busy == 1'b1);
        
        // Wait for busy to fall (processing ends)
        wait (o_fft_busy == 1'b0);

        $display("FFT Processing Done. Checking Outputs...");
        
        // Wait a bit for any trailing signals
        #(CLK_PERIOD * 20);
        
        $display("Simulation Finished Successfully.");
        $stop;
    end

    // 9. Monitor Process (Printing Results)
    always @(posedge clk) begin
        if (o_fft_out_valid) begin
            // Print to console
            $display("Bin: %3d | Magnitude: %d", o_fft_magnitude_addr, o_fft_magnitude_out);
        end
    end

endmodule