`default_nettype none
module servant_spi_master_if
  #(parameter ADDRESS_WIDTH = 24,
    parameter CLOCK_DIVIDER = 2,
    parameter CLOCK_POLARITY = 0)
   (// Wishbone Slave Interface
    input                                      clock,
    input                                      reset_n,
    input [31:0]                               wr_data,
    input [ADDRESS_WIDTH-1:2]                  address,
    input [3:0]                                wb_sel,
    input                                      wb_we,
    input                                      wb_cyc,
    output [31:0]                              rd_data,
    output reg                                 wb_ack,

    // SPI Master Interface
    input                                      spi_miso,
    output                                     spi_sck,
    output reg                                 spi_ss,
    output                                     spi_mosi);

// State encoding
parameter  IDLE = 3'b000;
parameter  TRANSMIT_COMMAND = 3'b001;
parameter  TRANSMIT_ADDRESS1 = 3'b010;
parameter  TRANSMIT_ADDRESS2 = 3'b011;
parameter  TRANSMIT_ADDRESS3 = 3'b100;
parameter  TRANSMIT_DATA = 3'b101;
parameter  READ_DATA = 3'b110;

// Command encoding
parameter CMD_READ_DATA = 8'h3;
parameter CMD_WRITE_DATA = 8'h2;

reg                                             serial_clk;
reg         [15:0]                              clk_cnt;
reg         [2:0]                               bit_cnt;

reg         [2:0]                               state;
reg                                             wr_cmd;
reg         [ADDRESS_WIDTH-1:0]                 address_reg;
reg         [7:0]                               wr_data_reg[4];
reg         [7:0]                               rd_data_reg[4];
reg         [1:0]                               byte_offset;
reg         [2:0]                               num_bytes;
reg         [7:0]                               spi_out_reg;
reg         [7:0]                               spi_in_reg;

assign rd_data = {rd_data_reg[3], rd_data_reg[2], rd_data_reg[1], rd_data_reg[0]};
assign spi_sck = serial_clk;
assign spi_mosi = spi_out_reg[7];

// Clock divider to generate serial clock and tick signal
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        serial_clk <= CLOCK_POLARITY;
        clk_cnt    <= 0;
        bit_cnt    <= 0;
        spi_ss     <= 1;
        wb_ack     <= 0;
        state      <= IDLE;
    end else if (wb_cyc && spi_ss) begin
        serial_clk     <= 0;
        clk_cnt        <= 0;
        bit_cnt        <= 0;
        spi_ss         <= 0;
        wb_ack         <= 0;
        state          <= TRANSMIT_COMMAND;
        wr_data_reg[0] <= wr_data[31:24];
        wr_data_reg[1] <= wr_data[23:16];
        wr_data_reg[2] <= wr_data[15:8];
        wr_data_reg[3] <= wr_data[7:0];
        rd_data_reg[0] <= 8'd0;
        rd_data_reg[1] <= 8'd0;
        rd_data_reg[2] <= 8'd0;
        rd_data_reg[3] <= 8'd0;
        address_reg[ADDRESS_WIDTH-1:2] <= address;
        if (wb_we) begin
            wr_cmd       <= 1'b1;
            spi_out_reg  <= CMD_WRITE_DATA;
        end
        else begin
            wr_cmd       <= 1'b0;
            spi_out_reg  <= CMD_READ_DATA;
        end
        num_bytes <= {1'b0, wb_sel[0]} + {1'b0, wb_sel[1]} + {1'b0, wb_sel[2]} + {1'b0, wb_sel[3]};
        casez (wb_sel)
            4'b???1: begin
                address_reg[1:0] <= 2'd0;
                byte_offset      <= 2'd0;
            end
            4'b??10: begin
                address_reg[1:0] <= 2'd1;
                byte_offset      <= 2'd1;
            end
            4'b?100: begin
                address_reg[1:0] <= 2'd2;
                byte_offset      <= 2'd2;
            end
            4'b1000: begin
                address_reg[1:0] <= 2'd3;
                byte_offset      <= 2'd3;
            end
            default: begin
                address_reg[1:0] <= 2'dx;
                byte_offset      <= 2'dx; // No 1's found
            end
        endcase
    end else if (!spi_ss) begin
        if (clk_cnt >= CLOCK_DIVIDER-1) begin
            clk_cnt <= 0;
            bit_cnt <= bit_cnt + 1;
            serial_clk <= 0;
            spi_out_reg <= spi_out_reg << 1;
            if (bit_cnt == 3'd7) begin
                if (state == TRANSMIT_COMMAND) begin
                    state <= TRANSMIT_ADDRESS1;
                    spi_out_reg <= address_reg[ADDRESS_WIDTH-1:16];
                end
                else if (state == TRANSMIT_ADDRESS1) begin
                    state <= TRANSMIT_ADDRESS2;
                    spi_out_reg <= address_reg[15:8];
                end
                else if (state == TRANSMIT_ADDRESS2) begin
                    state <= TRANSMIT_ADDRESS3;
                    spi_out_reg <= address_reg[7:0];
                end
                else if (state == TRANSMIT_ADDRESS3) begin
                    if(wb_we) begin
                        state <= TRANSMIT_DATA;
                        spi_out_reg <= wr_data_reg[byte_offset];
                        byte_offset <= byte_offset + 1;
                    end
                    else begin
                        state <= READ_DATA;
                        num_bytes <= num_bytes - 1;
                    end
                end
                else if (state == TRANSMIT_DATA) begin
                    if (byte_offset == num_bytes[1:0]) begin
                        clk_cnt    <= 0;
                        bit_cnt    <= 0;
                        spi_ss         <= 1;
                        wb_ack     <= 1;
                        state      <= IDLE;
                    end
                    else begin
                        state <= TRANSMIT_DATA;
                        spi_out_reg <= wr_data_reg[byte_offset];
                        byte_offset <= byte_offset + 1;
                    end
                end
                else if (state == READ_DATA) begin
                    rd_data_reg[byte_offset] <= spi_in_reg;
                    if (byte_offset == num_bytes[1:0]) begin
                        clk_cnt    <= 0;
                        bit_cnt    <= 0;
                        spi_ss         <= 1;
                        wb_ack     <= 1;
                        state      <= IDLE;
                    end
                    else begin
                        state <= READ_DATA;
                        byte_offset <= byte_offset + 1;
                    end
                end
            end
        end else begin
            clk_cnt <= clk_cnt + 1;
            if (clk_cnt == CLOCK_DIVIDER%2) begin
                serial_clk <= 1;
                spi_in_reg <= {spi_in_reg[6:0], spi_miso};
            end
        end
    end else begin
        serial_clk <= CLOCK_POLARITY;
        clk_cnt    <= 0;
        bit_cnt    <= 0;
        spi_ss     <= 1;
        wb_ack     <= 1;
        state      <= IDLE;
    end
end

endmodule