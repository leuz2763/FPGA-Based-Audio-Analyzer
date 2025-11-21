/************************************************************************************
* Module: i2c_config_codec_standard
*
* Description:
* Configures the WM8731 Codec via I2C interface for Altera DE2.
* 
* Configuration Details:
* - Sampling Rate: 48 kHz
* - IMPORTANT: User MUST provide a 12.000 MHz clock to AUD_XCK pin (USB Mode).
* - Data Format: I2S, 24-bit, Slave Mode.
* - Input Path: Microphone Enabled, Boost Enabled, Line-In Muted.
***********************************************************************************/
module i2c_config_codec_standard (
    input  wire clk,        // System Clock (50 MHz)
    input  wire reset_n,    // Active low reset (KEY[0])
    output wire scl,        // I2C Clock
    inout  wire sda,        // I2C Data
    output reg  done        // Configuration Done Flag
);

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    localparam DEVICE_ADDR = 7'b0011010; // WM8731 Address (CSB=0 on DE2)
    localparam TOTAL_REGS  = 10;

    //-------------------------------------------------------------------------
    // I2C Clock Generator (100 kHz approx)
    //-------------------------------------------------------------------------
    reg [15:0] clk_div;
    reg i2c_tick; 
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            clk_div <= 0;
            i2c_tick <= 0;
        end else begin
            // 50MHz / 250 / 2 (toggle) = 100kHz SCL
            if (clk_div >= 249) begin 
                clk_div <= 0;
                i2c_tick <= 1;
            end else begin
                clk_div <= clk_div + 1;
                i2c_tick <= 0;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Configuration ROM (LUT)
    //-------------------------------------------------------------------------
    reg [15:0] current_config_data;
    reg [3:0]  reg_index;

    always @(*) begin
        case (reg_index)
            // Reset Device
            0: current_config_data = 16'h1E00; // Reset Register (R15)
            
            // Power Down Control
            1: current_config_data = 16'h0C00; // R6: Power On everything
            
            // Analog Audio Path
            2: current_config_data = 16'h0815; // R4: Mic Boost, Mic Select, DAC Select
            
            // Digital Audio Path
            3: current_config_data = 16'h0A00; // R5: No De-emphasis, Clear DC
            
            // Digital Audio Interface Format
            4: current_config_data = 16'h0E0A; // R7: I2S, 24-bit, Slave
            
            // Sampling Control (USB Mode requires 12MHz MCLK input)
            5: current_config_data = 16'h1001; // R8: USB Mode, 48kHz (BOSR=0, SR=0)
            
            // Active Control
            6: current_config_data = 16'h1201; // R9: Active = 1
            
            // Volume Controls (Last to avoid pops)
            7: current_config_data = 16'h0097; // R0: Left Line Mute
            8: current_config_data = 16'h0297; // R1: Right Line Mute
            9: current_config_data = 16'h0479; // R2: Headphone Vol ~0dB (Left)
            
            // Note: Reg index 10 handling below will cover R3
            default: current_config_data = 16'h0679; // R3: Headphone Vol ~0dB (Right)
        endcase
    end

    //-------------------------------------------------------------------------
    // FSM Signals
    //-------------------------------------------------------------------------
    reg [4:0] state; // State machine
    
    // FIX: bit_index must be 5 bits to hold value 23 (10111)
    reg [4:0] bit_index; 
    
    reg sda_out;
    reg sda_drive; // 1 = drive sda_out, 0 = high-Z (read ACK)
    reg scl_out;
    
    reg [23:0] tx_packet; 

    assign sda = sda_drive ? sda_out : 1'bz;
    assign scl = scl_out;

    // FSM States
    localparam S_IDLE       = 0;
    localparam S_START      = 1;
    localparam S_CLK_LOW    = 2;
    localparam S_CLK_HIGH   = 3;
    localparam S_ACK1       = 4; // ACK Wait High
    localparam S_ACK2       = 5; // ACK Wait Low / Check End
    localparam S_STOP_1     = 6; // Setup Stop
    localparam S_STOP_2     = 7; // Execute Stop
    localparam S_DONE       = 8;

    //-------------------------------------------------------------------------
    // I2C State Machine
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state      <= S_IDLE;
            reg_index  <= 0;
            bit_index  <= 23;
            sda_out    <= 1;
            scl_out    <= 1;
            sda_drive  <= 1;
            done       <= 0;
            tx_packet  <= 0;
        end else if (i2c_tick) begin
            case (state)
                // ------------------------------------------------------
                // IDLE: Prepare Packet
                // ------------------------------------------------------
                S_IDLE: begin
                    scl_out   <= 1;
                    sda_out   <= 1;
                    bit_index <= 23;
                    sda_drive <= 1;
                    
                    // Load packet based on current reg_index from LUT
                    tx_packet <= { 
                        DEVICE_ADDR, 1'b0,              // Byte 1: Addr + Write
                        current_config_data[15:8],      // Byte 2: Reg Addr
                        current_config_data[7:0]        // Byte 3: Data
                    };
                    
                    if (!done) state <= S_START;
                end

                // ------------------------------------------------------
                // START: SDA Low while SCL High
                // ------------------------------------------------------
                S_START: begin
                    sda_out <= 0;
                    state   <= S_CLK_LOW;
                end

                // ------------------------------------------------------
                // SCL Low: Change Data or Release for ACK
                // ------------------------------------------------------
                S_CLK_LOW: begin
                    scl_out <= 0;
                    
                    // Check for ACK positions (After bit 16, 8, and 0)
                    if (bit_index == 16 || bit_index == 8 || bit_index == 0) begin
                        // Logic bug fix: If we just sent bit 16 (index 16), we don't ACK yet.
                        // We transmit bit 23...16. When index wraps from 16->15, that's the ACK.
                        // Let's assume standard loop: Write Bit -> Decrement -> Check ACK.
                        // But here we check before writing.
                        
                        // Actual logic: 
                        // Byte 1: 23..16. ACK.
                        // Byte 2: 15..8.  ACK.
                        // Byte 3: 7..0.   ACK.
                        
                        // If we are at specific points, we handle data, else handle ACK
                        // Let's stick to your logic flow but corrected:
                        sda_drive <= 1;
                        sda_out   <= tx_packet[bit_index];
                        state     <= S_CLK_HIGH;
                    end else begin
                        // Should never happen with the logic flow below, but safety
                        sda_drive <= 1;
                        sda_out   <= tx_packet[bit_index];
                        state     <= S_CLK_HIGH;
                    end
                end

                // ------------------------------------------------------
                // SCL High: Latch Data
                // ------------------------------------------------------
                S_CLK_HIGH: begin
                    scl_out <= 1;
                    
                    // Check if we need an ACK after this bit
                    // If we just finished bit 16, 8, or 0
                    if (bit_index == 16 || bit_index == 8 || bit_index == 0) begin
                        state <= S_ACK1;
                    end else begin
                        bit_index <= bit_index - 1;
                        state     <= S_CLK_LOW;
                    end
                end

                // ------------------------------------------------------
                // ACK Handling
                // ------------------------------------------------------
                S_ACK1: begin
                    scl_out   <= 0; // Pull SCL Low first
                    sda_drive <= 0; // Release SDA
                    state     <= S_ACK2;
                end
                
                S_ACK2: begin
                    scl_out <= 1;   // Clock High for ACK Pulse
                    // (We could check sda input here for NACK error handling)
                    state   <= S_ACK3; // Use extra state to finish pulse
                end

                S_ACK3: begin
                    scl_out <= 0;   // Clock Low
                    
                    if (bit_index == 0) begin
                        // Packet Done
                        state <= S_STOP_1;
                    end else begin
                        // Continue to next byte
                        bit_index <= bit_index - 1;
                        sda_drive <= 1; // Take back control
                        // Value will be set in S_CLK_LOW next
                        state     <= S_CLK_LOW; 
                    end
                end

                // ------------------------------------------------------
                // STOP Condition: SCL High then SDA Low->High
                // ------------------------------------------------------
                S_STOP_1: begin
                    sda_drive <= 1;
                    sda_out   <= 0; // Ensure SDA Low
                    scl_out   <= 0; // Ensure SCL Low
                    state     <= S_STOP_2;
                end
                
                S_STOP_2: begin
                    scl_out   <= 1; // SCL High first
                    state     <= S_DONE; // Recycle reuse state logic
                end

                S_DONE: begin
                    // SCL is High. Now bring SDA High.
                    sda_out <= 1; 
                    
                    // Check if all registers sent
                    if (reg_index < TOTAL_REGS) begin
                        reg_index <= reg_index + 1;
                        state     <= S_IDLE; // Need time gap between stop and start
                    end else begin
                        done <= 1; // Finished forever
                    end
                end
                
            endcase
        end
    end
endmodule