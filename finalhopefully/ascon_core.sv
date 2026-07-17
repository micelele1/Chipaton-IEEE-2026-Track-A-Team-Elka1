`ifndef INCL_ASCON_CORE
`define INCL_ASCON_CORE

// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Implementation of the Ascon core.

`include "config.sv"
`include "functions.sv"
`include "asconp.sv"
`include "register.sv"

module ascon_core (
    input  logic              clk,
    input  logic              rst,
    input  logic  [  CCW-1:0] key,
    input  logic              key_valid,
    output logic              key_ready,
    input  logic  [  CCW-1:0] bdi,
    input  logic  [CCW/8-1:0] bdi_valid,
    output logic              bdi_ready,
    input  logic [3:0] bdi_type,
    input  logic              bdi_eot,
    input  logic              bdi_eoi,
    input  logic [3:0] mode,
    output logic  [  CCW-1:0] bdo,
    output logic              bdo_valid,
    input  logic              bdo_ready,
    output logic [3:0] bdo_type,
    output logic              bdo_eot,
    input  logic              bdo_eoo,
    output logic              auth,
    output logic              auth_valid
);

  // FSM states
  typedef enum logic [4:0] {
    INVALID  = 5'd0,
    IDLE     = 5'd1,
    LD_KEY   = 5'd2,
    LD_NPUB  = 5'd3,
    INIT     = 5'd4,
    KADD_2   = 5'd5,
    ABS_AD   = 5'd6,
    PAD_AD   = 5'd7,
    PRO_AD   = 5'd8,
    DOM_SEP  = 5'd9,
    ABS_MSG  = 5'd10,
    PAD_MSG  = 5'd11,
    PRO_MSG  = 5'd12,
    KADD_3   = 5'd13,
    FINAL    = 5'd14,
    KADD_4   = 5'd15,
    SQZ_TAG  = 5'd16,
    VER_TAG  = 5'd17
  } fsm_t;

  // Register signals
  logic [W128-1:0][CCW-1:0] key_d, key_q;
  logic [LANES-1:0][W64-1:0][CCW-1:0] state_d, state_q;
  logic [3:0] round_cnt_d, word_cnt_d;
  logic [3:0] round_cnt_q, word_cnt_q;
  fsm_t fsm_d, fsm_q;
  mode_t mode_d, mode_q;
  logic auth_d, auth_intern_d, auth_valid_d;
  logic auth_q, auth_intern_q, auth_valid_q;
  logic ad_eot_d, ad_pad_d, msg_pad_d, eoi_d;
  logic ad_eot_q, ad_pad_q, msg_pad_q, eoi_q;

  // Registers
  register #('d128) reg_key_i (
    .clk(clk), .rst(rst), .data_d(key_d), .data_q(key_q)
  );

  register #('d320) reg_state_i (
    .clk(clk), .rst(rst), .data_d(state_d), .data_q(state_q)
  );

  register #('d8)  reg_cnt_i (
    .clk(clk), .rst(rst),
    .data_d({round_cnt_d, word_cnt_d}),
    .data_q({round_cnt_q, word_cnt_q})
  );

  logic [4:0] fsm_q_logic;
register #('d5, IDLE) reg_fsm_i (
.clk(clk), .rst(rst), .data_d(5'(fsm_d)), .data_q(fsm_q_logic)
);
assign fsm_q = fsm_t'(fsm_q_logic);

  register #('d11) reg_flags_i (
    .clk(clk), .rst(rst),
    .data_d({auth_d, auth_intern_d, auth_valid_d, ad_eot_d, ad_pad_d, msg_pad_d, eoi_d, mode_d}),
    .data_q({auth_q, auth_intern_q, auth_valid_q, ad_eot_q, ad_pad_q, msg_pad_q, eoi_q, mode_q})
  );

  // Event signals
  logic last_abs_blk;
  logic add_ad_pad, add_msg_pad;

  logic mode_enc_dec;
  assign mode_enc_dec  = (mode_q == M_AEAD128_ENC) || (mode_q == M_AEAD128_DEC);

  logic idle_done, ld_key, ld_key_done, ld_npub, ld_npub_done, init, init_done, kadd_2_done;
  assign idle_done    = (fsm_q == IDLE) && (mode > 4'd0);
  assign ld_key       = (fsm_q == LD_KEY) && key_valid && key_ready;
  assign ld_key_done  = ld_key && (word_cnt_q == (W128 - 1));
  assign ld_npub      = (fsm_q == LD_NPUB) && (bdi_type == D_NONCE) && (bdi_valid > 'd0) && bdi_ready;
  assign ld_npub_done = ld_npub && (word_cnt_q == (W128 - 1));
  assign init         = (fsm_q == INIT);
  assign init_done    = init && (round_cnt_q == UROL);
  assign kadd_2_done  = (fsm_q == KADD_2) && (eoi_q || (bdi_valid > 'd0));

  logic abs_ad, abs_ad_done, pro_ad, pro_ad_done;
  assign abs_ad      = (fsm_q == ABS_AD) && (bdi_type == D_AD) && (bdi_valid > 'd0) && bdi_ready;
  assign abs_ad_done = abs_ad && (last_abs_blk || bdi_eot);
  assign pro_ad      = (fsm_q == PRO_AD);
  assign pro_ad_done = pro_ad && (round_cnt_q == UROL);

  logic dom_sep_done;
  assign dom_sep_done = (fsm_q == DOM_SEP);

  logic abs_msg_part, abs_msg, abs_msg_done, pro_msg, pro_msg_done;
  assign abs_msg_part = (fsm_q == ABS_MSG) && (bdi_type == D_MSG) && (bdi_valid != 'd0) && bdi_ready;
  assign abs_msg      = abs_msg_part && ((bdo_valid && bdo_ready) || !mode_enc_dec);
  assign abs_msg_done = abs_msg && (last_abs_blk || bdi_eot);
  assign pro_msg      = (fsm_q == PRO_MSG);
  assign pro_msg_done = (round_cnt_q == UROL) && pro_msg;

  logic kadd_3_done, fin, fin_done, kadd_4_done;
  assign kadd_3_done = (fsm_q == KADD_3);
  assign fin         = (fsm_q == FINAL);
  assign fin_done    = (round_cnt_q == UROL) && fin;
  assign kadd_4_done = (fsm_q == KADD_4);

  logic sqz_tag, sqz_tag_done, ver_tag, ver_tag_done;
  assign sqz_tag        = (fsm_q == SQZ_TAG) && bdo_valid && bdo_ready;
  assign sqz_tag_done   = (word_cnt_q == (W128 - 1)) && sqz_tag;
  assign ver_tag        = (fsm_q == VER_TAG) && (bdi_type == D_TAG) && bdi_ready && (bdi_valid != 'd0);
  assign ver_tag_done   = (word_cnt_q == (W128 - 1)) && ver_tag;

  assign last_abs_blk =
    (abs_ad  && mode_enc_dec        && (word_cnt_q == (W128 - 1))) ||
    (abs_msg && mode_enc_dec        && (word_cnt_q == (W128 - 1)));

  assign add_ad_pad = (fsm_q == PAD_AD) || (abs_ad && (bdi_valid != '1));
  assign add_msg_pad = (fsm_q == PAD_MSG) ||
    (dom_sep_done && eoi_q) || (abs_msg && (bdi_valid != '1));

  // Utility signals
  logic [3:0] state_idx, lane_idx, word_idx;
  logic [CCW-1:0] state_slice_nx, state_slice, bdi_pad;

  assign word_idx = (CCW == 64) ? 'd0 : state_idx % 2;
  assign lane_idx = (CCW == 64) ? state_idx : state_idx / 2;
  assign state_slice = state_q[int'(lane_idx)][int'(word_idx)];

  logic [LANES-1:0][W64-1:0][CCW-1:0] asconp_o;

  // Instantiation of Ascon-p permutation
  asconp asconp_i (
    .round_cnt(round_cnt_q),
    .x0_i(state_q[0]),
    .x1_i(state_q[1]),
    .x2_i(state_q[2]),
    .x3_i(state_q[3]),
    .x4_i(state_q[4]),
    .x0_o(asconp_o[0]),
    .x1_o(asconp_o[1]),
    .x2_o(asconp_o[2]),
    .x3_o(asconp_o[3]),
    .x4_o(asconp_o[4])
  );

  /////////////////////
  // Control Signals //
  /////////////////////

  always_comb begin
    state_slice_nx = 'd0;
    state_idx      = 'd0;
    key_ready      = 'd0;
    bdi_ready      = 'd0;
    bdo            = 'd0;
    bdo_valid      = 'd0;
    bdo_type       = D_INVALID;
    bdo_eot        = 'd0;
    bdi_pad        = 'd0;
    auth           = auth_q;
    auth_valid     = auth_valid_q;

    unique case (fsm_q)
      LD_KEY:  key_ready = 'd1;
      LD_NPUB: begin
        state_idx = word_cnt_q + W192;
        bdi_ready = 'd1;
        state_slice_nx  = bdi;
      end
      ABS_AD: begin
        state_idx = word_cnt_q;
        bdi_ready = 'd1;
        bdi_pad   = pad(bdi, bdi_valid);
        state_slice_nx  = state_slice ^ bdi_pad;
      end
      PAD_AD, PAD_MSG: begin
        state_idx = word_cnt_q;
      end
      ABS_MSG: begin
        state_idx = word_cnt_q;
        if (mode_q == M_AEAD128_ENC) begin
          bdi_pad = pad(bdi, bdi_valid);
          state_slice_nx = state_slice ^ bdi_pad;
          bdo = mask(state_slice_nx, bdi_valid);
        end else if (mode_q == M_AEAD128_DEC) begin
          bdi_pad = pad2(bdi, state_slice, bdi_valid);
          state_slice_nx = bdi_pad;
          bdo = mask(state_slice ^ state_slice_nx, bdi_valid);
        end
        bdi_ready = mode_enc_dec ? bdo_ready : 'd1;
        bdo_valid = (mode_enc_dec && (bdi_valid != 'd0)) ? 'd1 : 'd0;
        bdo_type  = mode_enc_dec ? D_MSG : D_INVALID;
        bdo_eot   = mode_enc_dec ? bdi_eot : 'd0;
      end
      SQZ_TAG: begin
        state_idx = word_cnt_q + W192;
        bdo       = state_slice;
        bdo_valid = 'd1;
        bdo_type  = D_TAG;
        bdo_eot   = word_cnt_q == (W128 - 1);
      end
      VER_TAG: begin
        state_idx = word_cnt_q + W192;
        bdi_ready = 'd1;
      end
      default: ;
    endcase
  end

  //////////////////////////
  // FSM Next State Logic //
  //////////////////////////

  always_comb begin
    fsm_d = fsm_q;

    // Initialize:
    if (idle_done) begin
        if (mode == M_AEAD128_ENC || mode == M_AEAD128_DEC)
            fsm_d = LD_KEY;
    end
    if (ld_key_done) fsm_d = LD_NPUB;
    if (ld_npub_done) fsm_d = INIT;

    if (init_done) begin
      if (mode_enc_dec) fsm_d = KADD_2;
    end

    if (kadd_2_done) begin
      if (eoi_q) fsm_d = DOM_SEP;
      else if (bdi_type == D_AD) fsm_d = ABS_AD;
      else if (bdi_type == D_MSG) fsm_d = DOM_SEP;
    end

    // Process:
    // - AEAD: associated data
    if (abs_ad_done) begin
      if (bdi_valid != '1) begin
        fsm_d = PRO_AD;
      end else begin
        if ((word_cnt_q != (W128 - 1)) && mode_enc_dec) fsm_d = PAD_AD;
        else fsm_d = PRO_AD;
      end
    end

    if (fsm_q == PAD_AD) fsm_d = PRO_AD;

    if (pro_ad_done) begin
      begin
        if (ad_eot_q == 0) begin
          fsm_d = ABS_AD;
        end else if (ad_pad_q == 0) begin
          fsm_d = PAD_AD;
        end else begin
          if (mode_enc_dec) fsm_d = DOM_SEP;
        end
      end
    end

    if (dom_sep_done) fsm_d = eoi_q ? KADD_3 : ABS_MSG;

    // Process:
    // - AEAD: plaintext or ciphertext
    if (abs_msg_done) begin
      if (bdi_valid != '1) begin
        fsm_d = KADD_3;
      end else begin
        if (mode_enc_dec && (word_cnt_q != (W128 - 1))) fsm_d = PAD_MSG;
        else fsm_d = PRO_MSG;
      end
    end

    if (fsm_q == PAD_MSG) begin
      fsm_d = KADD_3;
    end

    if (pro_msg_done) begin
      if (eoi_q == 0) begin
        fsm_d = ABS_MSG;
      end else if (msg_pad_q == 0) begin
        fsm_d = PAD_MSG;
      end
    end

    if (kadd_3_done) fsm_d = FINAL;

    if (fin_done) begin
      fsm_d = KADD_4;
    end

    // Finalize:
    // - AEAD: Squeeze or verify tag
    if (kadd_4_done) fsm_d = (mode_q == M_AEAD128_DEC) ? VER_TAG : SQZ_TAG;
    if (sqz_tag_done) fsm_d = IDLE;
    if (ver_tag_done) fsm_d = IDLE;
  end

  /////////////////////////
  // Ascon State Updates //
  /////////////////////////

  always_comb begin
    state_d = state_q;

    // Absorb padded input
    if (ld_npub || abs_ad || abs_msg) begin
      state_d[int'(lane_idx)][int'(word_idx)] = state_slice_nx;
    end

    // Absorb padding word
    if (fsm_q == PAD_AD || fsm_q == PAD_MSG) begin
      state_d[int'(lane_idx)][int'(word_idx)] = state_slice ^ 'd1;
    end

    // State initialization: AEAD
    // - "npub" is written to state during LOAD_NPUB
    if (ld_npub_done) begin
      state_d[0] = IV_AEAD[0+:64];
      state_d[1] = key_q[0+:W64];
      state_d[2] = key_q[W64+:W64];
    end

    // Perform Ascon-p permutation
    if (init || pro_ad || pro_msg || fin) begin
      state_d = asconp_o;
    end

    // Key addition 2/4
    if (kadd_2_done || kadd_4_done) begin
      state_d[3] = state_q[3] ^ key_q[0+:W64];
      state_d[4] = state_q[4] ^ key_q[W64+:W64];
    end

    // Domain separation
    if (dom_sep_done) begin
      state_d[4] = state_q[4] ^ 64'h8000000000000000;
      if (eoi_q) state_d[0] = state_q[0] ^ 'd1;  // Pad empty message
    end

    // Key addition 3
    if (kadd_3_done) begin
      state_d[2] = state_q[2] ^ key_q[0+:W64];
      state_d[3] = state_q[3] ^ key_q[W64+:W64];
    end
  end

  ///////////////////////
  // Ascon Key Updates //
  ///////////////////////

  always_comb begin
    key_d = key_q;
    if (ld_key) begin
      key_d[word_cnt_q[(64/CCW)-1:0]] = key;
    end
  end

  /////////////////////
  // Counter Updates //
  /////////////////////

  always_comb begin
    word_cnt_d = word_cnt_q;

    if (ld_key || ld_npub || abs_ad || abs_msg || sqz_tag || ver_tag) begin
      word_cnt_d = word_cnt_q + 'd1;
    end

    if (ld_key_done || ld_npub_done || sqz_tag_done || ver_tag_done) begin
      word_cnt_d = 'd0;
    end

    if (abs_ad_done || abs_msg_done) begin
      if ((fsm_d == PAD_AD) || (fsm_d == PAD_MSG)) begin
        word_cnt_d = word_cnt_q + 'd1;
      end else begin
        word_cnt_d = 'd0;
      end
    end

    if (fsm_q == PAD_AD) word_cnt_d = 'd0;
    if (fsm_q == PAD_MSG) word_cnt_d = 'd0;
  end

  always_comb begin
    round_cnt_d = round_cnt_q;
    unique case (fsm_d)
      INIT:    round_cnt_d = ROUNDS_A;
      PRO_AD:  round_cnt_d = ROUNDS_B;
      PRO_MSG: round_cnt_d = ROUNDS_B;
      FINAL:   round_cnt_d = ROUNDS_A;
      default:;
    endcase
    if (init || pro_ad || pro_msg || fin) round_cnt_d = round_cnt_q - UROL;
  end

  //////////////////
  // Flag Updates //
  //////////////////

  always_comb begin
    auth_d        = auth_q;
    auth_intern_d = auth_intern_q;
    auth_valid_d  = auth_valid_q;
    ad_eot_d      = ad_eot_q;
    ad_pad_d      = ad_pad_q;
    eoi_d         = eoi_q;
    msg_pad_d     = msg_pad_q;
    mode_d        = mode_q;

    if (idle_done) begin
      auth_d        = 'd0;
      auth_intern_d = 'd0;
      auth_valid_d  = 'd0;
      ad_eot_d      = 'd0;
      ad_pad_d      = 'd0;
      eoi_d         = bdi_eoi;
      msg_pad_d     = 'd0;
      mode_d = mode_t'(mode);
    end
    if (ld_npub_done) begin
      if (bdi_eoi) eoi_d = 'd1;
    end
    if (abs_ad_done) begin
      if (bdi_eot) ad_eot_d = 'd1;
      if (bdi_eoi) eoi_d    = 'd1;
    end
    if (add_ad_pad) ad_pad_d = 'd1;
    if (add_msg_pad) ad_pad_d = 'd1;
    if (abs_msg_done && bdi_eoi) eoi_d = 'd1;

    if (kadd_4_done && (mode_q == M_AEAD128_DEC)) auth_intern_d = 'd1;
    if (ver_tag) auth_intern_d = auth_intern_d && (bdi == state_slice);
    if (ver_tag_done) begin
      auth_d = auth_intern_q && auth_intern_d;
      auth_valid_d = 'd1;
    end
  end

  //////////////////////////////////////////////////
  // Debug Signals (can be removed for synthesis) //
  //////////////////////////////////////////////////

  logic [63:0] x0, x1, x2, x3, x4;
  assign x0 = state_q[0];
  assign x1 = state_q[1];
  assign x2 = state_q[2];
  assign x3 = state_q[3];
  assign x4 = state_q[4];

endmodule

`endif  // INCL_ASCON_CORE