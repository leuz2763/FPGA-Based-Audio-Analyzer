/*******************************************************************************
 * Module: fft_top
 * 
 * Description:
 *   Top-level module for 512-point FFT implementation.
 *   Interconnects audio buffering, memory, control logic, and computation cores.
 * 
 * Reset Strategy:
 *   Input 'reset' is Active High.
 *   - Most modules receive 'reset'.
 *   - Twiddle ROM receives '~reset' (Active Low).
 *******************************************************************************/
module fft_top (
    // Clock and Global Reset
    input wire                      clk,
    input wire                      reset, // Synchronous Active High Reset

    // Audio Input Interface (from I2S Receiver)
    input wire                      i_new_sample_valid,
    input wire signed [23:0]        i_sample_data,

    // FFT Result Interface
    output wire [8:0]               o_fft_magnitude_addr, // Bin Address (0-511)
    output wire [23:0]              o_fft_magnitude_out,  // Magnitude Value
    output wire                     o_fft_out_valid,      // Strobe
    
    // Status Flags
    output wire                     o_fft_done_pulse,     
    output wire                     o_fft_busy            
);

    // --- Global Parameters ---
    localparam DATA_WIDTH     = 24;
    localparam TWIDDLE_WIDTH  = 24;
    localparam FFT_POINTS     = 512;
    localparam ADDR_WIDTH     = 9; // $clog2(512)

    // --- Internal Signals ---
    wire rst_n = ~reset; 

    // Double Buffer <-> Controller
    wire                       fft_data_ready;
    wire [ADDR_WIDTH-1:0]      buffer_read_addr;
    wire [DATA_WIDTH-1:0]      buffer_data_out;

    // Controller -> Working RAM
    wire [ADDR_WIDTH-1:0]      ram_addr_a;
    wire [DATA_WIDTH*2-1:0]    ram_data_in_a;
    wire                       ram_wr_en_a;
    wire [ADDR_WIDTH-1:0]      ram_addr_b;
    wire [DATA_WIDTH*2-1:0]    ram_data_in_b;
    wire                       ram_wr_en_b;
    
    // Working RAM -> Cores / Controller
    wire [DATA_WIDTH*2-1:0]    ram_data_out_a;
    wire [DATA_WIDTH*2-1:0]    ram_data_out_b;

    // Controller -> Twiddle ROM
    wire [ADDR_WIDTH-1:0]      twiddle_addr;
    wire [TWIDDLE_WIDTH*2-1:0] twiddle_factor_q;

    // Controller -> Butterfly Core
    wire                       butterfly_start;
    wire                       butterfly_valid;
    wire [DATA_WIDTH*2-1:0]    butterfly_a_out;
    wire [DATA_WIDTH*2-1:0]    butterfly_b_out;

    // Controller -> Magnitude Core
    wire                       magnitude_start;
    wire                       magnitude_valid;
    wire [DATA_WIDTH-1:0]      magnitude_result;
    wire [DATA_WIDTH-1:0]      controller_magnitude_out;


    // --- 1. Audio Input Buffer ---
    i2s_double_buffer #(
        .DATA_WIDTH   (DATA_WIDTH),
        .BUFFER_DEPTH (FFT_POINTS)
    ) u_double_buffer (
        .clk                (clk),
        .reset              (reset),
        .i_new_sample_valid (i_new_sample_valid),
        .i_sample_data      (i_sample_data),
        .i_fft_read_addr    (buffer_read_addr),
        .o_fft_data_out     (buffer_data_out),
        .o_fft_data_ready   (fft_data_ready)
    );

    // --- 2. Main Working RAM ---
    fft_working_ram #(
        .DATA_WIDTH   (DATA_WIDTH * 2), 
        .BUFFER_DEPTH (FFT_POINTS)
    ) u_working_ram (
        .clk         (clk),
        .reset       (reset),
        .i_addr_a    (ram_addr_a),
        .i_data_a    (ram_data_in_a),
        .i_wr_en_a   (ram_wr_en_a),
        .o_data_a    (ram_data_out_a),
        .i_addr_b    (ram_addr_b),
        .i_data_b    (ram_data_in_b),
        .i_wr_en_b   (ram_wr_en_b),
        .o_data_b    (ram_data_out_b)
    );

    // --- 3. Twiddle Factor ROM ---
    // Nota: Assicurati che il percorso del file .hex all'interno del modulo ROM
    // sia corretto o usa un percorso relativo se possibile.
    twiddle_factor_rom #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (TWIDDLE_WIDTH * 2)
    ) u_twiddle_rom (
        .clk              (clk),
        .rst_n            (rst_n), // Active Low reset
        .addr             (twiddle_addr),
        .twiddle_factor_q (twiddle_factor_q)
    );

    // --- 4. Butterfly Computation Core ---
    fft_butterfly #(
        .DATA_WIDTH    (DATA_WIDTH),
        .TWIDDLE_WIDTH (TWIDDLE_WIDTH)
    ) u_butterfly (
        .clk            (clk),
        .reset          (reset),
        .i_start        (butterfly_start),
        .i_data_a       (ram_data_out_a),
        .i_data_b       (ram_data_out_b),
        .i_twiddle      (twiddle_factor_q),
        .o_data_a_out   (butterfly_a_out),
        .o_data_b_out   (butterfly_b_out),
        .o_valid        (butterfly_valid)
    );

    // --- 5. Magnitude Approximation Core ---
    magnitude_approximator #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_magnitude (
        .clk             (clk),
        .reset           (reset),
        .i_start         (magnitude_start),
        .i_fft_complex   (ram_data_out_a), 
        .o_magnitude     (magnitude_result),
        .o_valid         (magnitude_valid)
    );

    // --- 6. Main FFT Controller ---
    fft_controller #(
        .FFT_POINTS    (FFT_POINTS),
        .DATA_WIDTH    (DATA_WIDTH),
        .TWIDDLE_WIDTH (TWIDDLE_WIDTH)
    ) u_controller (
        .clk                   (clk),
        .reset                 (reset),
        
        .i_data_ready          (fft_data_ready),
        .o_buffer_read_addr    (buffer_read_addr),
        .i_buffer_data_in      (buffer_data_out),
        
        .o_ram_addr_a          (ram_addr_a),
        .o_ram_data_in_a       (ram_data_in_a),
        .o_ram_wr_en_a         (ram_wr_en_a),
        .i_ram_data_out_a      (ram_data_out_a),
        
        .o_ram_addr_b          (ram_addr_b),
        .o_ram_data_in_b       (ram_data_in_b),
        .o_ram_wr_en_b         (ram_wr_en_b),
        .i_ram_data_out_b      (ram_data_out_b),
        
        .o_twiddle_addr        (twiddle_addr),
        .i_twiddle_factor      (twiddle_factor_q),
        
        .o_butterfly_start     (butterfly_start),
        .i_butterfly_valid     (butterfly_valid),
        .i_butterfly_a_out     (butterfly_a_out),
        .i_butterfly_b_out     (butterfly_b_out),
        
        .o_magnitude_start     (magnitude_start),
        .i_magnitude_valid     (magnitude_valid),
        .i_magnitude_in        (magnitude_result),
        .o_magnitude_out       (controller_magnitude_out),
        
        .o_fft_busy            (o_fft_busy),
        .o_fft_done            (o_fft_done_pulse)
    );

    // --- Output Assignments ---
    
    // ram_addr_a (pilotato dal controller) contiene l'indice del bin (load_counter)
    // durante la fase di output grazie al fix nel controller.
    assign o_fft_magnitude_addr = ram_addr_a; 
    assign o_fft_magnitude_out  = controller_magnitude_out;
    assign o_fft_out_valid      = magnitude_valid;

endmodule