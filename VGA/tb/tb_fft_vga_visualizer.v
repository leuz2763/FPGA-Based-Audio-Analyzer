`timescale 1ns / 1ps

/*******************************************************************************
 * Testbench: tb_fft_vga_visualizer
 * 
 * Description:
 *   Verifies the correct mapping of FFT magnitudes to VGA output colors.
 * 
 * Performed Tests:
 *   1. Initialization: Reset and signal cleanup.
 *   2. FFT Write: Simulates writing spectral data into the RAM.
 *      - Bin 0: High value (Saturation test).
 *      - Bin 1: Medium value (Standard height test).
 *      - Bin 2: Zero value.
 *   3. VGA Read: Simulates the VGA controller scanning horizontally.
 *      - Checks behavior in the left margin (White).
 *      - Checks behavior inside the FFT window (Blue bars vs White background).
 *      - Verifies pipeline delays and offset logic.
 *******************************************************************************/

module tb_fft_vga_visualizer;

    // --- Inputs (Registers to drive the module) ---
    reg          sys_clk;
    reg          sys_reset;
    
    reg [8:0]    i_fft_addr;
    reg [23:0]   i_fft_mag;
    reg          i_fft_valid;

    reg          pixel_clk;
    reg [9:0]    pixel_x;
    reg [9:0]    pixel_y;
    reg          video_on;

    // --- Outputs (Wires to read results) ---
    wire [9:0]   o_vga_r;
    wire [9:0]   o_vga_g;
    wire [9:0]   o_vga_b;

    // --- Parameters ---
    parameter MAG_SCALE_SHIFT = 10;
    parameter SCREEN_HEIGHT = 480;
    
    // Loop variable for testing (Declared here for Verilog-2001 compatibility)
    integer i;

    // DUT Instance
    fft_vga_visualizer #(
        .MAG_SCALE_SHIFT(MAG_SCALE_SHIFT)
    ) dut (
        .sys_clk(sys_clk),
        .sys_reset(sys_reset),
        .i_fft_addr(i_fft_addr),
        .i_fft_mag(i_fft_mag),
        .i_fft_valid(i_fft_valid),
        .pixel_clk(pixel_clk),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .video_on(video_on),
        .o_vga_r(o_vga_r),
        .o_vga_g(o_vga_g),
        .o_vga_b(o_vga_b)
    );

    // --- Clock Generation ---
    // sys_clk: 50 MHz (20ns period)
    always #10 sys_clk = ~sys_clk;
    
    // pixel_clk: 25 MHz (40ns period) - Slower to observe CDC
    always #20 pixel_clk = ~pixel_clk;

    // --- Test Procedure ---
    initial begin
        // 1. Initialization
        sys_clk = 0;
        pixel_clk = 0;
        sys_reset = 1;
        
        i_fft_addr = 0;
        i_fft_mag = 0;
        i_fft_valid = 0;
        
        pixel_x = 0;
        pixel_y = 0;
        video_on = 0;

        // Wait for reset
        #100;
        sys_reset = 0;
        #100;

        // ------------------------------------------------------------
        // PHASE 1: FFT Data Write (Simulating spectrum arrival)
        // ------------------------------------------------------------
        $display("--- Start FFT RAM Write ---");
        
        // Write to Bin 0: High value (to test saturation)
        // Value: 600 << 10 (so after shift it returns 600, which is > 480)
        @(posedge sys_clk);
        i_fft_valid = 1;
        i_fft_addr  = 0;
        i_fft_mag   = 24'd600 << MAG_SCALE_SHIFT; 

        // Write to Bin 1: Medium value (e.g., 200 pixels height)
        @(posedge sys_clk);
        i_fft_addr  = 1;
        i_fft_mag   = 24'd200 << MAG_SCALE_SHIFT;

        // Write to Bin 2: Zero value (0)
        @(posedge sys_clk);
        i_fft_addr  = 2;
        i_fft_mag   = 0;
        
        // End writing
        @(posedge sys_clk);
        i_fft_valid = 0;
        
        // Wait a bit
        #200;

        // ------------------------------------------------------------
        // PHASE 2: VGA Read (Simulating a horizontal scan line)
        // ------------------------------------------------------------
        $display("--- Start VGA Scan ---");
        
        // Simulating a line at Y = 400.
        // Since max height is 480 (0 top, 479 bottom),
        // Y=400 is near the bottom. A 200px high bar should be visible here.
        // Draw condition: pixel_y >= (480 - bar_height).
        // Bin 0 (height 480 sat): 400 >= (480-480=0)   -> TRUE (Draw BLUE)
        // Bin 1 (height 200):     400 >= (480-200=280) -> TRUE (Draw BLUE)
        // Bin 2 (height 0):       400 >= (480-0=480)   -> FALSE (Draw WHITE)
        
        pixel_y = 400; 
        video_on = 1; // We are in active area

        // Simulating horizontal scanning from X=50 to X=80
        // Offset is 64.
        // X=50..63: Left Margin (White)
        // X=64:     Bin 0 (Blue)
        // X=65:     Bin 1 (Blue)
        // X=66:     Bin 2 (White - bar too short/zero)
        
        // Corrected loop for Verilog-2001
        for (i = 50; i < 80; i = i + 1) begin
            @(posedge pixel_clk); // VGA clock rising edge
            pixel_x = i;
            
            // Small delay to allow signals to settle in waveform viewer
            #1; 
        end

        // Simulate Blanking (outside active area)
        @(posedge pixel_clk);
        video_on = 0;
        pixel_x = 640;
        
        #100;
        $display("--- End Simulation ---");
        $stop;
    end

endmodule