`timescale 1ns / 1ps

module tb_ascon_top;

  logic clk;
  logic rst;
  logic sclk;
  logic cs_n;
  logic mosi;
  logic miso;

  ascon_top uut (
    .clk(clk),
    .rst(rst),
    .sclk(sclk),
    .cs_n(cs_n),
    .mosi(mosi),
    .miso(miso)
  );

  // Mencegah kabel floating (X) pada internal ascon_top mengganggu simulasi
  initial begin
    force uut.bdo_eoo = 1'b0;
  end

  always #5 clk = ~clk;

  task spi_transfer(input logic [7:0] tx_byte, output logic [7:0] rx_byte);
    for (int i = 7; i >= 0; i--) begin
      mosi = tx_byte[i];
      #50;       
      sclk = 1;  
      rx_byte[i] = miso;
      #50;       
      sclk = 0;  
    end
  endtask

  task spi_send_block(input logic [7:0] cmd, input logic [127:0] data, input int num_bytes);
    logic [7:0] rx_dummy;
    logic [7:0] byte_to_send;

    $display("[%0t] Memulai Transaksi SPI - CMD: %h", $time, cmd);
    cs_n = 0;
    #50;

    spi_transfer(cmd, rx_dummy);

    for (int i = 0; i < num_bytes; i++) begin
      byte_to_send = data[127 - (i*8) -: 8];
      spi_transfer(byte_to_send, rx_dummy);
    end

    #50;
    cs_n = 1;
    $display("[%0t] Transaksi SPI Selesai\n", $time);
    #200; 
  endtask

  initial begin
    clk = 0;
    rst = 1;
    sclk = 0;
    cs_n = 1;
    mosi = 0;

    $display("==================================================");
    $display("   MEMULAI VERIFIKASI ASCON SPI CONTROLLER        ");
    $display("==================================================\n");

    #100; rst = 0; #100;

    // Uji 1: Mengirim Kunci (Command 0x10)
    spi_send_block(8'h10, 128'h000102030405060708090A0B0C0D0E0F, 16);

    // Uji 2: Mengirim Nonce (Command 0x20)
    spi_send_block(8'h20, 128'h101112131415161718191A1B1C1D1E1F, 16);

    // Uji 3: Mengirim AD (Command 0x30)
    spi_send_block(8'h30, 128'h303132333435363738393A3B3C3D3E3F, 16);

    // Uji 4: Mengirim Plaintext (Command 0x40)
    spi_send_block(8'h40, 128'h00112233445566778899aabbccddeeff, 16);

    #1000;
    $display("==================================================");
    $display("   SIMULASI SELESAI                               ");
    $display("==================================================");
    $finish;
  end

  initial begin
    #70000;
    $display("[ERROR] Timeout tercapai!");
    $finish;
  end

  // ---------------------------------------------------------
  // BLOK PEMANTAU (MONITOR) OTOMATIS
  // ---------------------------------------------------------
  always @(posedge clk) begin
    if (uut.key_valid && uut.key_ready) begin
      $display("   -> [MONITOR] Ascon Core menerima 32-bit KEY  : %x", uut.key);
    end
    
    if (uut.bdi_valid != 4'b0000 && uut.bdi_ready) begin
      $display("   -> [MONITOR] Ascon Core menerima 32-bit DATA : %x (Tipe: %0d)", uut.bdi, uut.bdi_type);
    end
  end

endmodule