module TOPM (
    input  wire        RST_N,       // Reset 
    input  wire        SPI_CS_N,    // Chip Select
    input  wire        SPI_SCLK,    // Main Clock
    input  wire        SPI_MOSI,    // Data in
    
    output wire        SPI_MISO,    // Data out
    output wire        IRQ          // Data ready interrupt
);

    wire [9:0] w_key;
    wire [7:0] w_plaintext;
    wire       w_sdes_en;
    wire [7:0] w_ciphertext;

    spi_control u_spi_block (
        .spi_sclk(SPI_SCLK),        // Single-clock architecture
        .rst_n(RST_N),
        .spi_cs_n(SPI_CS_N),
        .spi_mosi(SPI_MOSI),
        .spi_miso(SPI_MISO),
        .irq(IRQ),                  
        
        .parallel_key(w_key),
        .parallel_data(w_plaintext),
        .data_ready(w_sdes_en),
        .ciphertext_in(w_ciphertext)
    );

    SDES u_sdes_core (
        .encrypt(1'b1),             
        .en(w_sdes_en),
        .key(w_key),
        .plaintext(w_plaintext),
        .ciphertext(w_ciphertext)
    );

endmodule