module TOPM (
    input  wire       CLK,            // Main Board Clock (Pin fisik baru)
    input  wire       RST_N,          // Reset Global (Pin fisik baru)
    input  wire       encrypt,        // 1 = Enkripsi, 0 = Dekripsi
    
    // Jalur Bus SPI (4 Pin Fisik Pengganti 12 Pin Lama)
    input  wire       SelectButton,   // Di-remap menjadi SPI_CS_N
    input  wire       SPI_SCLK,       // SPI Clock dari CPU Drone
    input  wire       DataInBlock_0,  // Di-remap menjadi SPI_MOSI (Pin serial input)
    output wire       DataOutBlock_0  // Di-remap menjadi SPI_MISO (Pin serial output)
);

    // ---- 1. Kabel Jalur Interkoneksi Internal (Wire) ----
    wire [9:0] w_key;
    wire [7:0] w_plaintext;
    wire       w_sdes_en;
    wire [7:0] w_ciphertext;

    // ---- 2. Instansiasi Blok SPI Controller (Anak Buah 1) ----
    spi_control u_spi_block (
        .clk(CLK),
        .rst_n(RST_N),
        .spi_cs_n(SelectButton),     // Menghubungkan pin CS luar
        .spi_sclk(SPI_SCLK),         // Menghubungkan pin SCLK luar
        .spi_mosi(DataInBlock_0),    // Menghubungkan pin MOSI luar
        .spi_miso(DataOutBlock_0),    // Menghubungkan pin MISO luar
        
        .parallel_key(w_key),        // Bus internal menyalurkan Key ke S-DES
        .parallel_data(w_plaintext),  // Bus internal menyalurkan Plaintext ke S-DES
        .data_ready(w_sdes_en),      // Kabel kontrol memicu eksekusi S-DES
        .ciphertext_in(w_ciphertext) // Menerima hasil acakan dari S-DES
    );

    // ---- 3. Instansiasi Blok S-DES Core / File En Lama (Anak Buah 2) ----
    // Nama port input-output di bawah ini harus disesuaikan dengan isi file En.v lu
    SDES u_sdes_core (
        .encrypt(encrypt),
        .en(w_sdes_en),              // Hanya aktif saat diketok FSM SPI
        .key(w_key),                 // Menerima pasokan Key paralel dari SPI
        .plaintext(w_plaintext),     // Menerima pasokan Plaintext paralel dari SPI
        .ciphertext(w_ciphertext)    // Memuntahkan hasil acakan 8-bit ke kabel internal
    );

endmodule