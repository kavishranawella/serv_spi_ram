`default_nettype none
module servant_spi_master_if
  #(parameter ADDRESS_WIDTH = 24,
    parameter CLOCK_DIVIDER = 2)
   (// Wishbone Slave Interface
    input wire                                     clock,
    input wire                                     reset,
    input wire [31:0]                               wr_data,
    input wire [ADDRESS_WIDTH-1:2]                  address,
    input wire [3:0]                                wb_sel,
    input wire                                     wb_we,
    input wire                                     wb_cyc,
    output wire [31:0]                              rd_data,
    output reg                                 wb_ack,

    // SPI Master Interface
    input  wire                                    spi_miso,
    output wire                                    spi_sck,
    output reg                                 spi_ss,
    output wire                                    spi_mosi);

// State encoding
parameter  IDLE = 3'b000;
parameter  TRANSMIT_COMMAND = 3'b001;
parameter  TRANSMIT_ADDRESS1 = 3'b010;
parameter  TRANSMIT_ADDRESS2 = 3'b011;
parameter  TRANSMIT_ADDRESS3 = 3'b100;
parameter  TRANSMIT_DATA = 3'b101;
parameter  READ_DATA = 3'b110;
parameter  FINISH = 3'b111;

// Command encoding
parameter CMD_READ_DATA = 8'h3;
parameter CMD_WRITE_DATA = 8'h2;

reg                                             serial_clk;
reg         [15:0]                              clk_cnt;
reg         [2:0]                               bit_cnt;

reg         [2:0]                               state;
reg                                             wr_cmd;
reg         [ADDRESS_WIDTH-1:0]                 address_reg;
reg         [31:0]                              wr_data_reg;
reg         [31:0]                              rd_data_reg;
reg         [1:0]                               byte_offset;
reg         [1:0]                               last_byte;
reg         [7:0]                               spi_out_reg;
reg         [7:0]                               spi_in_reg;

wire [1:0] sel_dec_start;
wire [1:0] sel_dec_last;

assign spi_sck = serial_clk;
assign spi_mosi = spi_out_reg[7];
assign rd_data = rd_data_reg;
//assign rd_data = {rd_data_reg[3], rd_data_reg[2], rd_data_reg[1], rd_data_reg[0]}; //TODO: Check and remove this
assign sel_dec_start = wb_sel[0] ? 2'd0 : wb_sel[1] ? 2'd1 : wb_sel[2] ? 2'd2 : wb_sel[3] ? 2'd3 : 2'd0;
assign sel_dec_last  = wb_sel[3] ? 2'd0 : wb_sel[2] ? 2'd3 : wb_sel[1] ? 2'd2 : wb_sel[0] ? 2'd1 : 2'd0;

// Clock divider to generate serial clock
always @(posedge clock or posedge reset) begin
	if (reset) begin
		serial_clk <= 1;
	end else if (!spi_ss) begin
		if ((state == TRANSMIT_DATA || state == READ_DATA) && byte_offset == last_byte && clk_cnt == 0 && bit_cnt == 0) begin // TODO: Try to improve this
			serial_clk <= 1;
		end else if (clk_cnt % (CLOCK_DIVIDER/2) == 0) begin
			serial_clk <= ~serial_clk;
		end else begin
			serial_clk <= serial_clk;
		end
	end else if (wb_cyc && !wb_ack) begin
		serial_clk <= 0;
   	end else begin
		serial_clk <= 1;
	end
end

always @(posedge clock or posedge reset) begin
   if (reset) begin
		clk_cnt <= 0;
   end else if ((!spi_ss || wb_cyc) && !wb_ack && (clk_cnt != CLOCK_DIVIDER - 1)) begin
		clk_cnt <= clk_cnt + 1;
	end else begin
      clk_cnt <= 0;
   end
end

always @(posedge clock or posedge reset) begin
   if (reset) begin
		bit_cnt <= 0;
   end else if ((spi_ss && !wb_cyc) || wb_ack) begin
		bit_cnt <= 0;
	end else if (clk_cnt == 0 && (!spi_ss || wb_cyc)) begin
		bit_cnt <= bit_cnt + 1;
	end else begin
      bit_cnt <= bit_cnt;
   end
end

always @(posedge clock or posedge reset) begin
   if (reset) begin
		state <= IDLE;
	end else if (clk_cnt == 0 && bit_cnt == 0) begin
		case (state)
			IDLE: begin
				if (wb_cyc) begin
					state <= TRANSMIT_COMMAND;
				end
				else begin
					state <= IDLE;
				end
			end
			TRANSMIT_COMMAND: begin
				state <= TRANSMIT_ADDRESS1;
			end
			TRANSMIT_ADDRESS1: begin
				state <= TRANSMIT_ADDRESS2;
			end
			TRANSMIT_ADDRESS2: begin
				state <= TRANSMIT_ADDRESS3;
			end
			TRANSMIT_ADDRESS3: begin
				if(wr_cmd) begin
					state <= TRANSMIT_DATA;
				end
				else begin
					state <= READ_DATA;
				end
			end
			TRANSMIT_DATA: begin
				if (byte_offset == last_byte) begin
					state <= FINISH;
				end
				else begin
					state <= TRANSMIT_DATA;
				end
			end
			READ_DATA: begin
			  if (byte_offset == last_byte) begin
					state <= FINISH;
			  end
			  else begin
					state <= READ_DATA;
			  end
			end
			FINISH: begin
				state <= IDLE;
			end
		endcase
	end else begin
		if (state == FINISH) begin  //TODO: Try to improve
			state <= IDLE;
		end else begin
			state <= state;
		end
	end
end

always @(negedge serial_clk) begin
	if (bit_cnt == 1) begin
		case (state)
			TRANSMIT_COMMAND: begin
			  if (wb_we) begin
					spi_out_reg <= CMD_WRITE_DATA;
			  end
			  else begin
					spi_out_reg <= CMD_READ_DATA;
			  end
			end
			TRANSMIT_ADDRESS1:
			begin
				spi_out_reg <= address_reg[ADDRESS_WIDTH-1:16];
			end
			TRANSMIT_ADDRESS2:
			begin
				spi_out_reg <= address_reg[15:8];
			end
			TRANSMIT_ADDRESS3:
			begin
				spi_out_reg <= address_reg[7:0];
			end
			TRANSMIT_DATA: begin
				spi_out_reg <= wr_data_reg[byte_offset*8+:8];
			end
			default: begin
			end
		endcase
	end else begin
		spi_out_reg <= spi_out_reg << 1;
	end
end


always @(posedge serial_clk) begin
	if (bit_cnt == 0) begin
		case (state)
			TRANSMIT_COMMAND: begin
				byte_offset <= address_reg[1:0];
			end
			TRANSMIT_DATA: begin
				byte_offset <= byte_offset + 1;
			end
			READ_DATA: begin
				byte_offset <= byte_offset + 1;
			end
			default: begin
			end
		endcase
	end
end


always @(posedge serial_clk) begin
	if (state == READ_DATA) begin
		spi_in_reg <= {spi_in_reg[6:0], spi_miso};
		if (bit_cnt == 0) begin
			rd_data_reg[byte_offset*8+:8] <= {spi_in_reg[6:0], spi_miso};
		end
	end
end

always @(state) begin
	case (state)
		IDLE:
		begin
        spi_ss = 1;
        wb_ack = 0;
		end
		TRANSMIT_COMMAND:
		begin
        spi_ss = 0;
        wb_ack = 0;
		  wr_data_reg = wr_data;
//        wr_data_reg[3] = wr_data[31:24];  //TODO: Check and remove this
//        wr_data_reg[2] = wr_data[23:16];
//        wr_data_reg[1] = wr_data[15:8];
//        wr_data_reg[0] = wr_data[7:0];
        address_reg    = {address, sel_dec_start};
		  last_byte = sel_dec_last;
        if (wb_we) begin
            wr_cmd = 1'b1;
        end
        else begin
            wr_cmd = 1'b0;
        end
		end
		FINISH:
		begin
        spi_ss = 1;
        wb_ack = 1;
		end
		default:
		begin
		end
	endcase
end

endmodule