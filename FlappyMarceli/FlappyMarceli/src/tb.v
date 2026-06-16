`timescale 1ns / 100ps
`default_nettype none

module tb();
	
  localparam pixel = 15;
  localparam [10:0] SCR_W = 64; 
  localparam [10:0] SCR_H = 40; 
  integer file, i;

  initial begin
    file = $fopen("size.txt", "w+");
    $fwrite(file, "%d\n%d\n%d\n", SCR_W, SCR_H, pixel);
    $fclose(file);
  end

  reg RST;
  initial begin RST = 1'b1; #10 RST = 1'b0; end 

  reg CLK75_0;
  initial CLK75_0 <= 0;
  always #6.6 CLK75_0 <= ~CLK75_0; 
   
  reg EncA_QA, EncA_QB, EncB_QA, EncB_QB;
  wire [7:0] VID_RED, VID_GREEN, VID_BLUE; 
  wire [3:0] LED;
  
  // W�asny, niezawodny generator ekranu (zast�puje zepsuty vga_sync_gen)
  reg [10:0] x_hcnt_d = 0;
  reg [10:0] x_vcnt_d = 0;
  wire VID_DE_d = (x_hcnt_d < SCR_W) && (x_vcnt_d < SCR_H);

  always @(posedge CLK75_0) begin
    if (RST) begin
      x_hcnt_d <= 0; 
      x_vcnt_d <= 0;
    end else begin
      if (x_hcnt_d == SCR_W + 5) begin // Margines blankingu
        x_hcnt_d <= 0;
        if (x_vcnt_d == SCR_H + 2) x_vcnt_d <= 0;
        else x_vcnt_d <= x_vcnt_d + 1;
      end else begin
        x_hcnt_d <= x_hcnt_d + 1;
      end
    end
  end

  pong_main #( .SCR_W(SCR_W), .SCR_H(SCR_H) ) my_pong_inst (
    .CLK(CLK75_0), .RST(RST),
    .H_CNT(x_hcnt_d), .V_CNT(x_vcnt_d), 
    .RED(VID_RED), .GREEN(VID_GREEN), .BLUE(VID_BLUE),  
    .EncA_QA(EncA_QA), .EncA_QB(EncA_QB), .EncB_QA(EncB_QA), .EncB_QB(EncB_QB), 
    .LED(LED)      
  );   

  // GHOST PLAYER 
initial begin
    // Stan początkowy - enkoder w spoczynku (zazwyczaj obie fazy są w jedynce)
    EncA_QA = 1; EncA_QB = 1; EncB_QA = 1; EncB_QB = 1;
    #1000000 EncB_QB = 0;
    // Dajemy ptakowi chwilę na opadnięcie po starcie symulacji
    forever begin
      #310000
      #100000 EncA_QA = 0; EncA_QB = 0; // <-- W tym momencie następuje JUMP!
      #20000 EncA_QA = 1;
      #100000 EncA_QA = 0;
      #20000 EncA_QA = 1;
      #100000 EncA_QA = 0;
      #20000 EncA_QA = 1;
      #100000 EncA_QA = 0;
      #20000 EncA_QA = 1;
      #100000 EncA_QA = 0;
      #20000 EncA_QA = 1;
      #100000 EncA_QA = 0;
      #20000 EncA_QA = 1;
      #100000 EncA_QA = 0;
      #20000 EncA_QA = 1;
      #200000 EncA_QA = 0;
      #20000 EncA_QA = 1;
      #500000 EncA_QA = 0;
      #20000 EncA_QA = 1;
      #100000 EncA_QA = 0;
      #20000 EncA_QA = 1;
      #100000 EncA_QA = 0;
      #10000 EncA_QA = 1;
      #200000 EncA_QA = 0;
      #20000 EncA_QA = 1;
      #200000 EncA_QA = 0;
      #20000 EncA_QA = 1;
      #100000 EncA_QA = 0;
      #10000 EncA_QA = 1;
      #100000 EncA_QA = 0;    
      #10000 EncA_QA = 1;
      #100000 EncA_QA = 0; 
      #10000 EncA_QA = 1;
      #100000 EncA_QA = 0; 
      #10000 EncA_QA = 1;
      #700000 EncA_QA = 0;
      #10000 EncA_QA = 1;
      #10000 EncA_QA = 0;
      #10000 EncA_QA = 1;
      #100000 EncA_QA = 0;
      #10000 EncA_QA = 1;
      #600000 EncA_QA = 0;     
      #10000 EncA_QA = 1;
      #10000 EncA_QA = 0;
      #10000 EncA_QA = 1;
      #60000 EncA_QA = 0;
      #10000 EncA_QA = 1;
      #200000 EncA_QA = 0;
      #100 EncA_QA = 1;
      #400000 EncA_QA = 0;
      #100 EncA_QA = 1;
      #1000 EncA_QA = 0;
      #100 EncA_QA = 1; 
      #200000 EncA_QA = 0;
      #100 EncA_QA = 1; 
      #300000 EncA_QA = 0; 
      #100 EncA_QA = 1;
      #300000 EncA_QA = 0;
      #100 EncA_QA = 1;
      #1000 EncA_QA = 0;
      #100 EncA_QA = 1;
      #1000 EncA_QA = 0;
      #100 EncA_QA = 1; 
      #300000 EncA_QA = 0; 
      #100 EncA_QA = 1; 
      #500000 EncA_QA = 0; 
      #100 EncA_QA = 1; 
      #40000 EncA_QA = 0; 
      #100 EncA_QA = 1; 
      #200000 EncA_QA = 0; 
      #100 EncA_QA = 1; 
      #10000 EncA_QA = 0; 
      #100 EncA_QA = 1; 
      #300000 EncA_QA = 0; 
      #100 EncA_QA = 1; 
      #200000 EncA_QA = 0; 
      #100 EncA_QA = 1; 
      #200000 EncA_QA = 0; 
      #100 EncA_QA = 1; 
      #20000 EncA_QA = 0; 
      #100 EncA_QA = 1; 
      #20000 EncA_QA = 0;
      #100 EncA_QA = 1; 
      #200000 EncA_QA = 0; 
      #100 EncA_QA = 1; 
      #500000 EncA_QA = 0; 
      #100 EncA_QA = 1; 
      #20000 EncA_QA = 0;
      #100 EncA_QA = 1; 
      #400000 EncA_QA = 0;
      #100 EncA_QA = 1;
      #300000 EncA_QA = 0; 
      #100 EncA_QA = 1;
      #1000000 EncA_QA = 0;
    end
    //#400000 EncA_QA = 0;      
    //forever begin
      // SYMULACJA POJEDYNCZEGO SKOKU
      // Nasz kod łapie skok, gdy QA zmienia się 1 -> 0, a QB to 0
      //#400000
      //#200000 EncA_QA = 0; EncA_QB = 0; // <-- W tym momencie następuje JUMP!
      //#20000 EncA_QA = 1;
      //#200000 EncA_QA = 0;
      //#20000 EncA_QA = 1;
      //#200000 EncA_QA = 0;
      //#20000 EncA_QA = 1;
      //#200000 EncA_QA = 0;
      //#20000 EncA_QA = 1;
      //#20000 EncA_QA = 0; EncA_QB = 1;
      //#200000 EncA_QA = 1; EncA_QB = 1; // Powrót do stabilnego stanu spoczynku
      
      // PAUZA NA OPADANIE (GRAWITACJA)
      // Jeśli w symulacji ptak uderza w sufit - ZWIĘKSZ ten czas (żeby rzadziej skakał).
      // Jeśli uderza w ziemię przed skokiem - ZMNIEJSZ ten czas (żeby częściej skakał).
      //#10000; 
    //end
  end

  //---------------------------------------
  // PAMI�� WIDEO I ZAPIS (Inteligentny przechwyt)
  //---------------------------------------
  reg[2:0] VIDMEM [0:SCR_W*SCR_H-1];   
  
  // W�asne liczniki tylko dla widocznych pikseli (ignoruj� "puste" linie VGA)
  reg [10:0] active_x;
  reg [10:0] active_y;

  always@(posedge CLK75_0 or posedge RST) begin
    if (RST) begin
      active_x <= 0;
      active_y <= 0;
    end 
    else if(VID_DE_d) begin
      // ZAPIS Z OBROTEM: Odwracamy o� Y (SCR_H - 1 - active_y) 
      // Dzi�ki temu SimVid wy�wietli obraz prawid�o (gracz na dole, punkty na g�rze!)
      VIDMEM[active_x + ((SCR_H - 1 - active_y) * SCR_W)] <= { |VID_RED, |VID_GREEN, |VID_BLUE };
      
      // Przesuwamy wska�nik tylko dla widocznych pikseli
      if (active_x == SCR_W - 1) begin
        active_x <= 0;
        if (active_y == SCR_H - 1) active_y <= 0;
        else active_y <= active_y + 1;
      end else begin
        active_x <= active_x + 1;
      end
    end
  end

  // ZAPIS CO KLATK�
  reg stb_wysw;
  always@(posedge CLK75_0 or posedge RST) begin
    if(RST) stb_wysw <= 0;
    else begin
      // Wyzwalamy zapis dok�adnie, gdy inteligentny licznik dotrze do ko�ca
      if (VID_DE_d && active_x == SCR_W - 1 && active_y == SCR_H - 1) stb_wysw <= 1;

      if (stb_wysw) begin
        file = $fopen("dane.txt", "w+"); 
        for (i = 0; i < SCR_W*SCR_H; i = i+1) begin
          if (VIDMEM[i] === 3'bx) $fwrite(file, "0\n"); 
          else $fwrite(file, "%d\n", VIDMEM[i]);
        end
        $fclose(file);
        stb_wysw <= 0;
      end	
    end
  end
endmodule