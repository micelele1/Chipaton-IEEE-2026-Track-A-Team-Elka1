`timescale 1ns/1ps
`include "config.sv"

module tb_ascon_core_aead;

  logic clk;
  logic rst;

  logic [CCW-1:0] key;
  logic key_valid;
  logic key_ready;

  logic [CCW-1:0] bdi;
  logic [CCW/8-1:0] bdi_valid;
  logic bdi_ready;
  logic [3:0] bdi_type;
  logic bdi_eot;
  logic bdi_eoi;
  logic [3:0] mode;

  logic [CCW-1:0] bdo;
  logic bdo_valid;
  logic bdo_ready;
  logic [3:0] bdo_type;
  logic bdo_eot;
  logic bdo_eoo;

  logic auth;
  logic auth_valid;

  ascon_core dut (
    .clk(clk),
    .rst(rst),
    .key(key),
    .key_valid(key_valid),
    .key_ready(key_ready),
    .bdi(bdi),
    .bdi_valid(bdi_valid),
    .bdi_ready(bdi_ready),
    .bdi_type(bdi_type),
    .bdi_eot(bdi_eot),
    .bdi_eoi(bdi_eoi),
    .mode(mode),
    .bdo(bdo),
    .bdo_valid(bdo_valid),
    .bdo_ready(bdo_ready),
    .bdo_type(bdo_type),
    .bdo_eot(bdo_eot),
    .bdo_eoo(bdo_eoo),
    .auth(auth),
    .auth_valid(auth_valid)
  );

  always #5 clk = ~clk;

  typedef struct {
    logic [127:0] k;
    logic [127:0] n;
    logic [127:0] expected_tag;
  } kat_vector_t;

  kat_vector_t test_vectors[2] = '{
    '{128'h000102030405060708090A0B0C0D0E0F, 128'h000102030405060708090A0B0C0D0E0F, 128'h4427d64b8e1e1451fc445960f0839bb0},
    '{128'h000102030405060708090A0B0C0D0E0F, 128'h000102030405060708090A0B0C0D0E0F, 128'h4427d64b8e1e1451fc445960f0839bb0}
  };

  // Fix 1: Tambah 'automatic' dan jeda '#1' setelah clock
  task automatic send_key(input logic [127:0] k);
    key_valid = 1;
    for (int i=0; i<4; i++) begin
      logic [31:0] k_word;
      k_word = k[127 - 32*i -: 32]; 
      
      key = {k_word[7:0], k_word[15:8], k_word[23:16], k_word[31:24]};
      
      wait(key_ready);
      @(posedge clk); #1; 
    end
    key_valid = 0;
  endtask

  // Fix 2: Tambah 'automatic' dan jeda '#1' setelah clock
  task automatic send_nonce(input logic [127:0] n, input logic eoi);
    bdi_valid = 4'b1111;
    bdi_type = 4'd1; 
    bdi_eot = 1;
    bdi_eoi = 0;
    for (int i=0; i<4; i++) begin
      logic [31:0] n_word;
      n_word = n[127 - 32*i -: 32]; 
      
      bdi = {n_word[7:0], n_word[15:8], n_word[23:16], n_word[31:24]};
      
      if (i == 3) bdi_eoi = eoi; 
      wait(bdi_ready);
      @(posedge clk); #1;
    end
    bdi_valid = 0;
    bdi_type = 4'd0; 
    bdi_eot = 0;
    bdi_eoi = 0;
  endtask

  int total_pass;
  int total_fail;
  logic [127:0] actual_tag;
  int tag_words;

  initial begin
    clk = 0;
    rst = 1;
    key = 0;
    key_valid = 0;
    bdi = 0;
    bdi_valid = 0;
    bdi_type = 4'd0; 
    bdi_eot = 0;
    bdi_eoi = 0;
    mode = 4'd0; 
    bdo_ready = 1;
    bdo_eoo = 0;
    
    total_pass = 0;
    total_fail = 0;

    $display("==================================================");
    $display("Memulai Simulasi Otomatis KAT ASCON-AEAD128");
    $display("==================================================");

    for (int i = 0; i < 2; i++) begin
      $display("\n--- Menjalankan Kasus Uji %0d ---", i+1);
      
      // Fix 3: Matikan semua sinyal valid sebelum reset agar hardware bersih
      key_valid = 0;
      bdi_valid = 0;
      mode = 4'd0;
      @(posedge clk); #1;
      
      // Fix 4: Reset diperpanjang biar FSM balik ke IDLE dengan sempurna
      rst = 1;
      #100;
      rst = 0;
      @(posedge clk); #1;

      mode = 4'd1; 
      send_key(test_vectors[i].k);
      send_nonce(test_vectors[i].n, 1'b1);

      tag_words = 0;
      actual_tag = 128'h0;
      
      // Fix 5: Ganti fork-join pakai timeout counter. AMAN 100%.
      begin : wait_for_tag
        int timeout_ctr;
		  timeout_ctr = 0;
        
        while (tag_words < 4) begin
          @(posedge clk);
          timeout_ctr++;
          
          if (bdo_valid && bdo_ready && bdo_type == 4'd4) begin 
            actual_tag[127 - 32*tag_words -: 32] = {bdo[7:0], bdo[15:8], bdo[23:16], bdo[31:24]};
            tag_words++;
          end
          
          // Jika sudah nunggu 2000 siklus clock (20us) tapi tag gak lengkap, stop paksanya
          if (timeout_ctr > 2000) begin
            $display("[Error] Timeout! FSM macet atau Tag tidak keluar sepenuhnya.");
            break;
          end
        end
      end

      if (actual_tag == test_vectors[i].expected_tag && tag_words == 4) begin
        $display("[HASIL] PASS");
        $display("  -> Expected Tag : %x", test_vectors[i].expected_tag);
        $display("  -> Actual Tag   : %x", actual_tag);
        total_pass++;
      end else begin
        $display("[HASIL] FAIL");
        $display("  -> Expected Tag : %x", test_vectors[i].expected_tag);
        $display("  -> Actual Tag   : %x", actual_tag);
        total_fail++;
      end
    end

    $display("\n==================================================");
    $display("Simulasi Selesai.");
    $display("Total PASS: %0d | Total FAIL: %0d", total_pass, total_fail);
    $display("==================================================");
    $finish;
  end

endmodule
