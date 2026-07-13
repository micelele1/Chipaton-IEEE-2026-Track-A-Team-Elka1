`timescale 1ns / 1ps

module TOPM_tb;

    reg spi_sclk, rst_n, spi_cs_n, spi_mosi;
    wire spi_miso, irq;

    // DUT
    TOPM uut (
        .RST_N    (rst_n),
        .SPI_CS_N (spi_cs_n),
        .SPI_SCLK (spi_sclk),
        .SPI_MOSI (spi_mosi),
        .SPI_MISO (spi_miso),
        .IRQ      (irq)
    );

    // Reference SDES
    reg         ref_en;
    reg         ref_encrypt;
    reg [0:9]   ref_key;
    reg [0:7]   ref_plaintext;
    wire [0:7]  ref_ciphertext;

    SDES ref (
        .en(ref_en),
        .encrypt(ref_encrypt),
        .key(ref_key),
        .plaintext(ref_plaintext),
        .ciphertext(ref_ciphertext)
    );

    always #25 spi_sclk = ~spi_sclk;

    task run_test;
        input [9:0] key;
        input [7:0] pt;

        reg [17:0] tx;
        reg [7:0] received_ct;
        reg [7:0] expected_ct;
        integer i;

        begin
            // -----------------------------
            // Reference SDES encryption
            // -----------------------------
            ref_encrypt  = 1'b1;
            ref_key       = key;
            ref_plaintext = pt;
            ref_en        = 1'b1;
            #10;
            expected_ct = ref_ciphertext;
            ref_en = 1'b0;

            // -----------------------------
            // Send through SPI
            // -----------------------------
            tx = {key, pt};

            spi_cs_n = 0;

            for (i = 17; i >= 0; i = i - 1) begin
                @(negedge spi_sclk);
                spi_mosi = tx[i];
            end

            wait(irq);

            for (i = 7; i >= 0; i = i - 1) begin
                @(posedge spi_sclk);
                received_ct[i] = spi_miso;
            end

            @(negedge spi_sclk);
            spi_cs_n = 1;

            if (received_ct === expected_ct)
                $display("[PASS] Key=%b PT=%b CT=%b",
                         key, pt, received_ct);
            else
                $display("[FAIL] Key=%b PT=%b Expected=%b Got=%b",
                         key, pt, expected_ct, received_ct);

            #100;
        end
    endtask

    initial begin
        spi_sclk = 0;
        rst_n = 0;
        spi_cs_n = 1;
        spi_mosi = 0;

        ref_en = 0;
        ref_encrypt = 1;

        #100;
        rst_n = 1;
        #100;

        $display("==================================================");
        $display("               TOPM VERIFICATION                  ");
        $display("==================================================");

        // Phase 1
        run_test(10'b0000000000, 8'b00000000);
        run_test(10'b1111111111, 8'b11111111);
        run_test(10'b1010101010, 8'b01010101);
        run_test(10'b0101010101, 8'b10101010);

        // Phase 2
        run_test(10'b1010000010, 8'b01110010);
        run_test(10'b0111111101, 8'b10101010);
        run_test(10'b1110001110, 8'b00001111);

        // Phase 3
        run_test(10'b1000000000, 8'b11001100);
        run_test(10'b1000000001, 8'b11001100);
        run_test(10'b0000000000, 8'b11001100);

        // Phase 4
        run_test(10'b1100110011, 8'b00000000);
        run_test(10'b1100110011, 8'b00000001);
        run_test(10'b1100110011, 8'b10000000);

        // Phase 5
        repeat (10)
            run_test($random % 1024, $random % 256);

        $finish;
    end

endmodule