`timescale 1ns/1ps
`include "config.sv"

// ==============================================================================
// MODUL WRAPPER: POSTPROCESSOR RUP 
// ==============================================================================
module postprocessor_rup (
  input logic clk,
  input logic rst,
  
  input logic [CCW-1:0] key,
  input logic key_valid,
  output logic key_ready,
  input logic [CCW-1:0] bdi,
  input logic [CCW/8-1:0] bdi_valid,
  output logic bdi_ready,
  input logic [3:0] bdi_type,
  input logic bdi_eot,
  input logic bdi_eoi,
  input logic [3:0] mode,
  
  output logic [CCW-1:0] safe_bdo,
  output logic safe_bdo_valid,
  input logic safe_bdo_ready,
  output logic [3:0] safe_bdo_type,
  output logic safe_bdo_eot,
  input logic bdo_eoo, 
  
  output logic auth,
  output logic auth_valid
);

  logic [CCW-1:0] core_bdo;
  logic core_bdo_valid;
  logic core_bdo_ready;
  logic [3:0] core_bdo_type;
  logic core_bdo_eot;

  logic [CCW-1:0] fifo_data [0:63];
  logic [3:0] fifo_type [0:63];
  logic fifo_eot [0:63];
  
  int wr_ptr;
  int rd_ptr;
  logic flush_buffer;
  logic release_buffer;

  logic is_decrypt;
  assign is_decrypt = (mode == 4'd2); 

  ascon_core core_inst (
    .clk(clk), .rst(rst),
    .key(key), .key_valid(key_valid), .key_ready(key_ready),
    .bdi(bdi), .bdi_valid(bdi_valid), .bdi_ready(bdi_ready),
    .bdi_type(bdi_type), .bdi_eot(bdi_eot), .bdi_eoi(bdi_eoi),
    .mode(mode),
    .bdo(core_bdo), .bdo_valid(core_bdo_valid), .bdo_ready(core_bdo_ready),
    .bdo_type(core_bdo_type), .bdo_eot(core_bdo_eot), .bdo_eoo(bdo_eoo),
    .auth(auth), .auth_valid(auth_valid)
  );

  assign safe_bdo      = is_decrypt ? fifo_data[rd_ptr] : core_bdo;
  assign safe_bdo_type = is_decrypt ? fifo_type[rd_ptr] : core_bdo_type;
  assign safe_bdo_eot  = is_decrypt ? fifo_eot[rd_ptr]  : core_bdo_eot;

  always_comb begin
    if (is_decrypt) begin
      safe_bdo_valid = (release_buffer && (rd_ptr < wr_ptr)) ? 1'b1 : 1'b0;
      core_bdo_ready = (wr_ptr < 64) && !release_buffer;
    end else begin
      safe_bdo_valid = core_bdo_valid;
      core_bdo_ready = safe_bdo_ready;
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst || flush_buffer) begin
      wr_ptr <= 0;
    end else if (is_decrypt && core_bdo_valid && core_bdo_ready) begin
      fifo_data[wr_ptr] <= core_bdo;
      fifo_type[wr_ptr] <= core_bdo_type;
      fifo_eot[wr_ptr] <= core_bdo_eot;
      wr_ptr <= wr_ptr + 1;
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      flush_buffer <= 0;
      release_buffer <= 0;
    end else if (is_decrypt) begin
      if (auth_valid) begin
        if (auth == 1'b1) release_buffer <= 1; 
        else flush_buffer <= 1;                
      end else if (rd_ptr == wr_ptr && release_buffer) begin
        release_buffer <= 0; 
      end else begin
        flush_buffer <= 0;
      end
    end else begin
      flush_buffer <= 0;
      release_buffer <= 0;
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst || flush_buffer || !is_decrypt) begin
      rd_ptr <= 0;
    end else if (is_decrypt && release_buffer && (rd_ptr < wr_ptr) && safe_bdo_ready) begin
      rd_ptr <= rd_ptr + 1;
    end
  end
endmodule


// ==============================================================================
// TESTBENCH UTAMA 
// ==============================================================================
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

  logic [CCW-1:0] safe_bdo;
  logic safe_bdo_valid;
  logic safe_bdo_ready;
  logic [3:0] safe_bdo_type;
  logic safe_bdo_eot;
  logic bdo_eoo;

  logic auth;
  logic auth_valid;

  postprocessor_rup dut (
    .clk(clk), .rst(rst),
    .key(key), .key_valid(key_valid), .key_ready(key_ready),
    .bdi(bdi), .bdi_valid(bdi_valid), .bdi_ready(bdi_ready),
    .bdi_type(bdi_type), .bdi_eot(bdi_eot), .bdi_eoi(bdi_eoi),
    .mode(mode),
    .safe_bdo(safe_bdo), .safe_bdo_valid(safe_bdo_valid),
    .safe_bdo_ready(safe_bdo_ready), .safe_bdo_type(safe_bdo_type),
    .safe_bdo_eot(safe_bdo_eot), .bdo_eoo(bdo_eoo),
    .auth(auth), .auth_valid(auth_valid)
  );

  always #5 clk = ~clk;

  typedef struct {
    string name;
    logic [127:0] k;
    logic [127:0] n;
    int ad_len; 
    logic [255:0] ad;
    int pt_len; 
    logic [255:0] pt;
    logic [255:0] ct;
    logic [127:0] tag;
  } kat_vector_t;

  kat_vector_t test_vectors[2];

  initial begin
    // Nilai murni dari KAT NIST Ascon-AEAD128
    
    test_vectors[0].name = "Kasus 1: Count 1 (PT Kosong, AD Kosong)";
    test_vectors[0].k = 128'h000102030405060708090A0B0C0D0E0F;
    test_vectors[0].n = 128'h101112131415161718191A1B1C1D1E1F;
    test_vectors[0].ad_len = 0;
    test_vectors[0].ad = 256'h0;
    test_vectors[0].pt_len = 0;
    test_vectors[0].pt = 256'h0;
    test_vectors[0].ct = 256'h0;
    test_vectors[0].tag = 128'h4F9C278211BEC9316BF68F46EE8B2EC6;

    test_vectors[1].name = "Kasus 2: Count 57 (AD=23 byte, PT=1 byte)";
    test_vectors[1].k = 128'h000102030405060708090A0B0C0D0E0F;
    test_vectors[1].n = 128'h101112131415161718191A1B1C1D1E1F;
    test_vectors[1].ad_len = 23;
    test_vectors[1].ad = {184'h303132333435363738393A3B3C3D3E3F40414243444546, 72'h0}; 
    test_vectors[1].pt_len = 1;
    test_vectors[1].pt = {8'h20, 248'h0};
    test_vectors[1].ct = {8'h78, 248'h0};
    test_vectors[1].tag = 128'h09DAE4F15C2040B70B2BE56EB76A060C;
  end

  task send_key(input logic [127:0] k);
    logic [31:0] k_word;
    key_valid = 1;
    for (int i=0; i<4; i++) begin
      k_word = k[127 - 32*i -: 32];
      key = {k_word[7:0], k_word[15:8], k_word[23:16], k_word[31:24]};
      do begin @(posedge clk); end while (!key_ready);
    end
    key_valid = 0;
  endtask

  task send_bytes(input logic [255:0] data, input int len_bytes, input logic [3:0] d_type, input logic eoi);
    int bytes_in_word;
    logic [31:0] word;
    logic [3:0] valid;
    
    if (len_bytes == 0) return;
    
    bdi_type = d_type;
    bdi_eoi = 0;
    
    for (int i = 0; i < len_bytes; i += 4) begin
      bytes_in_word = (len_bytes - i >= 4) ? 4 : (len_bytes - i);
      
      if (bytes_in_word == 1) valid = 4'b0001;
      else if (bytes_in_word == 2) valid = 4'b0011;
      else if (bytes_in_word == 3) valid = 4'b0111;
      else valid = 4'b1111;
      
      bdi_eot = (i + 4 >= len_bytes) ? 1'b1 : 1'b0;
      if (bdi_eot) bdi_eoi = eoi;
      else bdi_eoi = 0;
      
      word[31:24] = (bytes_in_word >= 1) ? data[255 - i*8 -: 8] : 8'h00;
      word[23:16] = (bytes_in_word >= 2) ? data[255 - (i+1)*8 -: 8] : 8'h00;
      word[15:8]  = (bytes_in_word >= 3) ? data[255 - (i+2)*8 -: 8] : 8'h00;
      word[7:0]   = (bytes_in_word == 4) ? data[255 - (i+3)*8 -: 8] : 8'h00;
      
      bdi = {word[7:0], word[15:8], word[23:16], word[31:24]};
      bdi_valid = valid;
      
      do begin @(posedge clk); end while (!bdi_ready);
    end
    bdi_valid = 0;
    bdi_type = 4'd0;
    bdi_eot = 0;
    bdi_eoi = 0;
  endtask

  task send_tag(input logic [127:0] t, input logic corrupt);
    logic [127:0] data_to_send;
    logic [31:0] t_word;
    
    data_to_send = corrupt ? (t ^ 128'h00000000000000000000000000000001) : t;
    
    bdi_type = 4'd4; 
    bdi_eoi = 1; 
    
    for (int i=0; i<4; i++) begin
      t_word = data_to_send[127 - 32*i -: 32];
      
      bdi_eot = (i == 3) ? 1'b1 : 1'b0;
      bdi_valid = 4'b1111;
      bdi = {t_word[7:0], t_word[15:8], t_word[23:16], t_word[31:24]};
      
      do begin @(posedge clk); end while (!bdi_ready);
    end
    bdi_valid = 0;
    bdi_type = 4'd0;
    bdi_eot = 0;
    bdi_eoi = 0;
  endtask

  logic rup_violation;
  always @(posedge clk) begin
    if (mode == 4'd2 && safe_bdo_valid && !auth_valid && auth !== 1'b1) begin
       rup_violation = 1;
    end
  end

  initial begin
    logic [255:0] actual_pt;
    int bytes_read;
    int timeout_cnt;
    int bytes_this_word;

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
    safe_bdo_ready = 1;
    bdo_eoo = 0;

    $display("==================================================");
    $display("Memulai Simulasi Lanjutan DEKRIPSI & RUP ASCON");
    $display("==================================================");

    for (int i = 0; i < 2; i++) begin
      
      $display("\n--- DEKRIPSI NORMAL: %s ---", test_vectors[i].name);
      rst = 1; #20; rst = 0; @(posedge clk);
      rup_violation = 0;
      mode = 4'd2; 

      send_key(test_vectors[i].k);
      send_bytes({test_vectors[i].n, 128'h0}, 16, 4'd1, (test_vectors[i].ad_len == 0 && test_vectors[i].pt_len == 0)); 
      
      if (test_vectors[i].ad_len > 0) begin
         send_bytes(test_vectors[i].ad, test_vectors[i].ad_len, 4'd2, (test_vectors[i].pt_len == 0));
      end

      if (test_vectors[i].pt_len > 0) begin
         send_bytes(test_vectors[i].ct, test_vectors[i].pt_len, 4'd3, 1'b1); 
      end

      send_tag(test_vectors[i].tag, 0); 

      wait(auth_valid == 1'b1);
      @(posedge clk);

      if (auth == 1'b1) begin
         $display("[INFO] Otentikasi Berhasil.");
         if (rup_violation) $display("[FAIL] RUP Violation! Plaintext bocor sebelum auth disetujui.");
         else $display("[PASS] FIFO bekerja sempurna, aman dari RUP.");

         if (test_vectors[i].pt_len > 0) begin
            actual_pt = 0;
            bytes_read = 0;
            timeout_cnt = 0;
            
            while (bytes_read < test_vectors[i].pt_len && timeout_cnt < 200) begin
               if (safe_bdo_valid && safe_bdo_ready && safe_bdo_type == 4'd3) begin
                  bytes_this_word = (test_vectors[i].pt_len - bytes_read >= 4) ? 4 : (test_vectors[i].pt_len - bytes_read);
                  
                  if (bytes_this_word >= 1) actual_pt[255 - bytes_read*8 -: 8] = safe_bdo[7:0];
                  if (bytes_this_word >= 2) actual_pt[255 - (bytes_read+1)*8 -: 8] = safe_bdo[15:8];
                  if (bytes_this_word >= 3) actual_pt[255 - (bytes_read+2)*8 -: 8] = safe_bdo[23:16];
                  if (bytes_this_word == 4) actual_pt[255 - (bytes_read+3)*8 -: 8] = safe_bdo[31:24];
                  
                  bytes_read += bytes_this_word;
               end
               @(posedge clk);
               timeout_cnt++;
            end

            if (actual_pt == test_vectors[i].pt) begin
               $display("[PASS] Plaintext dekripsi cocok persis dengan KAT");
            end else begin
               $display("[FAIL] Plaintext salah!\n  -> Exp: %x\n  -> Act: %x", test_vectors[i].pt, actual_pt);
            end
         end
      end else begin
         $display("[FAIL] Otentikasi Gagal padahal Tag asli!");
      end


      if (test_vectors[i].pt_len > 0) begin
        $display("\n--- UJI RUP DENGAN SERANGAN: %s ---", test_vectors[i].name);
        rst = 1; #20; rst = 0; @(posedge clk);
        rup_violation = 0;
        mode = 4'd2; 

        send_key(test_vectors[i].k);
        send_bytes({test_vectors[i].n, 128'h0}, 16, 4'd1, 0); 
        send_bytes(test_vectors[i].ad, test_vectors[i].ad_len, 4'd2, 0);
        send_bytes(test_vectors[i].ct, test_vectors[i].pt_len, 4'd3, 1'b1); 
        
        send_tag(test_vectors[i].tag, 1); 

        wait(auth_valid == 1'b1);
        @(posedge clk);

        if (auth == 1'b0) begin
           $display("[INFO] Otentikasi Ditolak (Sesuai Ekspektasi).");
           if (rup_violation) $display("[FAIL] RUP Violation! Terdapat data Plaintext yang merembes keluar!");
           else $display("[PASS] Aman dari RUP. Buffer FIFO berhasil dihancurkan, nol data bocor.");
        end else begin
           $display("[FAIL] Otentikasi malah berhasil padahal Tag sudah dirusak!");
        end
      end

    end

    $display("\n==================================================");
    $display("Simulasi Selesai.");
    $display("==================================================");
    $finish;
  end

  initial begin
    #15000;
    $display("[Error] Timeout simulasi tercapai! FSM kemungkinan macet.");
    $finish;
  end

endmodule