module delay
#(
  parameter W = 1,
  parameter D = 1
)
(
  input  wire         CLK,
  
  input  wire [W-1:0] I,
  output wire [W-1:0] O
);      
  genvar i;
  generate
    if(D == 0) 
      begin
        assign O = I;
      end
    else
      begin
        reg [W-1:0] d [D-1:0];   
          for(i = D-1; i>=1; i=i-1)
          begin: del_stage
            always@(posedge CLK) d[i] <= d[i-1];
          end       
        always@(posedge CLK) d[0] <= I;
        assign O = d[D-1];
      end      
  endgenerate

endmodule
