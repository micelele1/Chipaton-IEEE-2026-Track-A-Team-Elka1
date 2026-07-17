`timescale 1ns/1ps

module ascon_top (
  input logic clk,
  input logic rst,
  
  // Interface SPI dari luar chip
  input  logic sclk,
  input  logic cs_n,
  input  logic mosi,
  output logic miso
);

  // Kabel penghubung antara SPI Slave dan SPI Controller
  logic [7:0] rx_data;
  logic       rx_valid;
  logic [7:0] tx_data;
  logic       tx_ready;

  // Kabel penghubung antara SPI Controller dan Ascon Core
  logic [31:0] key;
  logic        key_valid;
  logic        key_ready;
  logic [31:0] bdi;
  logic [3:0]  bdi_valid;
  logic        bdi_ready;
  logic [3:0]  bdi_type;
  logic        bdi_eot;
  logic        bdi_eoi;
  logic [3:0]  mode;
  logic [31:0] bdo;
  logic        bdo_valid;
  logic        bdo_ready;
  logic [3:0]  bdo_type;
  logic        bdo_eot;
  logic        bdo_eoo;
  logic        auth;
  logic        auth_valid;

  // 1. Instansiasi SPI Physical Layer
  spi_slave spi_phy (
    .clk(clk),
    .rst(rst),
    .sclk(sclk),
    .cs_n(cs_n),
    .mosi(mosi),
    .miso(miso),
    .rx_data(rx_data),
    .rx_valid(rx_valid),
    .tx_data(tx_data),
    .tx_ready(tx_ready)
  );

  // 2. Instansiasi SPI Protocol Controller
  spi_controller spi_ctrl (
    .clk(clk),
    .rst(rst),
    .cs_n(cs_n),
    .rx_data(rx_data),
    .rx_valid(rx_valid),
    .tx_data(tx_data),
    .tx_ready(tx_ready),
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
    .auth(auth),
    .auth_valid(auth_valid)
  );

  // 3. Instansiasi Ascon Core (Bisa diganti dengan postprocessor_rup jika diperlukan)
  ascon_core core_inst (
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

endmodule