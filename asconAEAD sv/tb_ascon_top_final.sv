`timescale 1ns/1ps

module tb_ascon_top_final;

  // ---------------------------------------------------------
  // Signal Declarations
  // ---------------------------------------------------------
  logic clk;
  logic rst;
  logic sclk;
  logic cs_n;
  logic mosi;
  logic miso;

  int spi_period = 20; // 50 MHz SPI clock
  logic [7:0] rx_byte;

  // ---------------------------------------------------------
  // Clock Generation (100 MHz)
  // ---------------------------------------------------------
  always #5 clk = ~clk; 

  // ---------------------------------------------------------
  // DUT Instantiation
  // ---------------------------------------------------------
  ascon_top dut (
    .clk(clk), .rst(rst), .sclk(sclk), .cs_n(cs_n), .mosi(mosi), .miso(miso)
  );

  // ---------------------------------------------------------
  // Core Output Monitors & Pulse Traps
  // ---------------------------------------------------------
  logic [31:0] captured_ct [$];
  logic [31:0] captured_tag [$];
  logic [31:0] captured_dec_pt [$];
  
  logic final_auth_valid = 0;
  logic final_auth_flag  = 0;

  always_ff @(posedge clk) begin
    if (rst) begin
      final_auth_valid <= 1'b0;
      final_auth_flag  <= 1'b0;
    end else begin
      // Capture data directly from the core when valid
      if (dut.spi_ctrl.bdo_valid && dut.spi_ctrl.bdo_ready) begin
        if (dut.core_inst.mode_q == 4'd1) begin 
          if (dut.spi_ctrl.bdo_type == 4'd3) captured_ct.push_back(dut.spi_ctrl.bdo);
          if (dut.spi_ctrl.bdo_type == 4'd4) captured_tag.push_back(dut.spi_ctrl.bdo);
        end 
        else if (dut.core_inst.mode_q == 4'd2) begin 
          if (dut.spi_ctrl.bdo_type == 4'd3) captured_dec_pt.push_back(dut.spi_ctrl.bdo);
        end
      end
      
      // Trap the 1-cycle authentication pulse
      if (dut.core_inst.auth_valid) begin
        final_auth_valid <= 1'b1;
        final_auth_flag  <= dut.core_inst.auth;
      end
    end
  end

  // ---------------------------------------------------------
  // SPI Master Tasks
  // ---------------------------------------------------------
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
    spi_trx(cmd, rx_byte); // Send Command
    for(int i = 0; i < payload.size(); i++) begin
      spi_trx(payload[i], rx_byte); // Send Data
    end
    #50; cs_n = 1; #200; // Hold time and transaction gap
  endtask

  task flush_miso(input int bytes_to_read);
    cs_n = 0; #(spi_period);
    spi_trx(8'h60, rx_byte); // CMD 0x60 (Read Data)
    for(int i = 0; i < bytes_to_read; i++) spi_trx(8'h00, rx_byte);
    #50; cs_n = 1; #200;
  endtask

  // ---------------------------------------------------------
  // Main Execution Flow
  // ---------------------------------------------------------
  byte KEY[]   = '{8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0E, 8'h0F};
  byte NONCE[] = '{8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01};
  byte AD[]    = '{8'h41, 8'h73, 8'h63, 8'h6F, 8'h6E, 8'h20, 8'h41, 8'h44, 8'h20, 8'h54, 8'h65, 8'h73, 8'h74, 8'h21, 8'h21, 8'h21}; // "Ascon AD Test!!!"
  byte PT[]    = '{8'h48, 8'h65, 8'h6C, 8'h6C, 8'h6F, 8'h20, 8'h46, 8'h50, 8'h47, 8'h41, 8'h20, 8'h57, 8'h6F, 8'h72, 8'h6C, 8'h64}; // "Hello FPGA World"
  
  byte dyn_CT[];
  byte dyn_TAG[];

  initial begin
    $timeformat(-9, 0, " ns", 10); 
    clk = 0; rst = 1; sclk = 0; cs_n = 1; mosi = 0;
    #100; rst = 0; #100;

    $display("==================================================");
    $display(" ASCON AEAD128 FULL SYSTEM VERIFICATION");
    $display("==================================================");

    // =========================================================
    // DATA DISPLAY: GIVEN INPUTS
    // =========================================================
    $display("\n---> [GIVEN DATA]");
    $write("KEY   : "); for(int i=0; i<KEY.size(); i++) $write("%02h", KEY[i]); $display("");
    $write("NONCE : "); for(int i=0; i<NONCE.size(); i++) $write("%02h", NONCE[i]); $display("");
    $write("AD    : "); for(int i=0; i<AD.size(); i++) $write("%02h", AD[i]); $display(" (ASCII: %p)", AD);
    $write("PT    : "); for(int i=0; i<PT.size(); i++) $write("%02h", PT[i]); $display(" (ASCII: %p)", PT);

    // =========================================================
    // PHASE 1: ENCRYPTION
    // =========================================================
    $display("\n---> [PHASE 1] ENCRYPTION STARTED");
    
    send_spi_payload(8'h10, KEY);
    send_spi_payload(8'h20, NONCE);
    #600; 
    
    send_spi_payload(8'h30, AD);
    #300; 

    send_spi_payload(8'h40, PT);
    flush_miso(32); 

    // Extract captured 32-bit words back into byte arrays
    dyn_CT  = new[captured_ct.size() * 4];
    dyn_TAG = new[captured_tag.size() * 4];
    
    foreach(captured_ct[i]) begin
      dyn_CT[i*4]   = captured_ct[i][31:24]; 
      dyn_CT[i*4+1] = captured_ct[i][23:16];
      dyn_CT[i*4+2] = captured_ct[i][15:8];  
      dyn_CT[i*4+3] = captured_ct[i][7:0];
    end
    foreach(captured_tag[i]) begin
      dyn_TAG[i*4]   = captured_tag[i][31:24]; 
      dyn_TAG[i*4+1] = captured_tag[i][23:16];
      dyn_TAG[i*4+2] = captured_tag[i][15:8];  
      dyn_TAG[i*4+3] = captured_tag[i][7:0];
    end

    // =========================================================
    // PHASE 2: DECRYPTION
    // =========================================================
    $display("\n---> [PHASE 2] DECRYPTION STARTED");
    
    // --> THE FIX: FORCE THE MODE BEFORE RELEASING RESET <--
    force dut.mode = 4'd2; 
    
    // Reset FSM. When it wakes up at rst=0, the mode is already 2!
    rst = 1; #100; rst = 0; #100;

    send_spi_payload(8'h10, KEY);
    send_spi_payload(8'h20, NONCE);
    #600; 
    
    send_spi_payload(8'h30, AD);
    #300; 

    // Feed the captured Ciphertext back in
    send_spi_payload(8'h40, dyn_CT);
    flush_miso(16); 
    #300; 

    // Override internal BDI Type net to 4 (D_TAG)
    force dut.bdi_type = 4'd4; 
    send_spi_payload(8'h40, dyn_TAG); 
    release dut.bdi_type;

    #500; 

    // =========================================================
    // PHASE 3: AUTOMATED CHECKING & DATA PROOF
    // =========================================================
    $display("\n---> [PHASE 3] OBTAINED DATA & VERIFICATION RESULTS");
    
    $write("CAPTURED CIPHERTEXT : ");
    for(int i=0; i<dyn_CT.size(); i++) $write("%02h", dyn_CT[i]);
    $display("");

    $write("CAPTURED TAG        : ");
    for(int i=0; i<dyn_TAG.size(); i++) $write("%02h", dyn_TAG[i]);
    $display("");

    $write("DECRYPTED PLAINTEXT : ");
    for(int i=0; i<captured_dec_pt.size(); i++) $write("%08h", captured_dec_pt[i]);
    $display("");

    $display("--------------------------------------------------");

    if (captured_dec_pt.size() == 0) begin
      $display("❌ FATAL: No plaintext was decrypted! The Ascon Core stalled or FSM locked.");
    end else begin
      int errors = 0;
      logic [31:0] expected_word;
      for (int i=0; i<captured_dec_pt.size(); i++) begin
        expected_word = {PT[i*4], PT[i*4+1], PT[i*4+2], PT[i*4+3]};
        if (captured_dec_pt[i] !== expected_word) begin
          $display("❌ MISMATCH at Word %0d! Expected: %h, Got: %h", i, expected_word, captured_dec_pt[i]);
          errors++;
        end
      end
      if (errors == 0) $display("✅ PLAINTEXT MATCH: Decrypted data perfectly matches original input.");
    end

    if (final_auth_valid) begin
      if (final_auth_flag) 
        $display("✅ AUTHENTICATION PASSED: Tag verified successfully.");
      else 
        $display("❌ AUTHENTICATION FAILED: Tag rejected by core!");
    end else begin
      $display("❌ AUTHENTICATION TIMEOUT: Core never asserted auth_valid.");
    end

    $display("\n==================================================");
    $display(" SIMULATION COMPLETE.");
    $display("==================================================");
    $finish;
  end

endmodule