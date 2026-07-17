`timescale 1ns/1ps
`include "config.sv"

module postprocessor_rup (
  input logic clk,
  input logic rst,
  
  // Sinyal input utama dari sistem luar (diteruskan langsung ke core)
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
  
  // Sinyal output aman ke sistem luar (keluar dari buffer)
  output logic [CCW-1:0] safe_bdo,
  output logic safe_bdo_valid,
  input logic safe_bdo_ready,
  output logic [3:0] safe_bdo_type,
  output logic safe_bdo_eot,
  
  // Sinyal otentikasi
  output logic auth,
  output logic auth_valid
);

  // Sinyal internal untuk menjembatani output core ke FIFO
  logic [CCW-1:0] core_bdo;
  logic core_bdo_valid;
  logic core_bdo_ready;
  logic [3:0] core_bdo_type;
  logic core_bdo_eot;
  logic core_bdo_eoo;

  // Memori FIFO sederhana (kedalaman 64 blok data)
  logic [CCW-1:0] fifo_data [0:63];
  logic [3:0] fifo_type [0:63];
  logic fifo_eot [0:63];
  
  int wr_ptr;
  int rd_ptr;
  logic flush_buffer;
  logic release_buffer;

  // Instansiasi Ascon Core asli milikmu
  ascon_core core_inst (
    .clk(clk), .rst(rst),
    .key(key), .key_valid(key_valid), .key_ready(key_ready),
    .bdi(bdi), .bdi_valid(bdi_valid), .bdi_ready(bdi_ready),
    .bdi_type(bdi_type), .bdi_eot(bdi_eot), .bdi_eoi(bdi_eoi),
    .mode(mode),
    .bdo(core_bdo), .bdo_valid(core_bdo_valid), .bdo_ready(core_bdo_ready),
    .bdo_type(core_bdo_type), .bdo_eot(core_bdo_eot), .bdo_eoo(core_bdo_eoo),
    .auth(auth), .auth_valid(auth_valid)
  );

  // Tahap 1: Logika Penulisan ke FIFO dari Core
  always_ff @(posedge clk or posedge rst) begin
    if (rst || flush_buffer) begin
      wr_ptr <= 0;
    end else if (core_bdo_valid && core_bdo_ready) begin
      // Tumpuk data dekripsi dari core ke dalam buffer
      fifo_data[wr_ptr] <= core_bdo;
      fifo_type[wr_ptr] <= core_bdo_type;
      fifo_eot[wr_ptr] <= core_bdo_eot;
      wr_ptr <= wr_ptr + 1;
    end
  end

  // Buffer selalu siap menerima data dari core jika belum penuh
  assign core_bdo_ready = (wr_ptr < 64) && !release_buffer;

  // Tahap 2: Logika Pengambilan Keputusan RUP
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      flush_buffer <= 0;
      release_buffer <= 0;
    end else if (auth_valid) begin
      if (auth == 1'b1) begin
        release_buffer <= 1; // Tag valid, izinkan baca buffer
      end else begin
        flush_buffer <= 1;   // Tag salah, hancurkan seluruh data
      end
    end else if (rd_ptr == wr_ptr && release_buffer) begin
      release_buffer <= 0; // Selesai membaca seluruh isi memori
    end else begin
      flush_buffer <= 0;
    end
  end

  // Tahap 3: Logika Pembacaan dari FIFO ke Sistem Luar
  always_ff @(posedge clk or posedge rst) begin
    if (rst || flush_buffer) begin
      rd_ptr <= 0;
      safe_bdo_valid <= 0;
    end else if (release_buffer && (rd_ptr < wr_ptr)) begin
      // Pindahkan data dari memori ke output jika diizinkan
      safe_bdo <= fifo_data[rd_ptr];
      safe_bdo_type <= fifo_type[rd_ptr];
      safe_bdo_eot <= fifo_eot[rd_ptr];
      safe_bdo_valid <= 1;
      
      // Majukan pointer jika sistem luar sudah mengambil datanya
      if (safe_bdo_ready) begin
        rd_ptr <= rd_ptr + 1;
      end
    end else begin
      safe_bdo_valid <= 0;
    end
  end

endmodule