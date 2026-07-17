`timescale 1ns/1ps

module spi_controller (
  input  logic        clk,
  input  logic        rst,
  input  logic        cs_n,

  input  logic [7:0]  rx_data,
  input  logic        rx_valid,
  output logic [7:0]  tx_data,
  input  logic        tx_ready,

  output logic [31:0] key,
  output logic        key_valid,
  input  logic        key_ready,

  output logic [31:0] bdi,
  output logic [3:0]  bdi_valid,
  input  logic        bdi_ready,
  output logic [3:0]  bdi_type,
  output logic        bdi_eot,
  output logic        bdi_eoi,
  output logic [3:0]  mode,

  input  logic [31:0] bdo,
  input  logic        bdo_valid,
  output logic        bdo_ready,
  input  logic [3:0]  bdo_type,
  input  logic        bdo_eot,

  input  logic        auth,
  input  logic        auth_valid
);

  // Ditambahkan state S_LOAD_AD
  typedef enum logic [3:0] {
    S_IDLE, S_GET_CMD, S_LOAD_KEY, S_LOAD_NONCE, S_LOAD_AD, S_LOAD_MSG, S_READ_DATA
  } state_t;
  state_t state, next_state;

  logic [31:0] word_buf;
  logic [1:0]  byte_cnt;
  logic [2:0]  word_cnt;

  logic cs_n_q;
  logic cs_rise;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) cs_n_q <= 1'b1;
    else cs_n_q <= cs_n;
  end
  assign cs_rise = (cs_n == 1'b1 && cs_n_q == 1'b0);

  always_ff @(posedge clk or posedge rst) begin
    if (rst) state <= S_IDLE;
    else if (cs_rise) state <= S_IDLE;
    else state <= next_state;
  end

  always_comb begin
    next_state = state;
    case (state)
      S_IDLE: if (cs_n == 1'b0) next_state = S_GET_CMD;
      S_GET_CMD: begin
        if (rx_valid) begin
          case (rx_data)
            8'h10: next_state = S_LOAD_KEY;
            8'h20: next_state = S_LOAD_NONCE;
            8'h30: next_state = S_LOAD_AD;   // <- CMD 30 sudah ditambahkan!
            8'h40: next_state = S_LOAD_MSG;
            8'h60: next_state = S_READ_DATA;
            default: next_state = S_IDLE;
          endcase
        end
      end
      default: next_state = state;
    endcase
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      byte_cnt  <= 0;
      word_cnt  <= 0;
      key_valid <= 0;
      bdi_valid <= 0;
      bdi_type  <= 0;
      bdi_eot   <= 0;
      bdi_eoi   <= 0;
      key       <= 0;
      bdi       <= 0;
    end else begin
      if (key_valid && key_ready) key_valid <= 0;
      if (bdi_valid != 0 && bdi_ready) bdi_valid <= 0;

      if (cs_rise) begin
        byte_cnt <= 0;
        word_cnt <= 0;
      // Jangan lupa izinkan S_LOAD_AD menangkap data juga
      end else if ((state == S_LOAD_KEY || state == S_LOAD_NONCE || state == S_LOAD_AD || state == S_LOAD_MSG) && rx_valid) begin
        
        if (byte_cnt == 0) word_buf[31:24] <= rx_data;
        if (byte_cnt == 1) word_buf[23:16] <= rx_data;
        if (byte_cnt == 2) word_buf[15:8]  <= rx_data;
        if (byte_cnt == 3) begin
          
          key <= {word_buf[31:8], rx_data};
          bdi <= {word_buf[31:8], rx_data};
          
          if (state == S_LOAD_KEY) begin
             key_valid <= 1;
          end else if (state == S_LOAD_NONCE) begin
             bdi_valid <= 4'b1111;
             bdi_type  <= 4'd1;
             bdi_eot   <= (word_cnt == 3) ? 1'b1 : 1'b0;
             bdi_eoi   <= 0; 
          end else if (state == S_LOAD_AD) begin // <- Logika pengiriman AD
             bdi_valid <= 4'b1111;
             bdi_type  <= 4'd2;
             bdi_eot   <= (word_cnt == 3) ? 1'b1 : 1'b0;
             bdi_eoi   <= 0; 
          end else if (state == S_LOAD_MSG) begin
             bdi_valid <= 4'b1111;
             bdi_type  <= 4'd3;
             bdi_eot   <= (word_cnt == 3) ? 1'b1 : 1'b0;
             bdi_eoi   <= (word_cnt == 3) ? 1'b1 : 1'b0; 
          end
          word_cnt <= word_cnt + 1;
        end
        byte_cnt <= byte_cnt + 1;
      end
    end
  end

  assign mode = 4'd1; 
  assign bdo_ready = 1'b1; 
  assign tx_data = bdo[31:24];

endmodule