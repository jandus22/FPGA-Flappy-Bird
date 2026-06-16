module hdmi_i2c_cfg
(
 input wire CLK,
 input wire RST,
 
 inout wire I2C_C,
 inout wire I2C_D
);

wire        x_run_stb;
wire        x_run_ack;
wire        x_stb;
wire  [2:0] x_mode;
wire  [7:0] x_data;
wire        x_ack;

wire        x_i_val;
wire  [7:0] x_i_data;
wire        x_i_err;

reg [31:0] cfg_state;
reg [31:0] cfg_wait;
reg  [7:0] cfg_addr;
reg [11:0] cfg_data;

always@(posedge CLK)
 case(cfg_addr)
 0: cfg_data <= 12'h0_00; // start
 1: cfg_data <= 12'h1_70;
 2: cfg_data <= 12'h1_08;
 3: cfg_data <= 12'h1_33;
 4: cfg_data <= 12'h7_00; // stop
 
 5: cfg_data <= 12'h0_00; // start //$S00$W70$W0A$W8E$P00
 6: cfg_data <= 12'h1_70;
 7: cfg_data <= 12'h1_0A;
 8: cfg_data <= 12'h1_84;
 9: cfg_data <= 12'h7_00; // stop
 
10: cfg_data <= 12'hF_FF; // eoc
 endcase
always@(posedge CLK or posedge RST)
 if(RST)  					cfg_wait <= 100000;
 else if(!cfg_wait[31])   	cfg_wait <= cfg_wait - 1;

always@(posedge CLK or posedge RST)
 if(RST) 
		begin
			cfg_addr  <= 0;
			cfg_state <= 0;
		end
 else case(cfg_state)
 0:
	begin
		if(cfg_wait[31]) cfg_state <= 1;
		else             cfg_state <= 0;	end
 1: // if(eoc)
	begin
		if(cfg_data != 12'hF_FF) cfg_state <= 2;	
		else             		 cfg_state <= 1;	
	end
 2: // stb > ack
	begin
		if(x_ack)	cfg_state <= 3;		else        cfg_state <= 2;
	end
 3: // inc addr
	begin
		cfg_addr  <=  cfg_addr + 1;
		cfg_state <= 4;
	end
 4: // wait 1T
	begin
		cfg_state <= 1;
	end
 endcase 


assign  x_stb	=	cfg_state==2; 
assign	x_mode	= 	cfg_data[11: 8];
assign 	x_data	= 	cfg_data[ 7: 0];

dev_i2c_phy i2c_phy1
(
.clk            (CLK),
.rst            (RST),   

.i_run          (x_run_stb),
.o_run          (x_run_ack),

.i_stb          (x_stb),
.i_mode         (x_mode),
.i_data         (x_data),
.i_ack          (x_ack),

.o_val          (x_i_val),
.o_data         (x_i_data),
.o_err          (x_i_err),

.i2c_sda        (I2C_D),
.i2c_scl        (I2C_C),

.cfg_clk_div    (16'd1000) 
);


endmodule