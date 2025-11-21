/************************************************************************************
* Module: i2s_controller
*
* Description:
* Handles the I2S serial protocol to receive audio data from the WM8731 Codec.
* It operates in Slave mode (receiving BCLK and LRCLK).
* It captures 24-bit samples and outputs them parallelly.
*
* Parameters:
* - DATA_WIDTH: 24 bits (Standard for high-quality audio).
*
* Ports:
* - bclk/lrclk: Clocks from Codec.
* - sdata_in: Serial data from Codec (ADC).
* - sdata_out: Serial data to Codec (DAC) - Loopback.
* - o_audio_data: Parallel 24-bit output (Left Channel).
* - o_audio_valid: Single cycle pulse when data is valid.
***********************************************************************************/
module i2s_controller (
    input  wire        bclk,           // Bit Clock (from Codec)
    input  wire        lrclk,          // Left/Right Clock (from Codec)
    input  wire        sdata_in,       // Serial Data In (from Codec ADC)
    input  wire        reset_n,        // Active low reset (KEY[0])
    output wire        sdata_out,      // Serial Data Out (to Codec DAC)
    
    output reg [23:0]  o_audio_data,   // Parallel Output (Left Channel)
    output reg         o_audio_valid   // Pulse valid
);

    // --- RX LOGIC (Campionamento su POSedge) ---
    reg [23:0] shift_reg_rx;
    reg        lrclk_d1;
    reg [4:0]  bit_cnt;

    always @(posedge bclk or negedge reset_n) begin
        if (!reset_n) begin
            lrclk_d1      <= 1'b0;
            bit_cnt       <= 5'd0;
            shift_reg_rx  <= 24'd0;
            o_audio_data  <= 24'd0;
            o_audio_valid <= 1'b0;
        end else begin
            lrclk_d1      <= lrclk;
            o_audio_valid <= 1'b0;

            // Rilevamento fronte LRCLK
            if (lrclk_d1 != lrclk) begin
                bit_cnt <= 5'd0; // Reset contatore al cambio canale
                
                // Se LRCLK va alto (1), il canale Sinistro (Low) è finito.
                if (lrclk == 1'b1) begin
                    o_audio_data  <= shift_reg_rx;
                    o_audio_valid <= 1'b1;
                end
            end else begin
                // Standard I2S: L'MSB è valido nel 2° ciclo dopo il fronte di LRCLK.
                // Questo blocco 'else' crea il ritardo di 1 ciclo necessario.
                if (bit_cnt < 5'd24) begin
                    bit_cnt <= bit_cnt + 1'b1;
                    // Shift in (MSB first)
                    // Campioniamo solo se siamo nel canale sinistro (lrclk=0) o destro (lrclk=1)
                    // Qui campioniamo sempre e salviamo solo alla fine del frame.
                    shift_reg_rx <= {shift_reg_rx[22:0], sdata_in};
                end
            end
        end
    end

    // --- TX LOGIC (Cambio dati su NEGedge) ---
    // Per rispettare l'I2S, guidiamo i dati sul fronte di discesa
    // così il codec li legge sul fronte di salita successivo.
    reg [23:0] shift_reg_tx;
    reg [23:0] latched_tx_data; // Dati da inviare (loopback)
    reg        lrclk_tx_d1;
    reg [4:0]  bit_cnt_tx;

    always @(negedge bclk or negedge reset_n) begin
        if (!reset_n) begin
            lrclk_tx_d1   <= 1'b0;
            shift_reg_tx  <= 24'd0;
            latched_tx_data <= 24'd0;
            bit_cnt_tx    <= 5'd0;
        end else begin
            lrclk_tx_d1 <= lrclk;

            // Rilevamento fronte LRCLK (sul negedge per sincronia TX)
            if (lrclk_tx_d1 != lrclk) begin
                bit_cnt_tx <= 5'd0;
                // Carichiamo i dati da trasmettere.
                // Usiamo i dati appena ricevuti (loopback semplice)
                latched_tx_data <= shift_reg_rx; 
            end else begin
                if (bit_cnt_tx < 5'd24) begin
                    bit_cnt_tx <= bit_cnt_tx + 1'b1;
                    // Al primo ciclo (bit_cnt_tx=0) non shiftiamo ancora per creare
                    // il ritardo di 1 ciclo I2S, o carichiamo l'MSB.
                    if (bit_cnt_tx == 0)
                        shift_reg_tx <= latched_tx_data; // Carica MSB
                    else
                        shift_reg_tx <= {shift_reg_tx[22:0], 1'b0}; // Shift
                end else begin
                    shift_reg_tx <= 24'd0; // Silence after 24 bits
                end
            end
        end
    end

    // Assegnazione output (MSB del registro)
    // Nota: I2S richiede che durante il ciclo di ritardo l'uscita sia valida.
    // Spesso si lascia il bit precedente o 0. Qui guidiamo MSB.
    assign sdata_out = shift_reg_tx[23];

endmodule