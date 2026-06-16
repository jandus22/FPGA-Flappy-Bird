//=============================================================================================
//    Main contributors
//      - Adam Luczak         <mailto:aluczak@multimedia.edu.pl>
//=============================================================================================
`default_nettype none
//---------------------------------------------------------------------------------------------
`timescale 1ns / 1ns                            
//=============================================================================================
// mode:
// 0x0 : start
// 0x1 : write byte
// 0x2 : read byte (not last)
// 0x3 : read last byte
// 0x7 : stop
//=============================================================================================
module dev_i2c_phy
(
input  wire	        clk,
input  wire         rst,   

input  wire         i_run,
output wire         o_run,

input  wire         i_stb,
input  wire  [2:0]  i_mode,
input  wire  [7:0]  i_data,
output wire         i_ack,

output wire         o_val,
output wire  [7:0]  o_data,
output wire         o_err,

// I2C bus
inout  wire         i2c_sda,
output wire         i2c_scl,

input  wire  [15:0] cfg_clk_div 
);
//==============================================================================================
// local param
//==============================================================================================
//==============================================================================================
// variables
//==============================================================================================   
integer     state;         
reg         run;      
//---------------------------------------------------------------------------------------------- 
wire        tick;
//---------------------------------------------------------------------------------------------- 
reg   [8:0] data_reg;
reg   [3:0] data_cnt;
reg   [2:0] data_mode;
//---------------------------------------------------------------------------------------------- 
wire        bs_stb;
reg         bs_dir;
reg   [1:0] bs_bit;
wire        bs_ack;
wire        bs_rdy;
//---------------------------------------------------------------------------------------------- 
wire        br_val;  
wire        br_lde;
wire        br_bit;         
//---------------------------------------------------------------------------------------------- 
reg         din_val;
reg         din_err;
reg   [7:0] din_data;
//==============================================================================================
// Frame  generator for D2R ring
//==============================================================================================
wire          f_go                     =                                         i_stb & bs_rdy;
//---------------------------------------------------------------------------------------------- 
wire          f_start                  =                                          i_mode == 'd0;
wire          f_wrb                    =                                          i_mode == 'd1;         
wire          f_rdb                    =                        i_mode == 'd2 ||  i_mode == 'd3;         
wire          f_stop                   =                                          i_mode == 'd7;
//---------------------------------------------------------------------------------------------- 
wire          f_bit_ack                =                                                 bs_ack;
wire          f_bit_rdy                =                                                 bs_rdy;
wire          f_bit_run                =                                                !bs_rdy;
wire          f_bit_sample             =                                                !bs_rdy;
//---------------------------------------------------------------------------------------------- 
wire          f_byte_rdy               =                                            data_cnt[3];
//---------------------------------------------------------------------------------------------- 
always@(posedge clk or posedge rst)
  if(rst)                       state <= 0;
  else case(state)                                                                             
  0  :        if(f_go)          state <= 1; 
  // main loop                                                                                     
  1  :                          state <= 2;  // set flags
  2  :        if(f_start)       state <= 10; // go to byte rd/wr
        else  if(f_stop)        state <= 20; // go to byte rd/wr 
        else  if(f_wrb)         state <= 50; // go to byte rd/wr 
        else  if(f_rdb)         state <= 50; // go to byte rd/wr 
  // start
  10 :                          state <= 11; // load mode & dir
  11 :        if(f_bit_rdy)     state <= 12; //  
  12 :        if(f_bit_ack)     state <= 13; // load bit
  13 :        if(f_bit_run)     state <=  0; // 
  // stop
  20 :                          state <= 21; // load mode & dir
  21 :        if(f_bit_rdy)     state <= 22; //  
  22 :        if(f_bit_ack)     state <= 23; // load bit
  23 :        if(f_bit_run)     state <=  0; // 
  // main loop of byte send/receive
  50 :        if(f_bit_rdy)     state <= 51; // 
  51 :                          state <= 52; // load mode & dir 
  52 :        if(f_bit_ack)     state <= 53; // load bit
  53 :        if(f_bit_run)     state <= 54; //  
  54 :        if(f_bit_sample)  state <= 55; //    
  55 :        if(f_bit_rdy)     state <= 56; //    
  56 :        if(f_byte_rdy)    state <= 57; //  
        else                    state <= 50; 
  57 :                          state <= 70; // go to "ACK" bit
  // read write ACK bit
  70 :        if(tick)          state <= 71; // empty slot 0
  71 :        if(tick)          state <= 72; // empty slot 1
  72 :        if(tick)          state <= 73; // empty slot 2
  73 :        if(tick)          state <= 74; // empty slot 3
  74 :        if(f_bit_rdy)     state <= 75; // 
  75 :                          state <= 76; // load mode & dir 
  76 :        if(f_bit_ack)     state <= 77; // load bit
  77 :        if(f_bit_run)     state <= 78; //  
  78 :        if(f_bit_sample)  state <= 79; //  
  79 :        if(f_bit_rdy)     state <= 80; //  
  80 :        if(tick)          state <= 81; // empty slot 0
  81 :        if(tick)          state <= 82; // empty slot 1
  82 :        if(tick)          state <= 83; // empty slot 2
  83 :        if(tick)          state <= 84; // empty slot 3
  84 :                          state <=  0; // send byte 
  endcase
//==============================================================================================
// control flags
//==============================================================================================
assign        i_ack                    =                                             state == 2;   
//---------------------------------------------------------------------------------------------- 
wire          f_load                   =                                             state == 2;   
wire          f_she                    =                                                 br_lde;   
//----------------------------------------------------------------------------------------------           
wire          f_ld_start                =                                           state == 10;             
wire          f_ld_stop                 =                                           state == 20;
wire          f_ld_wrb                  =      (                   data_mode==1) && state == 51;
wire          f_ld_rdb                  =      ( data_mode == 3 || data_mode==2) && state == 51;
wire          f_ld_wack                 =      ( data_mode == 3 || data_mode==2) && state == 75;
wire          f_ld_rack                 =      (                   data_mode==1) && state == 75;
//---------------------------------------------------------------------------------------------- 
wire          f_out_clr                 =                                           state ==  2;   
wire          f_out_lde                 =                                           state == 84;   
//==============================================================================================
// scaller
//==============================================================================================
dev_i2c_phy_scaler scaler
(
.i_clk        (clk),
.i_rst        (rst),   

.o_tick       (tick),

.cfg_clk_div  (cfg_clk_div) 
);
//==============================================================================================
// BYTE SENDER
//==============================================================================================                
always@(posedge clk or posedge rst)
  if(rst)                   data_reg    <=                                        'b1111_1111_1;
  else if(f_load)           data_reg    <=                                   {i_data,i_mode==3};
  else if(f_she)            data_reg    <=                               {data_reg[7:0],br_bit};
//---------------------------------------------------------------------------------------------- 
// bit counter
//---------------------------------------------------------------------------------------------- 
always@(posedge clk or posedge rst)                                                                             
  if(rst)                   data_cnt    <=                                                  'd0;                
  else if(f_load)           data_cnt    <=                                                  'd7;
  else if(f_she)            data_cnt    <=                                       data_cnt - 'd1;
//---------------------------------------------------------------------------------------------- 
// data mode
//---------------------------------------------------------------------------------------------- 
always@(posedge clk or posedge rst)                                                                             
  if(rst)                   data_mode   <=                                                  'd0;                
  else if(f_load)           data_mode   <=                                               i_mode;
//==============================================================================================
// BIT SENDER CTRL
//==============================================================================================
always@(posedge clk or posedge rst)
  if(rst)                   bs_dir   <=                                                    1'd1;
  else if(f_ld_start)       bs_dir   <=                                                    1'd1;
  else if(f_ld_wrb)         bs_dir   <=                                                    1'd1;
  else if(f_ld_rdb)         bs_dir   <=                                                    1'd0;
  else if(f_ld_stop)        bs_dir   <=                                                    1'd1; 
  else if(f_ld_wack)        bs_dir   <=                                                    1'd1;     
  else if(f_ld_rack)        bs_dir   <=                                                    1'd0;
//---------------------------------------------------------------------------------------------- 
always@(posedge clk or posedge rst)
  if(rst)                   bs_bit   <=                                                    2'd0;
  else if(f_ld_start)       bs_bit   <=                                                    2'd2;
  else if(f_ld_wrb)         bs_bit   <=                                      {1'b0,data_reg[8]};
  else if(f_ld_rdb)         bs_bit   <=                                                    2'd0;
  else if(f_ld_stop)        bs_bit   <=                                                    2'd3;
  else if(f_ld_wack)        bs_bit   <=                                      {1'b0,data_reg[8]};     
  else if(f_ld_rack)        bs_bit   <=                                                    2'd0;
//---------------------------------------------------------------------------------------------- 
assign                      bs_stb    =        state==76 || state==12 || state==22 || state==52;
//==============================================================================================
// BIT SENDER
//==============================================================================================
dev_i2c_phy_bit bit_sender
(
.clk          (clk),
.tick         (tick),
.rst          (rst),   

.i_stb        (bs_stb),
.i_dir        (bs_dir),
.i_bit        (bs_bit),
.i_ack        (bs_ack),
.i_rdy        (bs_rdy),

.o_val        (br_val),
.o_lde        (br_lde),
.o_bit        (br_bit),

.i2c_sda      (i2c_sda),
.i2c_scl      (i2c_scl)
);
//==============================================================================================        
// data output 
//==============================================================================================
always@(posedge clk or posedge rst)                                                                             
  if(rst)                   din_val     <=                                                 1'b0;
  else if(f_out_clr)        din_val     <=                                                 1'b0;
  else if(f_out_lde)        din_val     <=                                                 1'b1;
//---------------------------------------------------------------------------------------------- 
always@(posedge clk or posedge rst)                                                                             
  if(rst)                   din_err     <=                                                 1'b0;                
  else if(f_out_clr)        din_err     <=                                                 1'b0;
  else if(f_out_lde)        din_err     <=                        (data_mode==3) ^ data_reg [0];
//---------------------------------------------------------------------------------------------- 
always@(posedge clk or posedge rst)                                                                             
  if(rst)                   din_data    <=                                                 1'b0;                
  else if(f_out_clr)        din_data    <=                                                 1'b0;
  else if(f_out_lde)        din_data    <=                                       data_reg [8:1];
//==============================================================================================
assign                      o_val        =                                              din_val; 
assign                      o_err        =                                              din_err; 
assign                      o_data       =                                             din_data;
//==============================================================================================
endmodule









