`ifndef INCL_CONFIG
`define INCL_CONFIG

// Licensed under the Creative Commons 1.0 Universal License (CC0), see LICENSE
// for details.
//
// Author: Robert Primas (rprimas 'at' proton.me, https://rprimas.github.io)
//
// Configuration of the Ascon core.

// UROL: Number of Ascon-p rounds per clock cycle.
// CCW: Width of the data buses.
`ifdef V1
localparam logic [3:0] UROL = 1;
localparam unsigned CCW = 32;
`elsif V2
localparam logic [3:0] UROL = 2;
localparam unsigned CCW = 32;
`elsif V3
localparam logic [3:0] UROL = 4;
localparam unsigned CCW = 32;
`elsif V4
localparam logic [3:0] UROL = 1;
localparam unsigned CCW = 64;
`elsif V5
localparam logic [3:0] UROL = 2;
localparam unsigned CCW = 64;
`elsif V6
localparam logic [3:0] UROL = 4;
localparam unsigned CCW = 64;
`endif
`ifndef V1
`ifndef V2
`ifndef V3
`ifndef V4
`ifndef V5
`ifndef V6
localparam logic [3:0] UROL = 1;
localparam unsigned CCW = 32;
`endif
`endif
`endif
`endif
`endif
`endif

localparam logic [3:0] W64 = CCW == 32 ? 4'd2 : 4'd1;   // Number of words in 64 bits
localparam logic [3:0] W128 = CCW == 32 ? 4'd4 : 4'd2;  // Number of words in 128 bits
localparam logic [3:0] W192 = CCW == 32 ? 4'd6 : 4'd3;  // Number of words in 192 bits

// Ascon parameters
localparam unsigned LANES = 5;
localparam unsigned ROUNDS_A = 12;
localparam unsigned ROUNDS_B = 8;

localparam logic [63:0] IV_AEAD = 64'h00001000808c0001;  // Ascon-AEAD128

// Ascon modes (Hanya menyisakan AEAD)
typedef enum logic [3:0] {
  M_INVALID     = 4'd0,
  M_AEAD128_ENC = 4'd1,
  M_AEAD128_DEC = 4'd2
} mode_t;

// Interface data types
typedef enum logic [3:0] {
  D_INVALID = 4'd0,
  D_NONCE   = 4'd1,
  D_AD      = 4'd2,
  D_MSG     = 4'd3,
  D_TAG     = 4'd4
} data_t;

`endif  // INCL_CONFIG