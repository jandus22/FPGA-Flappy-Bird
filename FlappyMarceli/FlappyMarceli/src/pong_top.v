module pong_top(
  input wire          CLK,  // CLK 50 MHz
  input wire          nRST, // Active low reset
  
  output wire [3:0]   LED,
  
  output wire         VID_DDR_PCLK,  // 
  output wire         VID_DDR_HSYNC, //
  output wire         VID_DDR_VSYNC, //
  output wire         VID_DDR_DE,    //
  output wire  [11:0] VID_DDR_DAT,   //
  
  inout wire          I2C_C,
  inout wire          I2C_D,
                      
  input wire          EncA_QA,
  input wire          EncA_QB,
  input wire          EncB_QA,
  input wire          EncB_QB
  );
  
  //---------------------------------------
  // Generacja sygna³u resetu
  //---------------------------------------
  wire RST;
  assign RST = ~nRST;
  
  //---------------------------------------
  // Generacja potrzebnych sygnalow zegarowych
  //---------------------------------------
  wire CLK75_0;
  wire CLK75_90;
  wire CLK75_180;
  // PLL 
  // Create 75MHz clock from the input 50MHz clock
  // 3 clocks with 0, 90 and 180 deg. phase shift are generated
  pll_75mhz pong_pll(.CLKI(CLK), .CLKOP(CLK75_0), .CLKOS(CLK75_90), .CLKOS2(CLK75_180));
  
  //---------------------------------------

  wire       VID_HSYNC;
  wire       VID_VSYNC;
  wire       VID_DE;
  wire [7:0] VID_RED;
  wire [7:0] VID_GREEN;
  wire [7:0] VID_BLUE;
  wire       VID_HSYNC_d;
  wire       VID_VSYNC_d;
  wire       VID_DE_d;
  
  //---------------------------------------
  // VESA signal generator
  //---------------------------------------
  wire [10:0] x_hcnt;
  wire [10:0] x_vcnt;
  
  vga_sync_gen pong_vga_sync_gen (
    .CLK (CLK75_0),
    .RST (RST),
    
    // output ports
    .GEN_ACTIVE    (VID_DE),        // [ 0:0]
    .GEN_RGB       (),              // [23:0] TEST PATERN OUTPUT

    .GEN_HSYNC     (),              // [ 0:0] HORIZONTAL SYNCHRONIZATION  
    .GEN_HSYNCP    (VID_HSYNC),     // [ 0:0] HORIZONTAL SYNCHRONIZATION (POLARITY)
    .GEN_HCNT      (x_hcnt),        // [10:0] PIXEL IN LINE ID

    .GEN_VSYNC     (),              // [ 0:0] VERTICAL SYNCHRONIZATION
    .GEN_VSYNCP    (VID_VSYNC),     // [ 0:0] VERTICAL SYNCHRONIZATION (POLARITY)
    .GEN_VCNT      (x_vcnt),        // [10:0] LINE IN FRAME ID

    // Parametry H
    .H_ACTIVE      (11'd1280),      // [10:0] FRAME WIDTH
    .H_FRONT_PORCH (11'd64),        // [10:0] VESA BLANKING PERIOD PARAMETER
    .H_BACK_PORCH  (11'd192),       // [10:0] VESA BLANKING PERIOD PARAMETER
    .H_SYNC        (11'd128),       // [10:0] VESA BLANKING PERIOD PARAMETER
    .H_SYNC_POL    (1'd0),          // [ 0:0] SYNCHRONIZATION SIGNAL POLARIZATION 0(-), 1(+)

    // Parametry V
    .V_ACTIVE      (11'd720),       // [10:0] FRAME HEIGHT
    .V_FRONT_PORCH (11'd3),         // [10:0] VESA BLANKING PERIOD PARAMETER
    .V_BACK_PORCH  (11'd20),        // [10:0] VESA BLANKING PERIOD PARAMETER
    .V_SYNC        (11'd5),         // [10:0] VESA BLANKING PERIOD PARAMETER
    .V_SYNC_POL    (1'd0)           // [ 0:0] SYNCHRONIZATION SIGNAL POLARIZATION 0(-), 1(+)
  );
  
  //---------------------------------------
  // Delay HSYNC, VSYNC, DE
  //---------------------------------------
  localparam CTRL_DELAY = 3;
  delay #(.D(CTRL_DELAY)) del1 (.CLK(CLK75_0), .I(   VID_DE), .O(   VID_DE_d));
  delay #(.D(CTRL_DELAY)) del2 (.CLK(CLK75_0), .I(VID_HSYNC), .O(VID_HSYNC_d));
  delay #(.D(CTRL_DELAY)) del3 (.CLK(CLK75_0), .I(VID_VSYNC), .O(VID_VSYNC_d));
  //---------------------------------------
  // PONG game
  //---------------------------------------
  pong_main 
  #(
    .SCR_W  (1280),
    .SCR_H  ( 720)
  )
  my_pong_inst
  (
    .CLK    (CLK75_0),   // 75 MHz clock signal
    .RST    (RST),       // active high reset
    
    .H_CNT  (x_hcnt),    // input horizontal pixel pointer 
    .V_CNT  (x_vcnt),    // input vertical   pixel pointer
    
    .RED    (VID_RED),   // generated value for pixel (x_hcnt, x_vcnt)
    .GREEN  (VID_GREEN), // generated value for pixel (x_hcnt, x_vcnt)
    .BLUE   (VID_BLUE),  // generated value for pixel (x_hcnt, x_vcnt)
    
    .EncA_QA(EncA_QA),   // encoder A input
    .EncA_QB(EncA_QB),   // encoder A input
    .EncB_QA(EncB_QA),   // encoder B input
    .EncB_QB(EncB_QB),   // encoder B input
    
    .LED    (LED)        // general purpose LED output
  );
      
  //---------------------------------------
  // VESA signals SDR->DDR converter 
  //---------------------------------------
  
  vo_phy_ddr pong_vo_phy_ddr(
    .i_phy_clk0     (CLK75_0),
    .i_phy_clk90    (CLK75_90),
    .i_phy_clk180   (CLK75_180),
    .i_phy_rst0     (RST),
    .i_phy_rst90    (RST),
    
    .i_phy_hsync    (VID_HSYNC_d),
    .i_phy_vsync    (VID_VSYNC_d),
    .i_phy_de       (VID_DE_d),
    .i_phy_red      (VID_RED),
    .i_phy_green    (VID_GREEN),
    .i_phy_blue     (VID_BLUE),
    
    .o_pclk_pin     (VID_DDR_PCLK),
    .o_hsync_pin    (VID_DDR_HSYNC),
    .o_vsync_pin    (VID_DDR_VSYNC),
    .o_de_pin       (VID_DDR_DE),
    .o_data_pin     (VID_DDR_DAT)
  );

  //---------------------------------------
  // Konfigurator ukladu TFP410
  //---------------------------------------
  hdmi_i2c_cfg pong_hdmi_i2c_cfg(
    .CLK            (CLK75_0),
    .RST            (RST),       
    .I2C_C          (I2C_C),
    .I2C_D          (I2C_D)
  );
  //---------------------------------------
endmodule