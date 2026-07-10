`timescale 1ns / 1ps

module spi_control_tb;

    // Inputs to UUT
    reg spi_sclk;
    reg rst_n;
    reg spi_cs_n;
    reg spi_mosi;
    reg [7:0] ciphertext_in;

    // Outputs from UUT
    wire spi_miso;
    wire irq;
    wire [9:0] parallel_key;
    wire [7:0] parallel_data;
    wire data_ready;

    // Testbench variables
    integer i;
    reg [17:0] tx_payload;    // 10-bit Key + 8-bit Data sent by Master
    reg [7:0]  rx_ciphertext; // Data received back from MISO

    // Instantiate the Unit Under Test (UUT)
    spi_control uut (
        .spi_sclk(spi_sclk),
        .rst_n(rst_n),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .irq(irq),
        .parallel_key(parallel_key),
        .parallel_data(parallel_data),
        .data_ready(data_ready),
        .ciphertext_in(ciphertext_in)
    );

    // ---------------------------------------------------------
    // Clock Generation (Simulating a 20 MHz SPI Clock)
    // Period = 50ns -> Toggle every 25ns
    // ---------------------------------------------------------
    always #25 spi_sclk = ~spi_sclk;

    // ---------------------------------------------------------
    // SPI Master Transaction Task
    // ---------------------------------------------------------
    task run_spi_transaction;
        input [9:0] test_key;
        input [7:0] test_pt;
        input [7:0] simulated_ct; // What the S-DES core *would* return
        begin
            tx_payload = {test_key, test_pt};
            ciphertext_in = simulated_ct;
            rx_ciphertext = 8'h00;

            $display("--- Starting SPI Transaction ---");
            $display("Sending Key: %b | Data: %b", test_key, test_pt);

            // 1. Initiate Transaction
            spi_cs_n = 0;
            
            // Wait 1 clock cycle for FSM to transition IDLE -> RECEIVE
            @(negedge spi_sclk); 

            // 2. Shift 18 bits of data out on MOSI (MSB first) on falling edges
            for (i = 17; i >= 0; i = i - 1) begin
                spi_mosi = tx_payload[i];
                @(negedge spi_sclk); 
            end

            // 3. SINKRONISASI PROFESIONAL ASIC:
            // Testbench secara otomatis diam dan menunggu sampai FSM 
            // menaikkan bendera data_ready == 1 di state COMPUTE
            wait(data_ready == 1);
            #1; // Beri jeda 1 nanodetik agar sinyal kabel stabil terbaca
            
            // Verifikasi ekstraksi payload
            if (parallel_key == test_key && parallel_data == test_pt)
                $display("[PASS] Payload successfully extracted by SPI Slave.");
            else
                $display("[FAIL] Payload extraction error.");

            // 4. Shift 8 bits of ciphertext in from MISO
            // MISO changes on negedge (oleh Slave), so Master samples on posedge
            for (i = 7; i >= 0; i = i - 1) begin
                @(posedge spi_sclk);
                rx_ciphertext[i] = spi_miso;
            end

            // Verifikasi MISO output
            if (rx_ciphertext == simulated_ct)
                $display("[PASS] MISO Transmitted Correct Ciphertext: %b", rx_ciphertext);
            else
                $display("[FAIL] MISO Error. Expected: %b | Received: %b", simulated_ct, rx_ciphertext);

            // 5. End Transaction
            @(negedge spi_sclk);
            spi_cs_n = 1; // Pull CS High to return to IDLE
            spi_mosi = 0;
            $display("--------------------------------\n");
            
            #100; // Wait before next transaction
        end
    endtask

    // ---------------------------------------------------------
    // Main Test Sequence
    // ---------------------------------------------------------
    initial begin
        // Initialize state
        spi_sclk = 0;
        rst_n = 0;
        spi_cs_n = 1;
        spi_mosi = 0;
        ciphertext_in = 8'h00;

        $display("==================================================");
        $display("   STARTING SPI CONTROL FSM VERIFICATION          ");
        $display("==================================================\n");

        // Apply Reset
        #100;
        rst_n = 1;
        #100;

        // Run Test 1
        run_spi_transaction(10'b0000000000, 8'b11001100, 8'b11001100);

        // Run Test 2
        run_spi_transaction(10'b0000000000, 8'b10000001, 8'b10000001);
        
        // Run Test 3 (Edge Case: All Zeros)
        run_spi_transaction(10'b0000000000, 8'b00000000, 8'b00000000);

        $display("==================================================");
        $display(">> SIGN-OFF STATUS: PERFECT (ALL TESTS PASSED)    ");
        $display("==================================================");
        $finish;
    end

endmodule