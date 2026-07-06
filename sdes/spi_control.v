module spi_control (
    input  wire        clk,           // Clock utama chip
    input  wire        rst_n,         // Reset global (Active Low)
    
    // Antarmuka Fisik SPI (Ke Luar Chip / CPU Drone)
    input  wire        spi_cs_n,      // Chip Select
    input  wire        spi_sclk,      // SPI Clock dari CPU Drone
    input  wire        spi_mosi,      // Data masuk serial
    output reg         spi_miso,      // Data keluar serial
    
    // Antarmuka Paralel Internal (Ke Dalam Chip S-DES)
    output reg  [9:0]  parallel_key,  // Hasil potong 10-bit Key
    output reg  [7:0]  parallel_data, // Hasil potong 8-bit Plaintext
    output reg         data_ready,    // Sinyal pemicu S-DES (Enable)
    input  wire [7:0]  ciphertext_in  // Hasil acakan dari modul SDES
);

    reg [17:0] shift_reg;
    reg [4:0]  bit_count;
    reg [7:0]  tx_reg;
    reg        load_done;

    localparam STATE_IDLE     = 2'b00;
    localparam STATE_RECEIVE  = 2'b01;
    localparam STATE_COMPUTE  = 2'b10;
    localparam STATE_TRANSMIT = 2'b11;
    reg [1:0] current_state, next_state;

    // FSM: Transisi State
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= STATE_IDLE;
        else current_state <= next_state;
    end

    // FSM: Logika Next State
    always @(*) begin
        next_state = current_state;
        case (current_state)
            STATE_IDLE:     if (!spi_cs_n) next_state = STATE_RECEIVE;
            STATE_RECEIVE:  if (spi_cs_n) next_state = STATE_IDLE;
                            else if (bit_count == 5'd18) next_state = STATE_COMPUTE;
            STATE_COMPUTE:  next_state = STATE_TRANSMIT;
            STATE_TRANSMIT: if (spi_cs_n) next_state = STATE_IDLE;
            default:        next_state = STATE_IDLE;
        endcase
    end

    // SPI Receive (Menggunakan detak SPI SCLK)
    always @(posedge spi_sclk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 18'h0;
            bit_count <= 5'd0;
        end else if (current_state == STATE_RECEIVE) begin
            shift_reg <= {shift_reg[16:0], spi_mosi};
            bit_count <= bit_count + 1'b1;
        end else if (current_state == STATE_IDLE) begin
            bit_count <= 5'd0;
        end
    end

    // Trigger S-DES (Menggunakan clock utama chip)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            parallel_key  <= 10'h0;
            parallel_data <= 8'h0;
            data_ready    <= 1'b0;
        end else begin
            case (current_state)
                STATE_COMPUTE: begin
                    parallel_key  <= shift_reg[17:8];
                    parallel_data <= shift_reg[7:0];
                    data_ready    <= 1'b1;
                end
                STATE_TRANSMIT: data_ready <= 1'b0;
                STATE_IDLE:     data_ready <= 1'b0;
                default:        data_ready <= 1'b0;
            endcase
        end
    end

    // SPI Transmit (Menggunakan negedge SPI SCLK untuk keamanan CDC)
    always @(negedge spi_sclk or negedge rst_n) begin
        if (!rst_n) begin
            spi_miso  <= 1'b0;
            tx_reg    <= 8'h0;
            load_done <= 1'b0;
        end else if (current_state == STATE_TRANSMIT) begin
            if (!load_done) begin
                spi_miso  <= ciphertext_in[7];
                tx_reg    <= {ciphertext_in[6:0], 1'b0};
                load_done <= 1'b1;
            end else begin
                spi_miso  <= tx_reg[7];
                tx_reg    <= {tx_reg[6:0], 1'b0};
            end
        end else begin
            spi_miso  <= 1'b0;
            load_done <= 1'b0;
        end
    end

endmodule