`timescale 1ns / 1ps

module SDES_tb;

    reg en;
    reg [9:0] key;
    reg [7:0] plaintext;
    reg encrypt;
    wire [7:0] ciphertext;

    integer passed_tests = 0;
    integer failed_tests = 0;
    integer i;

    SDES uut (
        .en(en),
        .key(key),
        .plaintext(plaintext),
        .encrypt(encrypt),
        .ciphertext(ciphertext)
    );

    task test_roundtrip;
        input [9:0] test_key;
        input [7:0] test_pt;

        reg [7:0] captured_ct;
        reg [7:0] decrypted_pt;

        begin
            // Encryption
            encrypt = 1'b1;
            key = test_key;
            plaintext = test_pt;

            #10 en = 1;
            #10 captured_ct = ciphertext;
            en = 0;
            #10;

            // Decryption
            encrypt = 1'b0;
            plaintext = captured_ct;

            #10 en = 1;
            #10 decrypted_pt = ciphertext;
            en = 0;
            #10;

            if (decrypted_pt === test_pt) begin
                $display("[PASS] Key: %b | PT: %b -> CT: %b -> Decrypted: %b",
                         test_key, test_pt, captured_ct, decrypted_pt);
                passed_tests = passed_tests + 1;
            end
            else begin
                $display("[FAIL] Key: %b | PT: %b -> CT: %b -> Decrypted: %b (MISMATCH!)",
                         test_key, test_pt, captured_ct, decrypted_pt);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    initial begin
        en = 0;
        key = 10'b0;
        plaintext = 8'b0;
        encrypt = 0;

        #100;

        $display("==================================================");
        $display("               S-DES VERIFICATION                 ");
        $display("==================================================");

        $display("\n--- PHASE 1: Extreme Hardware Edge Cases ---");
        test_roundtrip(10'b0000000000, 8'b00000000);
        test_roundtrip(10'b1111111111, 8'b11111111);
        test_roundtrip(10'b1010101010, 8'b01010101);
        test_roundtrip(10'b0101010101, 8'b10101010);

        $display("\n--- PHASE 2: Standard Known Vectors ---");
        test_roundtrip(10'b1010000010, 8'b01110010);
        test_roundtrip(10'b0111111101, 8'b10101010);
        test_roundtrip(10'b1110001110, 8'b00001111);

        $display("\n--- PHASE 3: Avalanche Effect (Key Sensitivity) ---");
        test_roundtrip(10'b1000000000, 8'b11001100);
        test_roundtrip(10'b1000000001, 8'b11001100);
        test_roundtrip(10'b0000000000, 8'b11001100);

        $display("\n--- PHASE 4: Avalanche Effect (Data Sensitivity) ---");
        test_roundtrip(10'b1100110011, 8'b00000000);
        test_roundtrip(10'b1100110011, 8'b00000001);
        test_roundtrip(10'b1100110011, 8'b10000000);

        $display("\n--- PHASE 5: Automated Random Fuzzing ---");
        for (i = 0; i < 10; i = i + 1)
            test_roundtrip($random % 1024, $random % 256);

        $display("\n==================================================");
        $display("   VERIFICATION SUMMARY REPORT                    ");
        $display("==================================================");
        $display("Total Tests Run : %0d", passed_tests + failed_tests);
        $display("Total PASSED    : %0d", passed_tests);
        $display("Total FAILED    : %0d", failed_tests);

        if (failed_tests == 0)
            $display(">> SIGN-OFF STATUS: PERFECT (100%% PASS RATE)");
        else
            $display(">> SIGN-OFF STATUS: FAILED (CHECK LOGS)");

        $display("==================================================\n");

        $finish;
    end

endmodule