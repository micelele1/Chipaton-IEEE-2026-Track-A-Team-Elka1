`timescale 1ns/1ps

module tb_ascon_top_final;

  logic clk;
  logic rst;
  logic sclk;
  logic cs_n;
  logic mosi;
  logic miso;

  int spi_period = 80; 
  logic [7:0] rx_byte;

  always #5 clk = ~clk; 

  ascon_top dut (
    .clk(clk), .rst(rst), .sclk(sclk), .cs_n(cs_n), .mosi(mosi), .miso(miso)
  );

  logic [31:0] captured_ct [$];
  logic [31:0] captured_tag [$];
  logic [31:0] captured_dec_pt [$];
  
  logic final_auth_valid;
  logic final_auth_flag;

  always_ff @(posedge clk) begin
    if (rst) begin
      final_auth_valid <= 1'b0;
      final_auth_flag  <= 1'b0;
    end else begin
      // Menangkap output safe_bdo dari spi_controller
      if (dut.spi_ctrl.bdo_valid && dut.spi_ctrl.bdo_ready) begin
        // Perbaikan path hierarchy ke pp_inst.core_inst
        if (dut.pp_inst.core_inst.mode_q == 4'd1) begin 
          if (dut.spi_ctrl.bdo_type == 4'd3) captured_ct.push_back(dut.spi_ctrl.bdo);
          if (dut.spi_ctrl.bdo_type == 4'd4) captured_tag.push_back(dut.spi_ctrl.bdo);
        end 
        else if (dut.pp_inst.core_inst.mode_q == 4'd2) begin 
          if (dut.spi_ctrl.bdo_type == 4'd3) captured_dec_pt.push_back(dut.spi_ctrl.bdo);
        end
      end
      
      // Perbaikan path hierarchy ke pp_inst.core_inst
      if (dut.pp_inst.core_inst.auth_valid) begin
        final_auth_valid <= 1'b1;
        final_auth_flag  <= dut.pp_inst.core_inst.auth;
      end
    end
  end

  task spi_trx(input logic [7:0] tx_data, output logic [7:0] rx_data);
    rx_data = 8'h00;
    for (int i = 7; i >= 0; i--) begin
      mosi = tx_data[i]; #(spi_period/2);
      sclk = 1'b1; rx_data[i] = miso; #(spi_period/2);
      sclk = 1'b0;
    end
  endtask

  task send_spi_payload(input logic [7:0] cmd, input byte payload[]);
    cs_n = 0; #(spi_period);
    spi_trx(cmd, rx_byte); 
    for(int i = 0; i < payload.size(); i++) begin
      spi_trx(payload[i], rx_byte); 
    end
    #50; cs_n = 1; #200; 
  endtask

  task flush_miso(input int bytes_to_read);
    cs_n = 0; #(spi_period);
    spi_trx(8'h60, rx_byte); 
    for(int i = 0; i < bytes_to_read; i++) spi_trx(8'h00, rx_byte);
    #50; cs_n = 1; #200;
  endtask

  byte KEY[]   = '{8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0E, 8'h0F};
  byte NONCE[] = '{8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01};
  byte AD[]    = '{8'h41, 8'h73, 8'h63, 8'h6F, 8'h6E, 8'h20, 8'h41, 8'h44, 8'h20, 8'h54, 8'h65, 8'h73, 8'h74, 8'h21, 8'h21, 8'h21}; 
  byte PT[]    = '{8'h48, 8'h65, 8'h6C, 8'h6C, 8'h6F, 8'h20, 8'h46, 8'h50, 8'h47, 8'h41, 8'h20, 8'h57, 8'h6F, 8'h72, 8'h6C, 8'h64}; 
  
  byte dyn_CT[];
  byte dyn_TAG[];
  byte corrupt_TAG[];
  
  byte mode_enc[];
  byte mode_dec[];

  initial begin
    mode_enc = new[1]; mode_enc[0] = 8'h01;
    mode_dec = new[1]; mode_dec[0] = 8'h02;

    $timeformat(-9, 0, " ns", 10); 
    clk = 0; rst = 1; sclk = 0; cs_n = 1; mosi = 0;
    #100; rst = 0; #100;

    $display("==================================================");
    $display(" ASCON AEAD128 FULL SYSTEM VERIFICATION");
    $display("==================================================");

    // SKENARIO 1: ENKRIPSI
    $display("\n---> [SKENARIO 1] ENKRIPSI DIMULAI");
    
    send_spi_payload(8'h50, mode_enc);
    send_spi_payload(8'h10, KEY);
    send_spi_payload(8'h20, NONCE);
    send_spi_payload(8'h30, AD);
    send_spi_payload(8'h40, PT);

    // Langsung flush karena M_AEAD128_ENC mem-bypass FIFO
    flush_miso(32); 

    dyn_CT  = new[captured_ct.size() * 4];
    dyn_TAG = new[captured_tag.size() * 4];
    corrupt_TAG = new[captured_tag.size() * 4];
    
    foreach(captured_ct[i]) begin
      dyn_CT[i*4]   = captured_ct[i][31:24]; dyn_CT[i*4+1] = captured_ct[i][23:16];
      dyn_CT[i*4+2] = captured_ct[i][15:8];  dyn_CT[i*4+3] = captured_ct[i][7:0];
    end
    foreach(captured_tag[i]) begin
      dyn_TAG[i*4]   = captured_tag[i][31:24]; dyn_TAG[i*4+1] = captured_tag[i][23:16];
      dyn_TAG[i*4+2] = captured_tag[i][15:8];  dyn_TAG[i*4+3] = captured_tag[i][7:0];
      
      corrupt_TAG[i*4]   = captured_tag[i][31:24] ^ 8'hFF; corrupt_TAG[i*4+1] = captured_tag[i][23:16];
      corrupt_TAG[i*4+2] = captured_tag[i][15:8];  corrupt_TAG[i*4+3] = captured_tag[i][7:0];
    end

    // SKENARIO 2: DEKRIPSI VALID
    $display("\n---> [SKENARIO 2] DEKRIPSI VALID DIMULAI");
    
    rst = 1; #100; rst = 0; #100;
    captured_dec_pt.delete();

    send_spi_payload(8'h50, mode_dec);
    send_spi_payload(8'h10, KEY);
    send_spi_payload(8'h20, NONCE);
    send_spi_payload(8'h30, AD);
    send_spi_payload(8'h40, dyn_CT);
    send_spi_payload(8'h45, dyn_TAG); 
    
    // Tunggu sinyal validasi asli dari hardware (tidak lagi menggunakan delay statis)
    wait(final_auth_valid == 1'b1);
    #100;

    // Jika TAG benar, baru minta master SPI menarik data dari buffer
    if (final_auth_flag) begin
      flush_miso(16); 
    end

    if (final_auth_valid && final_auth_flag && captured_dec_pt.size() > 0)
      $display(" [PASS] Dekripsi Valid sukses. RUP melepaskan data.");
    else
      $display(" [FAIL] Dekripsi Valid gagal.");


    // SKENARIO 3: DEKRIPSI INVALID (SERANGAN)
    $display("\n---> [SKENARIO 3] DEKRIPSI INVALID DIMULAI");
    
    rst = 1; #100; rst = 0; #100;
    captured_dec_pt.delete();
    
    // Perbaikan: Tidak ada pemaksaan sinyal final_auth_valid = 0 di sini

    send_spi_payload(8'h50, mode_dec);
    send_spi_payload(8'h10, KEY);
    send_spi_payload(8'h20, NONCE);
    send_spi_payload(8'h30, AD);
    send_spi_payload(8'h40, dyn_CT);
    send_spi_payload(8'h45, corrupt_TAG); 
    
    // Tunggu sinyal penolakan dari hardware
    wait(final_auth_valid == 1'b1);
    #100;

    // Karena final_auth_flag bernilai 0 (salah), blok pembacaan SPI tidak akan tereksekusi
    if (final_auth_flag) begin
      flush_miso(16); 
    end

    if (final_auth_valid && !final_auth_flag && captured_dec_pt.size() == 0)
      $display(" [PASS] Serangan digagalkan. FIFO dikosongkan dan RUP menahan kebocoran data.");
    else
      $display(" [FAIL] RUP gagal menahan kebocoran.");

    $display("\n==================================================");
    $display(" SIMULASI SELESAI.");
    $display("==================================================");
    $finish;
  end

endmodule