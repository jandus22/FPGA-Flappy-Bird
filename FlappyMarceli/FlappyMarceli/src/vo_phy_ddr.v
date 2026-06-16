//=============================================================================================
//    Main contributors                                                                                         
//      - Adam £uczak         <mailto:aluczak@multimedia.edu.pl>                
//      - Jakub Siast         <mailto:jsiast@multimedia.edu.pl>     
//=============================================================================================
`default_nettype none
//-----------------------------------------------------------------------------
`timescale 1ns / 1ns
//=============================================================================
module vo_phy_ddr
(
input  wire         i_phy_clk0,
input  wire         i_phy_clk90,
input  wire			i_phy_clk180,
input  wire         i_phy_rst0,
input  wire         i_phy_rst90,

input  wire         i_phy_hsync,
input  wire         i_phy_vsync,
input  wire         i_phy_de,
input  wire   [7:0] i_phy_red,
input  wire   [7:0] i_phy_green,
input  wire   [7:0] i_phy_blue,

output wire         o_pclk_pin,
output wire         o_hsync_pin,
output wire         o_vsync_pin,
output wire         o_de_pin,
output wire  [11:0] o_data_pin 
);                 
//=============================================================================
// parameters
//=============================================================================

//=============================================================================
// local variables
//=============================================================================
reg        buff_hsync;
reg        buff_vsync;
reg        buff_de;
reg [23:0] buff_rgb;
//=============================================================================
// input buffer
//=============================================================================
always@(posedge i_phy_clk0)
 begin
	buff_hsync 	  <=  i_phy_hsync;
	buff_vsync 	  <=  i_phy_vsync;
	buff_de       <=  i_phy_de; 
  buff_rgb      <= {i_phy_red,i_phy_green,i_phy_blue};
 end
//=============================================================================
// SDR to DDR 
//=============================================================================
generate
  genvar i;
  
  for(i=0; i<12; i=i+1)
    begin : DATA
	  ddr ddr(	      .clkop(i_phy_clk0),
		  .clkos(i_phy_clk90),
		  .clkout(),
		  .reset(i_phy_rst0),
		  .sclk(),
		  .dataout({buff_rgb[i], buff_rgb[12+i]}),
		  .dout(o_data_pin[i]));
    end

    begin : HSYNC
	   ddr ddr(	      
	      .clkop(i_phy_clk0),
		  .clkos(i_phy_clk90),
		  .clkout(),
		  .reset(i_phy_rst0),
		  .sclk(),
		  .dataout({buff_hsync, buff_hsync}),
		  .dout(o_hsync_pin));
    end
    
    begin : VSYNC
	   ddr ddr(	      
	      .clkop(i_phy_clk0),
		  .clkos(i_phy_clk90),
		  .clkout(),
		  .reset(i_phy_rst0),
		  .sclk(),
		  .dataout({buff_vsync, buff_vsync}),
		  .dout(o_vsync_pin));
    end
    
    begin : DE
	   ddr ddr(	      
	      .clkop(i_phy_clk0),
		  .clkos(i_phy_clk90),
		  .clkout(),
		  .reset(i_phy_rst0),
		  .sclk(),
		  .dataout({buff_de, buff_de}),
		  .dout(o_de_pin));
    end

    begin : PCLK
	  ddr ddr(	      
	      .clkop(i_phy_clk90),
		  .clkos(i_phy_clk180),
		  .clkout(),
		  .reset(i_phy_rst0),
		  .sclk(),
		  .dataout({1'b1, 1'b0}),
		  .dout(o_pclk_pin));
    end
    
endgenerate
//=============================================================================
endmodule
