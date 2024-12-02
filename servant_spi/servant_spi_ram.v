`default_nettype none
module servant_spi_ram
  #(//Memory parameters
    parameter depth = 65536,
    parameter aw    = $clog2(depth)+2,
    parameter RESET_STRATEGY = "",
    parameter memfile = "")
   (input wire 		i_clk,
    input wire [aw-1:0] i_addr,
    input wire [7:0] 	i_wdata,
    input wire 		i_we,
    input wire 		i_re,
    output wire [7:0] 	o_rdata);

   reg [31:0] 		mem [0:depth-1] /* verilator public */;

   always @* begin
      case (i_addr[1:0])
          2'b00: o_rdata = mem[i_addr[aw-1:2]][7:0];
          2'b01: o_rdata = mem[i_addr[aw-1:2]][15:8];
          2'b10: o_rdata = mem[i_addr[aw-1:2]][23:16];
          2'b11: o_rdata = mem[i_addr[aw-1:2]][31:24];
      endcase
   end

   //assign o_rdata = mem[i_addr[aw-1:2]][(8*i_addr[1:0])+:8];

   always @(negedge i_clk) begin
      if (!i_we) begin
        case (i_addr[1:0])
          2'b00: mem[i_addr[aw-1:2]][7:0]   <= i_wdata;
          2'b01: mem[i_addr[aw-1:2]][15:8]  <= i_wdata;
          2'b10: mem[i_addr[aw-1:2]][23:16] <= i_wdata;
          2'b11: mem[i_addr[aw-1:2]][31:24] <= i_wdata;
        endcase
        //mem[i_addr[aw-1:2]][(8*i_addr[1:0]+:8]) <= i_wdata;
      end
   end

   initial
     if(|memfile) begin
`ifndef ISE
`ifndef CCGM
	$display("Preloading %m from %s", memfile);
`endif
`endif
	$readmemh(memfile, mem);
     end

endmodule
