`timescale 1ns/1ps

module tb_spi_slave;

    //------------------------------------------------------------
    // DUT Signals
    //------------------------------------------------------------
    logic clk;
    logic rst;

    logic sclk;
    logic cs_n;
    logic mosi;
    logic miso;

    logic [7:0] rx_data;
    logic rx_valid;

    logic [7:0] tx_data;
    logic tx_ready;

    //------------------------------------------------------------
    // DUT
    //------------------------------------------------------------
    spi_slave dut (
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

    //------------------------------------------------------------
    // Clock
    //------------------------------------------------------------
    always #5 clk = ~clk;

    //------------------------------------------------------------
    // Test statistics
    //------------------------------------------------------------
    integer pass = 0;
    integer fail = 0;

    //------------------------------------------------------------
    // Event-based receive monitor
    //------------------------------------------------------------
    event rx_event;

    logic [7:0] received_byte;

    always @(posedge clk) begin
        if (rx_valid) begin
            received_byte <= rx_data;
            -> rx_event;

            $display("[%0t] RX_VALID : %02h",
                     $time, rx_data);
        end
    end

    //------------------------------------------------------------
    // SPI Transfer Task (Mode-0)
    //------------------------------------------------------------
    task spi_send_byte(
        input  [7:0] tx,
        output [7:0] rx
    );
        integer i;

        begin

            for(i=7;i>=0;i=i-1) begin

                mosi = tx[i];

                #50;
                sclk = 1;

                rx[i] = miso;

                #50;
                sclk = 0;

            end

        end

    endtask

    //------------------------------------------------------------
    // Wait for expected byte
    //------------------------------------------------------------
    task expect_byte(
        input [7:0] expected
    );

    begin

        fork

            begin

                @rx_event;

                #1;

                if(received_byte == expected) begin
                    pass++;
                    $display("[PASS] Received %02h", expected);
                end
                else begin
                    fail++;
                    $display("[FAIL] Expected %02h  Got %02h",
                             expected, received_byte);
                end

            end

            begin

                #10000;

                fail++;
                $display("[FAIL] Timeout waiting for RX_VALID");

            end

        join_any

        disable fork;

    end

    endtask

    //------------------------------------------------------------
    // Main Test
    //------------------------------------------------------------
    logic [7:0] dummy;

    initial begin

        clk = 0;
        rst = 1;

        sclk = 0;
        cs_n = 1;
        mosi = 0;

        tx_data = 8'hA5;

        #100;

        rst = 0;

        //--------------------------------------------------------
        // TEST 1
        //--------------------------------------------------------

        $display("\n======================================");
        $display("TEST 1 : Single Byte");
        $display("======================================");

        cs_n = 0;

        fork
            spi_send_byte(8'h3C, dummy);
            expect_byte(8'h3C);
        join

        cs_n = 1;

        #200;

        //--------------------------------------------------------
        // TEST 2
        //--------------------------------------------------------

        $display("\n======================================");
        $display("TEST 2 : Multiple Bytes");
        $display("======================================");

        cs_n = 0;

        fork
            spi_send_byte(8'h11, dummy);
            expect_byte(8'h11);
        join

        fork
            spi_send_byte(8'h22, dummy);
            expect_byte(8'h22);
        join

        fork
            spi_send_byte(8'h33, dummy);
            expect_byte(8'h33);
        join

        cs_n = 1;

        #200;

        //--------------------------------------------------------
        // TEST 3
        //--------------------------------------------------------

        $display("\n======================================");
        $display("TEST 3 : CS Abort");
        $display("======================================");

        cs_n = 0;

        repeat(4) begin

            mosi = 1;

            #50;
            sclk = 1;
            #50;
            sclk = 0;

        end

        cs_n = 1;

        #1000;

        if(rx_valid) begin
            fail++;
            $display("[FAIL] Partial byte accepted");
        end
        else begin
            pass++;
            $display("[PASS] Partial byte discarded");
        end

        //--------------------------------------------------------
        // TEST 4
        //--------------------------------------------------------

        $display("\n======================================");
        $display("TEST 4 : MISO");
        $display("======================================");

        tx_data = 8'h5A;

        cs_n = 0;

        spi_send_byte(8'h00, dummy);

        cs_n = 1;

        if(dummy == 8'h5A) begin
            pass++;
            $display("[PASS] MISO transmitted correctly");
        end
        else begin
            fail++;
            $display("[FAIL] MISO incorrect (%02h)", dummy);
        end

        //--------------------------------------------------------
        // TEST 5
        //--------------------------------------------------------

        $display("\n======================================");
        $display("TEST 5 : Back-to-Back");
        $display("======================================");

        cs_n = 0;

        fork
            spi_send_byte(8'hAA, dummy);
            expect_byte(8'hAA);
        join

        cs_n = 1;

        #200;

        cs_n = 0;

        fork
            spi_send_byte(8'h55, dummy);
            expect_byte(8'h55);
        join

        cs_n = 1;

        //--------------------------------------------------------
        // Summary
        //--------------------------------------------------------

        $display("\n======================================");
        $display("Verification Summary");
        $display("======================================");
        $display("PASSED : %0d", pass);
        $display("FAILED : %0d", fail);

        if(fail == 0)
            $display("SPI SLAVE VERIFICATION PASSED");
        else
            $display("SPI SLAVE VERIFICATION FAILED");

        #100;

        $finish;

    end

endmodule