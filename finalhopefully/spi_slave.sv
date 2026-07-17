`timescale 1ns/1ps

module spi_slave (
    input  logic       clk,      // System clock (Fast)
    input  logic       rst,      // Active-high synchronous reset

    // SPI Physical Interface (Eksternal)
    input  logic       sclk,
    input  logic       cs_n,
    input  logic       mosi,
    output logic       miso,

    // Parallel Interface ke SPI Controller (Internal)
    output logic [7:0] rx_data,
    output logic       rx_valid,
    input  logic [7:0] tx_data,
    output logic       tx_ready  // Sinyal meminta byte berikutnya dari controller
);

  // Tahap 1: Synchronizer (Mencegah Metastability dari sinyal eksternal)
  logic [2:0] sclk_sync;
  logic [2:0] cs_n_sync;
  logic [1:0] mosi_sync;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      sclk_sync <= 3'b000;
      cs_n_sync <= 3'b111;
      mosi_sync <= 2'b00;
    end else begin
      sclk_sync <= {sclk_sync[1:0], sclk};
      cs_n_sync <= {cs_n_sync[1:0], cs_n};
      mosi_sync <= {mosi_sync[0], mosi};
    end
  end

  // Tahap 2: Edge Detection
  logic sclk_rise, sclk_fall, cs_fall, cs_active;
  
  assign sclk_rise = (sclk_sync[2:1] == 2'b01);
  assign sclk_fall = (sclk_sync[2:1] == 2'b10);
  assign cs_fall   = (cs_n_sync[2:1] == 2'b10);
  assign cs_active = ~cs_n_sync[1];

  // Tahap 3: Shift Registers dan Pengontrol Transmisi
  logic [2:0] bit_cnt;
  logic [7:0] rx_reg;
  logic [7:0] tx_reg;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      bit_cnt  <= 3'd0;
      rx_reg   <= 8'd0;
      rx_data  <= 8'd0;
      rx_valid <= 1'b0;
      tx_reg   <= 8'd0;
      miso     <= 1'b0;
      tx_ready <= 1'b0;
    end else begin
      rx_valid <= 1'b0; // Default: mati (hanya berupa pulsa 1 siklus clk)
      tx_ready <= 1'b0; // Default: mati

      if (cs_fall) begin
        // Saat CS turun, reset counter dan siapkan data TX pertama
        bit_cnt <= 3'd0;
        tx_reg  <= tx_data;
        miso    <= tx_data[7]; // SPI Mode 0: Data pertama langsung keluar saat CS turun
      end else if (cs_active) begin
        
        // Sampling data masuk dari MOSI pada Rising Edge SCLK
        if (sclk_rise) begin
          rx_reg  <= {rx_reg[6:0], mosi_sync[1]};
          bit_cnt <= bit_cnt + 3'd1;
          
          // Jika ini adalah bit ke-8 (terakhir dalam satu byte)
          if (bit_cnt == 3'd7) begin
            rx_data  <= {rx_reg[6:0], mosi_sync[1]};
            rx_valid <= 1'b1; // Beri tahu controller bahwa data valid
            tx_ready <= 1'b1; // Minta controller menyiapkan data balasan berikutnya
          end
        end 
        
        // Menggeser data keluar ke MISO pada Falling Edge SCLK
        else if (sclk_fall) begin
          if (bit_cnt == 3'd0) begin
            // Tepat setelah satu byte utuh selesai diproses, muat data TX baru
            tx_reg <= tx_data;
            miso   <= tx_data[7];
          end else begin
            // Sedang di tengah transmisi byte, geser sisa bitnya
            tx_reg <= {tx_reg[6:0], 1'b0};
            miso   <= tx_reg[6];
          end
        end
        
      end
    end
  end

endmodule