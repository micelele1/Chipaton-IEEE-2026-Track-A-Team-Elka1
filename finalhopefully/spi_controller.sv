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

  typedef enum logic [3:0] {
    S_IDLE, S_GET_CMD, S_SET_MODE, S_LOAD_KEY, S_LOAD_NONCE, S_LOAD_AD,
    S_LOAD_MSG, S_LOAD_TAG, S_READ_DATA, S_READ_AUTH
  } state_t;
  state_t state, next_state;

  logic [31:0] word_buf;
  logic [1:0]  byte_cnt;
  logic [2:0]  word_cnt;

  // NEW: mode register. Default = M_AEAD128_ENC (4'd1) supaya kompatibel
  // dengan host lama yang belum pernah kirim SET_MODE.
  logic [3:0]  mode_reg;

  // ---------------------------------------------------------
  // HAZARD FIX: Synchronize CS_N and add 1-cycle pipeline match
  // ---------------------------------------------------------
  logic [2:0] cs_n_sync;
  logic       cs_rise_comb;
  logic       cs_rise;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) cs_n_sync <= 3'b111;
    else     cs_n_sync <= {cs_n_sync[1:0], cs_n};
  end
  
  // Triggers when the spi_slave considers the transaction over
  assign cs_rise_comb = (cs_n_sync[2:1] == 2'b01);

  // Delay by exactly 1 clock cycle to match the rx_valid flip-flop in spi_slave
  always_ff @(posedge clk or posedge rst) begin
    if (rst) cs_rise <= 1'b0;
    else     cs_rise <= cs_rise_comb;
  end

  // ---------------------------------------------------------
  // MISO BDO ROUTING FIX: 32-bit Shift Register
  // ---------------------------------------------------------
  logic [31:0] tx_shift_reg;
  logic [1:0]  tx_byte_cnt;
  logic        tx_busy;

  assign bdo_ready = ~tx_busy;

  // NEW: byte laporan status auth, dibaca lewat command 0x70 (READ_AUTH)
  logic [7:0] auth_byte;
  assign auth_byte = {6'b0, auth_valid, auth};

  assign tx_data = (state == S_READ_AUTH) ? auth_byte : tx_shift_reg[31:24];

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      tx_shift_reg <= 32'd0;
      tx_byte_cnt  <= 2'd0;
      tx_busy      <= 1'b0;
    end else begin
      if (bdo_valid && bdo_ready) begin
        tx_shift_reg <= bdo;
        tx_busy      <= 1'b1;
        tx_byte_cnt  <= 2'd0;
      end else if (tx_busy && tx_ready && (state == S_READ_DATA || state == S_LOAD_MSG)) begin
        tx_shift_reg <= {tx_shift_reg[23:0], 8'h00};
        if (tx_byte_cnt == 2'd3) begin
          tx_busy <= 1'b0; 
        end else begin
          tx_byte_cnt <= tx_byte_cnt + 2'd1;
        end
      end
    end
  end

  // ---------------------------------------------------------
  // State Machine & Core Interaction Logic
  // ---------------------------------------------------------
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
            8'h30: next_state = S_LOAD_AD;   
            8'h40: next_state = S_LOAD_MSG;
            8'h45: next_state = S_LOAD_TAG;   // NEW: dekripsi - load tag 128-bit
            8'h50: next_state = S_SET_MODE;   // NEW: set mode ENC/DEC
            8'h60: next_state = S_READ_DATA;
            8'h70: next_state = S_READ_AUTH;  // NEW: baca status auth
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
      mode_reg  <= 4'd0;  // default: M_AEAD128_ENC, backward-compatible
    end else begin
      if (key_valid && key_ready) key_valid <= 0;
      if (bdi_valid != 0 && bdi_ready) bdi_valid <= 0;

      // NEW: tangkap payload byte SET_MODE (0x01=ENC, 0x02=DEC)
      if (state == S_SET_MODE && rx_valid) begin
        mode_reg <= rx_data[3:0];
      end

      if (cs_rise) begin
        byte_cnt <= 0;
        word_cnt <= 0;
      end else if ((state == S_LOAD_KEY || state == S_LOAD_NONCE || state == S_LOAD_AD
                    || state == S_LOAD_MSG || state == S_LOAD_TAG) && rx_valid) begin
        
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
          end else if (state == S_LOAD_AD) begin 
             bdi_valid <= 4'b1111;
             bdi_type  <= 4'd2;
             bdi_eot   <= (word_cnt == 3) ? 1'b1 : 1'b0;
             bdi_eoi   <= 0; 
          end else if (state == S_LOAD_MSG) begin
             bdi_valid <= 4'b1111;
             bdi_type  <= 4'd3;
             bdi_eot   <= (word_cnt == 3) ? 1'b1 : 1'b0;
             bdi_eoi   <= (word_cnt == 3) ? 1'b1 : 1'b0; 
          end else if (state == S_LOAD_TAG) begin
             // NEW: 128-bit tag masuk sebagai D_TAG, dipakai ascon_core
             // saat fsm_q == VER_TAG (hanya relevan untuk mode dekripsi)
             bdi_valid <= 4'b1111;
             bdi_type  <= 4'd4;  // D_TAG
             bdi_eot   <= (word_cnt == 3) ? 1'b1 : 1'b0;
             bdi_eoi   <= 0;
          end
          word_cnt <= word_cnt + 1;
        end
        byte_cnt <= byte_cnt + 1;
      end
    end
  end

  assign mode = mode_reg;  // was hardcoded 4'd1 (ENC-only)

endmodule