`timescale 1ns/1ps

module tb_spi_controller;

logic clk;
logic rst;
logic cs_n;

logic [7:0] rx_data;
logic rx_valid;

logic [7:0] tx_data;
logic tx_ready;

logic [31:0] key;
logic key_valid;
logic key_ready;

logic [31:0] bdi;
logic [3:0] bdi_valid;
logic bdi_ready;
logic [3:0] bdi_type;
logic bdi_eot;
logic bdi_eoi;
logic [3:0] mode;

logic [31:0] bdo;
logic bdo_valid;
logic bdo_ready;
logic [3:0] bdo_type;
logic bdo_eot;

logic auth;
logic auth_valid;

integer pass;
integer fail;

spi_controller dut(
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

always #5 clk = ~clk;

initial begin
    clk = 0;
    rst = 1;
    cs_n = 1;

    rx_data = 0;
    rx_valid = 0;

    key_ready = 1;
    bdi_ready = 1;

    bdo = 32'h12345678;
    bdo_valid = 0;
    bdo_type = 0;
    bdo_eot = 0;

    auth = 0;
    auth_valid = 0;

    pass = 0;
    fail = 0;

    #40;
    rst = 0;
end

//------------------------------------------------------------
// Send one SPI byte into controller
//------------------------------------------------------------

task send_byte;

input [7:0] data;

begin

    rx_data = data;
    rx_valid = 1;

    @(posedge clk);

    rx_valid = 0;

    @(posedge clk);

end

endtask

//------------------------------------------------------------

task start_packet;

begin
    cs_n = 0;
    repeat(2) @(posedge clk);
end

endtask

//------------------------------------------------------------

task end_packet;

begin
    cs_n = 1;
    repeat(4) @(posedge clk);
end

endtask

//------------------------------------------------------------

task send_word;

input [31:0] word;

begin

    send_byte(word[31:24]);
    send_byte(word[23:16]);
    send_byte(word[15:8]);
    send_byte(word[7:0]);

end

endtask

//------------------------------------------------------------

task expect_key;

input [31:0] expected;

begin

    repeat(20) begin

        @(posedge clk);

        if(key_valid) begin

            if(key==expected) begin
                pass = pass + 1;
                $display("[PASS] KEY %08x",expected);
            end
            else begin
                fail = fail + 1;
                $display("[FAIL] KEY Expected=%08x Got=%08x",
                        expected,key);
            end

            disable expect_key;

        end

    end

    fail = fail + 1;
    $display("[FAIL] KEY timeout");

end

endtask

//------------------------------------------------------------

task expect_bdi;

input [31:0] expected_data;
input [3:0] expected_type;
input expected_eot;
input expected_eoi;

begin

    repeat(20) begin

        @(posedge clk);

        if(bdi_valid!=0) begin

            if(bdi!==expected_data) begin

                fail = fail + 1;
                $display("[FAIL] DATA");

            end
            else if(bdi_type!=expected_type) begin

                fail = fail + 1;
                $display("[FAIL] TYPE");

            end
            else if(bdi_eot!=expected_eot) begin

                fail = fail + 1;
                $display("[FAIL] EOT");

            end
            else if(bdi_eoi!=expected_eoi) begin

                fail = fail + 1;
                $display("[FAIL] EOI");

            end
            else begin

                pass = pass + 1;
                $display("[PASS] %08x",expected_data);

            end

            disable expect_bdi;

        end

    end

    fail = fail + 1;
    $display("[FAIL] Timeout waiting BDI");

end

endtask
//------------------------------------------------------------
// TESTS
//------------------------------------------------------------

initial begin

    wait(rst==0);

    repeat(5) @(posedge clk);

    //--------------------------------------------------------
    // TEST 1 : RESET
    //--------------------------------------------------------

    $display("");
    $display("====================================");
    $display("TEST 1 : RESET");
    $display("====================================");

    if(key_valid==0 && bdi_valid==0)
    begin
        pass++;
        $display("[PASS] Reset");
    end
    else
    begin
        fail++;
        $display("[FAIL] Reset");
    end

    //--------------------------------------------------------
    // TEST 2 : KEY
    //--------------------------------------------------------

    $display("");
    $display("====================================");
    $display("TEST 2 : LOAD KEY");
    $display("====================================");

    start_packet();

    send_byte(8'h10);

    send_word(32'h00010203);
    expect_key(32'h00010203);

    send_word(32'h04050607);
    expect_key(32'h04050607);

    send_word(32'h08090A0B);
    expect_key(32'h08090A0B);

    send_word(32'h0C0D0E0F);
    expect_key(32'h0C0D0E0F);

    end_packet();

    //--------------------------------------------------------
    // TEST 3 : NONCE
    //--------------------------------------------------------

    $display("");
    $display("====================================");
    $display("TEST 3 : LOAD NONCE");
    $display("====================================");

    start_packet();

    send_byte(8'h20);

    send_word(32'h10111213);
    expect_bdi(32'h10111213,4'd1,0,0);

    send_word(32'h14151617);
    expect_bdi(32'h14151617,4'd1,0,0);

    send_word(32'h18191A1B);
    expect_bdi(32'h18191A1B,4'd1,0,0);

    send_word(32'h1C1D1E1F);
    expect_bdi(32'h1C1D1E1F,4'd1,1,0);

    end_packet();

    //--------------------------------------------------------
    // TEST 4 : ASSOCIATED DATA
    //--------------------------------------------------------

    $display("");
    $display("====================================");
    $display("TEST 4 : LOAD AD");
    $display("====================================");

    start_packet();

    send_byte(8'h30);

    send_word(32'h30313233);
    expect_bdi(32'h30313233,4'd2,0,0);

    send_word(32'h34353637);
    expect_bdi(32'h34353637,4'd2,0,0);

    send_word(32'h38393A3B);
    expect_bdi(32'h38393A3B,4'd2,0,0);

    send_word(32'h3C3D3E3F);
    expect_bdi(32'h3C3D3E3F,4'd2,1,0);

    end_packet();

    //--------------------------------------------------------
    // TEST 5 : MESSAGE
    //--------------------------------------------------------

    $display("");
    $display("====================================");
    $display("TEST 5 : LOAD MESSAGE");
    $display("====================================");

    start_packet();

    send_byte(8'h40);

    send_word(32'h00112233);
    expect_bdi(32'h00112233,4'd3,0,0);

    send_word(32'h44556677);
    expect_bdi(32'h44556677,4'd3,0,0);

    send_word(32'h8899AABB);
    expect_bdi(32'h8899AABB,4'd3,0,0);

    send_word(32'hCCDDEEFF);
    expect_bdi(32'hCCDDEEFF,4'd3,1,1);

    end_packet();
    //--------------------------------------------------------
    // TEST 6 : INVALID COMMAND
    //--------------------------------------------------------

    $display("");
    $display("====================================");
    $display("TEST 6 : INVALID COMMAND");
    $display("====================================");

    start_packet();

    send_byte(8'hAA);

    repeat(10) @(posedge clk);

    if(key_valid==0 && bdi_valid==0)
    begin
        pass++;
        $display("[PASS] Invalid command ignored");
    end
    else
    begin
        fail++;
        $display("[FAIL] Invalid command generated output");
    end

    end_packet();

    //--------------------------------------------------------
    // TEST 7 : MODE OUTPUT
    //--------------------------------------------------------

    $display("");
    $display("====================================");
    $display("TEST 7 : MODE");
    $display("====================================");

    if(mode==4'd1)
    begin
        pass++;
        $display("[PASS] Mode output correct");
    end
    else
    begin
        fail++;
        $display("[FAIL] Mode expected 1 got %0d",mode);
    end

    //--------------------------------------------------------
    // TEST 8 : BDO READY
    //--------------------------------------------------------

    $display("");
    $display("====================================");
    $display("TEST 8 : BDO READY");
    $display("====================================");

    if(bdo_ready==1'b1)
    begin
        pass++;
        $display("[PASS] bdo_ready always asserted");
    end
    else
    begin
        fail++;
        $display("[FAIL] bdo_ready");
    end

    //--------------------------------------------------------
    // SUMMARY
    //--------------------------------------------------------

    $display("");
    $display("====================================");
    $display("SPI CONTROLLER VERIFICATION SUMMARY");
    $display("====================================");

    $display("PASS = %0d",pass);
    $display("FAIL = %0d",fail);

    if(fail==0)
    begin
        $display("");
        $display("########################################");
        $display("# SPI CONTROLLER VERIFICATION PASSED   #");
        $display("########################################");
    end
    else
    begin
        $display("");
        $display("########################################");
        $display("# SPI CONTROLLER VERIFICATION FAILED   #");
        $display("########################################");
    end

    #100;
    $finish;

end

endmodule