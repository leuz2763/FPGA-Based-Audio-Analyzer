/************************************************************************************
* Module: i2s_double_buffer
*
* Description:
* Implements a double buffering mechanism for audio samples.
* While one buffer is being filled with new data (by I2S), the other
* is available read-only to a processing unit (e.g., an FFT core).
* When the write buffer is full, the roles of the two buffers are swapped.
*
* Parameters:
* - DATA_WIDTH: Width in bits of each audio sample (e.g., 24 for WM8731).
* - BUFFER_DEPTH: Number of samples per buffer (e.g., 512 for your FFT).
*
* Usage with an FFT core:
* 1. The FFT core waits for the `o_fft_data_ready` signal to go high for one cycle.
* 2. When `o_fft_data_ready` is high, it means that a new buffer of
* BUFFER_DEPTH samples is ready and stable for reading.
* 3. The FFT core can begin reading data by presenting addresses 0 to
* (BUFFER_DEPTH - 1) to `i_fft_read_addr`.
* 4. While the FFT is reading, the module is already filling the other buffer with new
* samples, ensuring continuous processing without data loss.
*
***********************************************************************************/
module i2s_double_buffer #(
    parameter DATA_WIDTH   = 24,
    parameter BUFFER_DEPTH = 512
) (
    // Global Signals
    input wire                      clk,
    input wire                      reset, // Synchronous active-high reset

    // I2S Sample Input Interface
    input wire                      i_new_sample_valid, // High for 1 cycle when a new sample is available
    input wire [DATA_WIDTH-1:0]     i_sample_data,      // Sample data input

    // Read Interface for FFT Core
    input wire [$clog2(BUFFER_DEPTH)-1:0] i_fft_read_addr, // Address from FFT core to read data  
    output wire [DATA_WIDTH-1:0]    o_fft_data_out, // Data output to FFT core

    // Segnale di controllo per l'FFT
    output wire                     o_fft_data_ready    // High for 1 cycle when a new buffer is ready for FFT
);

    // Address width
    localparam ADDR_WIDTH = $clog2(BUFFER_DEPTH);

    // reg declarations for the two buffers
    reg [DATA_WIDTH-1:0] buffer_0 [0:BUFFER_DEPTH-1];
    reg [DATA_WIDTH-1:0] buffer_1 [0:BUFFER_DEPTH-1];

    // Reg declarations for selectors and pointers
    reg [ADDR_WIDTH-1:0] write_addr;       // Current write address within the active buffer
    reg                  write_buffer_sel; // 0 -> buffer_0, 1 -> buffer_1
    reg                  read_buffer_sel;  // Available buffer for FFT to read

    // Ready signal register
    reg                  o_fft_data_ready_reg;

    // Writing and swap Logic (sequential)
    always @(posedge clk) begin
        if (reset) begin
            write_addr           <= 0;
            write_buffer_sel     <= 0;
            read_buffer_sel      <= 1; // Inizia leggendo dal buffer 1 (mentre si scrive su 0)
            o_fft_data_ready_reg <= 0;
        end else begin
            
            // Reset ready flag after one clock cycle
            o_fft_data_ready_reg <= 0;

            if (i_new_sample_valid) begin
                // Write the new sample into the active write buffer
                if (write_buffer_sel == 1'b0) begin
                    buffer_0[write_addr] <= i_sample_data;
                end else begin
                    buffer_1[write_addr] <= i_sample_data;
                end

                // Checks if the buffer is full
                if (write_addr == BUFFER_DEPTH - 1) begin
                    // If full swap
                    write_addr           <= 0;                 
                    write_buffer_sel     <= ~write_buffer_sel; 
                    
                    // Full buffer is now available for reading
                    read_buffer_sel      <= write_buffer_sel;    
                    
                    // New set of data is ready for FFT flag
                    o_fft_data_ready_reg <= 1'b1;               
                end else begin
                    // Not full, increment
                    write_addr <= write_addr + 1;
                end
            end
        end
    end

    // Reading Logic (combinational)
    // MUX chooses the correct buffer for FFT reading, FFT core can read at any time
    assign o_fft_data_out = (read_buffer_sel == 1'b0) ? 
                            buffer_0[i_fft_read_addr] : 
                            buffer_1[i_fft_read_addr];

    // Final output assignment
    assign o_fft_data_ready = o_fft_data_ready_reg;

endmodule