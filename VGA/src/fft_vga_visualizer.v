/*******************************************************************************
 * Module: fft_vga_visualizer
 * 
 * Description:
 *   Interface between FFT and VGA.
 *   - Uses Dual-Port RAM for Clock Domain Crossing (CDC).
 *   - Horizontal centering (64 pixel offset).
 *   - Style: BLUE bars on a WHITE background.
 *******************************************************************************/
module fft_vga_visualizer (
    // --- System / FFT Side (Write Side) ---
    input wire          sys_clk,
    input wire          sys_reset,
    
    input wire [8:0]    i_fft_addr,     // 0-511
    input wire [23:0]   i_fft_mag,
    input wire          i_fft_valid,

    // --- VGA Side (Read Side) ---
    input wire          pixel_clk,
    input wire [9:0]    pixel_x,        // 0-639
    input wire [9:0]    pixel_y,        // 0-479
    input wire          video_on,

    // --- Color Output ---
    output reg [9:0]    o_vga_r,
    output reg [9:0]    o_vga_g,
    output reg [9:0]    o_vga_b
);

    // --- Parameters ---
    parameter MAG_SCALE_SHIFT = 10; 
    localparam SCREEN_HEIGHT = 480;
    
    // Centering parameters (Standard VGA 640x480)
    // 640 - 512 = 128; 128 / 2 = 64 lateral offset.
    localparam H_OFFSET = 10'd64; 

    // --- 1. Dual Port RAM ---
    reg [8:0] video_ram [0:511];
    
    wire [23:0] shifted_mag;
    wire [8:0]  ram_data_in;

    // Scaling logic
    assign shifted_mag = i_fft_mag >> MAG_SCALE_SHIFT;
    
    // Saturation (max 480 or 511, clamped to screen height)
    assign ram_data_in = (shifted_mag > SCREEN_HEIGHT) ? 9'd480 : shifted_mag[8:0];

    // --- RAM Write (sys_clk) ---
    always @(posedge sys_clk) begin
        if (i_fft_valid) begin
            video_ram[i_fft_addr] <= ram_data_in;
        end
    end

    // --- RAM Read (pixel_clk) ---
    reg [8:0] bar_height;
    reg       pixel_in_range;

    // Calculate read address by subtracting the offset
    wire [9:0] read_addr = pixel_x - H_OFFSET;

    always @(posedge pixel_clk) begin
        // Read only if we are within the central window (from 64 to 575)
        if (pixel_x >= H_OFFSET && pixel_x < (H_OFFSET + 512)) begin
            bar_height <= video_ram[read_addr[8:0]];
            pixel_in_range <= 1'b1;
        end else begin
            bar_height <= 9'd0;
            pixel_in_range <= 1'b0;
        end
    end

    // --- Pipeline Delay Compensation ---
    reg [9:0] pixel_y_d1;
    reg       video_on_d1;

    always @(posedge pixel_clk) begin
        pixel_y_d1  <= pixel_y;
        video_on_d1 <= video_on;
    end

    // --- Pixel Drawing Logic ---
    wire is_bar_pixel;
    // Draw if we are in the correct column AND the height is sufficient
    // (Note: Y grows downwards, so we check if current Y is >= calculated top of bar)
    assign is_bar_pixel = (pixel_y_d1 >= (SCREEN_HEIGHT - bar_height));

    always @(posedge pixel_clk) begin
        if (!video_on_d1) begin
            // IMPORTANT: During blanking, output MUST be black (0V)
            o_vga_r <= 10'd0;
            o_vga_g <= 10'd0;
            o_vga_b <= 10'd0;
        end 
        else begin
            // Visible screen area
            
            if (pixel_in_range && is_bar_pixel) begin
                // --- BAR (BLUE) ---
                o_vga_r <= 10'd0; 
                o_vga_g <= 10'd0;
                o_vga_b <= 10'd1023; // Full Blue
            end 
            else begin
                // --- BACKGROUND (WHITE) ---
                // This covers the space above the bars and the lateral margins
                o_vga_r <= 10'd1023;
                o_vga_g <= 10'd1023;
                o_vga_b <= 10'd1023;
                
                // Optional: A gray/black line at the bottom to "ground" the bars
                if (pixel_y_d1 == 479) begin
                    o_vga_r <= 10'd0; o_vga_g <= 10'd0; o_vga_b <= 10'd0; 
                end
            end
        end
    end

endmodule