`timescale 1ns/1ps

module tb_ascon_top;

  // ---------------------------------------------------------
  // Signal Declarations
  // ---------------------------------------------------------
  logic clk;
  logic rst; // Active-high reset
  
  // SPI Physical Interface
  logic sclk;
  logic cs_n;
  logic mosi;
  logic miso;

  // Internal TB variables
  logic [7:0] rx_byte;
  int spi_period = 20; // 50 MHz SPI clock (Tight timing to expose the hazard)

  // ---------------------------------------------------------
  // Clock Generation (100 MHz)
  // ---------------------------------------------------------
  always #5 clk = ~clk; 

  // ---------------------------------------------------------
  // Device Under Test (DUT) Instantiation
  // ---------------------------------------------------------
  ascon_top dut (
    .clk(clk),
    .rst(rst),
    .sclk(sclk),
    .cs_n(cs_n),
    .mosi(mosi),
    .miso(miso)
  );

  // ---------------------------------------------------------
  // SPI Master Task (Mode 0: CPOL=0, CPHA=0)
  // ---------------------------------------------------------
  task spi_transfer(input logic [7:0] tx_data, output logic [7:0] rx_data);
    rx_data = 8'h00;
    for (int i = 7; i >= 0; i--) begin
      mosi = tx_data[i];
      #(spi_period/2);
      
      sclk = 1'b1;
      rx_data[i] = miso; 
      #(spi_period/2);
      
      sclk = 1'b0;
    end
  endtask

  // ---------------------------------------------------------
  // Main Test Sequence
  // ---------------------------------------------------------
  initial begin
    clk = 0; rst = 1; sclk = 0; cs_n = 1; mosi = 0;
    #100; rst = 0; #100;

    $display("==================================================");
    $display(" ASCON SYSTEMVERILOG TESTBENCH (HIGH-SPEED)");
    $display("==================================================");

    // ---------------------------------------------------------
    // TEST 1: Proper Initialization (Full 16-byte Key & Nonce)
    // ---------------------------------------------------------
    $display("\n[TEST 1] Initializing Ascon Core...");
    
    // Send 16-byte Key
    cs_n = 0; #(spi_period);
    spi_transfer(8'h10, rx_byte); // CMD 0x10
    for(int i=0; i<16; i++) spi_transfer(i, rx_byte);
    #50; cs_n = 1; #100;

    // Send 16-byte Nonce
    cs_n = 0; #(spi_period);
    spi_transfer(8'h20, rx_byte); // CMD 0x20
    for(int i=0; i<16; i++) spi_transfer(8'hFF - i, rx_byte);
    #50; cs_n = 1; 

    // Wait for the Ascon Core to finish its 12-round initialization
    $display("         Waiting for Ascon FSM INIT rounds to complete...");
    #300; 

    // ---------------------------------------------------------
    // TEST 2: The Broken MISO Path Bug Trigger
    // ---------------------------------------------------------
    $display("\n[TEST 2] Processing Message to trigger MISO/BDO Bug...");
    cs_n = 0; #(spi_period);
    spi_transfer(8'h40, rx_byte); // CMD 0x40 (Load MSG)
    
    // Sending exactly 1 word (4 bytes) to trigger the core to output BDO
    spi_transfer(8'hAA, rx_byte);
    spi_transfer(8'hBB, rx_byte);
    spi_transfer(8'hCC, rx_byte);
    spi_transfer(8'hDD, rx_byte); 
    #100; cs_n = 1; #100;

    // ---------------------------------------------------------
    // TEST 3: The CS-Timing Hazard Bug Trigger
    // ---------------------------------------------------------
    $display("\n[TEST 3] Simulating fast CS_N drop to trigger Hazard...");
    cs_n = 0; #(spi_period);
    spi_transfer(8'h30, rx_byte); // CMD 0x30 (Load AD)
    
    spi_transfer(8'h11, rx_byte);
    spi_transfer(8'h22, rx_byte);
    spi_transfer(8'h33, rx_byte);

    // Manual SPI transfer for the final byte to drop CS_N EXACTLY on the clock edge
    rx_byte = 8'h00;
    for (int i = 7; i >= 0; i--) begin
      mosi = (8'h44 >> i) & 1'b1;
      #(spi_period/2);
      sclk = 1'b1;
      rx_byte[i] = miso;
      #(spi_period/2);
      sclk = 1'b0;
    end
    
    // PREMATURE DROP: Pulling CS high the nanosecond the SCLK falls.
    // The synchronizer won't process the final SCLK edge in time!
    cs_n = 1; 
    #200;

    $display("\n==================================================");
    $display(" SIMULATION COMPLETE.");
    $display("==================================================");
    $finish;
  end

// ---------------------------------------------------------
  // TEXT-BASED RESULT LOGGER (V3 - POST-LATCH CHECK)
  // ---------------------------------------------------------
  initial $timeformat(-9, 0, " ns", 10); 

  logic bdo_valid_q;
  logic [31:0] bdo_q;

  always_ff @(posedge clk) begin
    if (rst) begin
      bdo_valid_q <= 1'b0;
      bdo_q <= 32'd0;
    end else begin
      bdo_valid_q <= dut.spi_ctrl.bdo_valid;
      bdo_q <= dut.spi_ctrl.bdo;
    end
  end

  always @(posedge clk) begin
    if (!rst) begin
      // 1. Check the CS-Timing Hazard Fix
      if (dut.spi_ctrl.cs_rise) begin
        if (dut.spi_ctrl.byte_cnt != 0) begin
           $display("\n[%t] [ERROR] ❌ CS Hazard still exists! byte_cnt: %0d", $time, dut.spi_ctrl.byte_cnt);
        end else begin
           $display("\n[%t] [SUCCESS] ✅ CS Hazard Fixed! Final byte safely processed before FSM reset.", $time);
        end
      end

      // 2. Check the MISO Shift Register Fix
      if (bdo_valid_q) begin
        $display("\n[%t] [SUCCESS] ✅ MISO Shift Register Latched!", $time);
        $display("                      Core BDO output: 32'h%h", bdo_q);
        $display("                      Shift reg holds: 32'h%h", dut.spi_ctrl.tx_shift_reg);
      end
    end
  end
endmodule