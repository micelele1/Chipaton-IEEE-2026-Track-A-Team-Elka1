`timescale 1ns/1ps
`include "config.sv"

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
  
  output logic auth,
  output logic auth_valid
);

  logic [CCW-1:0] core_bdo;
  logic core_bdo_valid;
  logic core_bdo_ready;
  logic [3:0] core_bdo_type;
  logic core_bdo_eot;
  logic core_bdo_eoo;

  logic [CCW-1:0] fifo_data [0:63];
  logic [3:0] fifo_type [0:63];
  logic fifo_eot [0:63];
  
  logic [6:0] wr_ptr;  
  logic [6:0] rd_ptr;
  logic flush_buffer;
  logic release_buffer;

  // Deteksi mode dekripsi untuk bypass RUP
  logic is_decrypt;
  assign is_decrypt = (mode == 4'd2);

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

  // Bypass logika jika mode Enkripsi
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

  // Tahap 1: Penulisan FIFO (Hanya berlaku untuk Dekripsi)
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      wr_ptr <= 0;
    end else if (flush_buffer) begin
      wr_ptr <= 0;
    end else if (is_decrypt && core_bdo_valid && core_bdo_ready) begin
      fifo_data[wr_ptr] <= core_bdo;
      fifo_type[wr_ptr] <= core_bdo_type;
      fifo_eot[wr_ptr] <= core_bdo_eot;
      wr_ptr <= wr_ptr + 1;
    end
  end

  // Tahap 2: Pengambilan Keputusan RUP
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

  // Tahap 3: Pembacaan FIFO
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      rd_ptr <= 0;
    end else if (flush_buffer || !is_decrypt) begin
      rd_ptr <= 0;
    end else if (is_decrypt && release_buffer && (rd_ptr < wr_ptr) && safe_bdo_ready) begin
      rd_ptr <= rd_ptr + 1;
    end
  end

endmodule