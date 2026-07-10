module spi_control (
    input  wire        spi_sclk,
    input  wire        rst_n,
    input  wire        spi_cs_n,
    input  wire        spi_mosi,
    output reg         spi_miso,
    output reg         irq,
    output reg  [9:0]  parallel_key,
    output reg  [7:0]  parallel_data,
    output reg         data_ready,
    input  wire [7:0]  ciphertext_in
);

    reg [17:0] shift_reg;
    reg [4:0]  bit_count;
    reg [7:0]  tx_reg;
    reg        latch_done;

    localparam STATE_IDLE     = 2'b00;
    localparam STATE_RECEIVE  = 2'b01;
    localparam STATE_COMPUTE  = 2'b10;
    localparam STATE_TRANSMIT = 2'b11;
    reg [1:0] state;

    always @(posedge spi_sclk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= STATE_IDLE;
            shift_reg     <= 18'h0;
            bit_count     <= 5'd0;
            parallel_key  <= 10'h0;
            parallel_data <= 8'h0;
            data_ready    <= 1'b0;
            irq           <= 1'b0;
            tx_reg        <= 8'h0;
            latch_done    <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    data_ready <= 1'b0;
                    irq        <= 1'b0;
                    latch_done <= 1'b0;
                    
                    if (!spi_cs_n) begin
                        state     <= STATE_RECEIVE;
                        shift_reg <= {shift_reg[16:0], spi_mosi}; 
                        bit_count <= 5'd1; 
                    end else begin
                        bit_count <= 5'd0;
                    end
                end

                STATE_RECEIVE: begin
                    shift_reg <= {shift_reg[16:0], spi_mosi};
                    
                    if (bit_count == 5'd17) begin
                        state <= STATE_COMPUTE;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                    end
                end

                STATE_COMPUTE: begin
                    parallel_key  <= shift_reg[17:8];
                    parallel_data <= shift_reg[7:0];
                    data_ready    <= 1'b1;
                    latch_done    <= 1'b0; 
                    state         <= STATE_TRANSMIT;
                end

                STATE_TRANSMIT: begin
                    data_ready <= 1'b0; 
                    irq        <= 1'b1;
                    
                    if (!latch_done) begin
                        tx_reg <= {ciphertext_in[6:0], 1'b0};
                        latch_done <= 1'b1;
                    end else begin
                        tx_reg <= {tx_reg[6:0], 1'b0};
                    end
                    
                    if (spi_cs_n) state <= STATE_IDLE;
                end
            endcase
        end
    end


    always @(negedge spi_sclk or negedge rst_n) begin
        if (!rst_n) begin
            spi_miso <= 1'b0;
        end else begin
            if (state == STATE_TRANSMIT && !latch_done) begin
                spi_miso <= ciphertext_in[7];
            end else if (state == STATE_TRANSMIT && latch_done) begin
                spi_miso <= tx_reg[7];        
            end else begin
                spi_miso <= 1'b0;
            end
        end
    end

endmodule