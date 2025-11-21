/************************************************************************************
* Module: top_audio_system
*
* Description:
* Top level module for the DE2 board.
* 1. Generates Master Clock (XCK) for Codec.
* 2. Configures Codec via I2C (Mic Input, 24-bit I2S).
* 3. Controls I2S data flow (Receives Mic data).
* 4. Synchronizes Audio Data from Audio Clock Domain (BCLK) to System Domain (50MHz).
* 5. Stores data in a Double Buffer for FFT processing.
*
***********************************************************************************/
module top_audio_system(
    input  wire CLOCK_50,         // 50 MHz System Clock
    input  wire KEY0,             // Pushbutton for Reset (Active Low)

    // I2C Interface
    inout  wire AUD_I2C_SCLK,     
    inout  wire AUD_I2C_SDAT,     

    // Audio Codec Interface
    output wire AUD_XCK,          // Master Clock to Codec
    output wire AUD_BCLK,         // Bit Clock (Input in Slave mode, but bidirectional on pin)
    output wire AUD_DACLRCK,      // DAC LR Clock
    output wire AUD_DACDAT,       // DAC Data (Loopback)
    input  wire AUD_ADCLRCK,      // ADC LR Clock
    input  wire AUD_ADCDAT        // ADC Data
);

    //-------------------------------------------------------------------------
    // 1. Reset & Clock Generation
    //-------------------------------------------------------------------------
    wire reset_n    = KEY0;       // Active Low Reset
    wire reset_high = ~KEY0;      // Active High Reset (for Buffer)

    // Generate ~12.5 MHz for Codec MCLK (50MHz / 4)
    // Note: 12.5MHz is approx 12.288MHz (acceptable for basic config)
    reg [1:0] clk_cnt;
    reg       clk_div;
    
    always @(posedge CLOCK_50) begin
        clk_cnt <= clk_cnt + 1;
        if (clk_cnt == 2'b01) begin 
            clk_cnt <= 0;
            clk_div <= ~clk_div;
        end
    end
    assign AUD_XCK = clk_div;

    // Force BCLK/LRCK direction logic (FPGA is Slave, so these are inputs physically)
    // We assign inputs to wires for internal use
    wire bclk_in   = AUD_BCLK;
    wire lrclk_in  = AUD_ADCLRCK;
    
    // To drive DACLRCK same as ADCLRCK (Sync mode)
    assign AUD_DACLRCK = AUD_ADCLRCK; 

    //-------------------------------------------------------------------------
    // 2. I2C Configuration
    //-------------------------------------------------------------------------
    wire i2c_done;

    i2c_config_codec_standard i2c_inst (
        .clk     (CLOCK_50),
        .reset_n (reset_n),
        .scl     (AUD_I2C_SCLK),
        .sda     (AUD_I2C_SDAT),
        .done    (i2c_done)
    );

    //-------------------------------------------------------------------------
    // 3. I2S Controller
    // Captures audio in the BCLK domain
    //-------------------------------------------------------------------------
    wire [23:0] w_audio_sample_bclk;
    wire        w_sample_valid_bclk;

    i2s_controller i2s_inst (
        .bclk          (bclk_in),
        .lrclk         (lrclk_in),
        .sdata_in      (AUD_ADCDAT),
        .reset_n       (reset_n),
        .sdata_out     (AUD_DACDAT), // Loopback to headphones
        
        // Outputs (valid in BCLK domain)
        .o_audio_data  (w_audio_sample_bclk),
        .o_audio_valid (w_sample_valid_bclk)
    );

    //-------------------------------------------------------------------------
    // 4. Clock Domain Crossing (CDC): BCLK -> CLOCK_50
    // The buffer runs on CLOCK_50 to allow the FFT to run fast.
    // We need to bring the sample and valid signal safely to 50MHz.
    //-------------------------------------------------------------------------
    reg [23:0] sample_reg_50;
    reg        valid_sync_1, valid_sync_2, valid_sync_3;
    wire       valid_pulse_50;

    // Synchronize the 'valid' pulse
    // Since CLOCK_50 (50MHz) >> BCLK (~3MHz), we can oversample the valid signal.
    always @(posedge CLOCK_50 or posedge reset_high) begin
        if (reset_high) begin
            valid_sync_1 <= 0;
            valid_sync_2 <= 0;
            valid_sync_3 <= 0;
            sample_reg_50 <= 0;
        end else begin
            valid_sync_1 <= w_sample_valid_bclk;
            valid_sync_2 <= valid_sync_1;
            valid_sync_3 <= valid_sync_2; // Edge detection history

            // When we detect a rising edge of the synced valid signal, 
            // we capture the data which is stable by now.
            if (valid_sync_2 && !valid_sync_3) begin
                sample_reg_50 <= w_audio_sample_bclk;
            end
        end
    end

    // Generate a 1-cycle pulse in 50MHz domain on rising edge
    assign valid_pulse_50 = (valid_sync_2 && !valid_sync_3);


    //-------------------------------------------------------------------------
    // 5. Double Buffer Interface
    // Runs entirely on CLOCK_50
    //-------------------------------------------------------------------------
    wire [23:0] w_fft_data_out;
    wire        w_fft_buffer_ready;
    // Connect this to your FFT logic counter
    wire [8:0]  fft_read_addr = 9'd0; 

    i2s_double_buffer #(
        .DATA_WIDTH   (24),   // Configured for 24-bit
        .BUFFER_DEPTH (512)
    ) buffer_inst (
        .clk                (CLOCK_50),       
        .reset              (reset_high),     

        // Write Interface (Now synchronized to CLOCK_50)
        .i_new_sample_valid (valid_pulse_50),
        .i_sample_data      (sample_reg_50),

        // Read Interface (FFT)
        .i_fft_read_addr    (fft_read_addr),
        .o_fft_data_out     (w_fft_data_out),
        .o_fft_data_ready   (w_fft_buffer_ready)
    );

endmodule