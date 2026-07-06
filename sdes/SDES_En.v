/*
    Simplified Data Encryption Standard (S-DES)
    Version 2
    - Combinational RTL
    - Latch-free
    - ASIC coding style
*/

module SDES(
    input              en,
    input      [0:9]   key,
    input      [0:7]   plaintext,
    input              encrypt,
    output     [0:7]   ciphertext
);

    //--------------------------------------------------------
    // Internal Registers
    //--------------------------------------------------------
    reg [0:7] key_round1;
    reg [0:7] key_round2;

    reg [0:7] IP_out;
    reg [0:7] sw_out;
    reg [0:7] feistel_out;
    reg [0:7] iip_out;

    assign ciphertext = en ? iip_out : 8'h00;

    //--------------------------------------------------------
    // Key Generation
    //--------------------------------------------------------
    task GenerateKeys;

        input  [0:9] Key;
        output [0:7] Key1;
        output [0:7] Key2;

        reg [0:9] p10_out;
        reg [0:9] key_ls1;
        reg [0:9] key_ls3;

        begin

            // P10
            p10_out =
            {
                Key[2], Key[4], Key[1], Key[6], Key[3],
                Key[9], Key[0], Key[8], Key[7], Key[5]
            };

            // LS-1
            key_ls1 =
            {
                p10_out[1:4], p10_out[0],
                p10_out[6:9], p10_out[5]
            };

            // P8 -> K1
            Key1 =
            {
                key_ls1[5], key_ls1[2], key_ls1[6], key_ls1[3],
                key_ls1[7], key_ls1[4], key_ls1[9], key_ls1[8]
            };

            // LS-3
            key_ls3 =
            {
                p10_out[3:4], p10_out[0:2],
                p10_out[8:9], p10_out[5:7]
            };

            // P8 -> K2
            Key2 =
            {
                key_ls3[5], key_ls3[2], key_ls3[6], key_ls3[3],
                key_ls3[7], key_ls3[4], key_ls3[9], key_ls3[8]
            };

        end

    endtask

    //--------------------------------------------------------
    // Feistel Function
    //--------------------------------------------------------
    task Feistel;

        input  [0:7] inp_block;
        input  [0:7] key;
        output [0:7] out_block;

        reg [0:3] left_half;
        reg [0:3] right_half;

        reg [0:3] xor_left;
        reg [0:3] xor_right;

        reg [0:3] p4_in;
        reg [0:3] p4_out;

        reg [0:7] EP_out;
        reg [0:7] xor_out;

        reg [0:1] s0_out;
        reg [0:1] s1_out;

        begin

            left_half  = inp_block[0:3];
            right_half = inp_block[4:7];

            EP_out =
            {
                right_half[3],
                right_half[0],
                right_half[1],
                right_half[2],
                right_half[1],
                right_half[2],
                right_half[3],
                right_half[0]
            };

            xor_out = EP_out ^ key;

            xor_left  = xor_out[0:3];
            xor_right = xor_out[4:7];

            S0_Box(xor_left , s0_out);
            S1_Box(xor_right, s1_out);

            p4_in = {s0_out,s1_out};

            p4_out =
            {
                p4_in[1],
                p4_in[3],
                p4_in[2],
                p4_in[0]
            };

            xor_left = p4_out ^ left_half;

            out_block =
            {
                xor_left,
                right_half
            };

        end

    endtask

// S0 Box
	task S0_Box;
	input[0:3] inp_bits;
	output[0:1] out_bits;
	
	begin
		case(inp_bits)
			4'b0000: out_bits = 2'b01;
			4'b0001: out_bits = 2'b11;
			4'b0010: out_bits = 2'b00;
			4'b0011: out_bits = 2'b10;
			4'b0100: out_bits = 2'b11;
			4'b0101: out_bits = 2'b01;
			4'b0110: out_bits = 2'b10;
			4'b0111: out_bits = 2'b00;
			4'b1000: out_bits = 2'b00;
			4'b1001: out_bits = 2'b11;
			4'b1010: out_bits = 2'b10;
			4'b1011: out_bits = 2'b01;
			4'b1100: out_bits = 2'b01;
			4'b1101: out_bits = 2'b11;
			4'b1110: out_bits = 2'b11;
			4'b1111: out_bits = 2'b10;
		endcase
	end
	
	endtask

	// S1 Box
	task S1_Box;
	input[0:3] inp_bits;
	output[0:1] out_bits;
	
	begin
		case(inp_bits)
			4'b0000: out_bits = 2'b00;
			4'b0001: out_bits = 2'b10;
			4'b0010: out_bits = 2'b01;
			4'b0011: out_bits = 2'b00;
			4'b0100: out_bits = 2'b10;
			4'b0101: out_bits = 2'b01;
			4'b0110: out_bits = 2'b11;
			4'b0111: out_bits = 2'b11;
			4'b1000: out_bits = 2'b11;
			4'b1001: out_bits = 2'b10;
			4'b1010: out_bits = 2'b00;
			4'b1011: out_bits = 2'b01;
			4'b1100: out_bits = 2'b01;
			4'b1101: out_bits = 2'b00;
			4'b1110: out_bits = 2'b00;
			4'b1111: out_bits = 2'b11;
		endcase
	end
	
	endtask

    //==========================================================
    // Main SDES Combinational Logic
    //==========================================================

    always @(*) begin

        //------------------------------------------------------
        // Default assignments
        //------------------------------------------------------

        key_round1  = 8'h00;
        key_round2  = 8'h00;

        IP_out       = 8'h00;
        sw_out       = 8'h00;
        feistel_out  = 8'h00;
        iip_out      = 8'h00;

        if(en) begin

            //----------------------------------
            // Key Schedule
            //----------------------------------

            GenerateKeys(
                key,
                key_round1,
                key_round2
            );

            //----------------------------------
            // Initial Permutation
            //----------------------------------

            IP_out =
            {
                plaintext[1],
                plaintext[5],
                plaintext[2],
                plaintext[0],
                plaintext[3],
                plaintext[7],
                plaintext[4],
                plaintext[6]
            };

            //----------------------------------
            // Round 1
            //----------------------------------

            if(encrypt)
                Feistel(IP_out,key_round1,feistel_out);
            else
                Feistel(IP_out,key_round2,feistel_out);

            //----------------------------------
            // Swap
            //----------------------------------

            sw_out =
            {
                feistel_out[4:7],
                feistel_out[0:3]
            };

            //----------------------------------
            // Round 2
            //----------------------------------

            if(encrypt)
                Feistel(sw_out,key_round2,feistel_out);
            else
                Feistel(sw_out,key_round1,feistel_out);

            //----------------------------------
            // Inverse IP
            //----------------------------------

            iip_out =
            {
                feistel_out[3],
                feistel_out[0],
                feistel_out[2],
                feistel_out[4],
                feistel_out[6],
                feistel_out[1],
                feistel_out[7],
                feistel_out[5]
            };

        end

    end

endmodule