module pong_main
#(
  parameter SCR_W = 64,
  parameter SCR_H = 40,
  parameter BIRD_W = 4,    // Szerokość ptaka
  parameter BIRD_H = 3,    // Wysokość ptaka
  parameter PIPE_W = 6,    // Szerokość rury
  parameter GAP_H = 14     // Przerwa między rurami (prześwit)
)
(
	input wire        CLK,
	input wire        RST,
	input wire [10:0] H_CNT,
	input wire [10:0] V_CNT,
	input wire        EncA_QA, EncA_QB, EncB_QA, EncB_QB,
	output reg [7:0]  RED, GREEN, BLUE,
	output wire [3:0] LED
);

  // Zafixowana pozycja X ptaka na ekranie (stoi w miejscu, rury lecą w lewo)
  wire [10:0] BIRD_X = SCR_W / 3;

  // LFSR - generator liczb pseudolosowych do ustalania wysokości rur
  reg [15:0] lfsr;
  wire lfsr_feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
  always @(posedge CLK or posedge RST) begin
    if (RST) lfsr <= 16'hACE1;
    else     lfsr <= {lfsr[14:0], lfsr_feedback};
  end

  reg [31:0] heartbeat;
  always@(posedge CLK or posedge RST)
    if(RST) heartbeat <= 0;
    else    heartbeat <= heartbeat + 1;
  assign LED = heartbeat[26:23];

  // ZEGAR GRY - przyspiesza z poziomem
  reg [3:0] level;
  wire [31:0] current_speed = 2500 - (level * 200); // Do testów na ekranie zmień na 2500000 itp.
  reg [31:0] tick_counter;
  wire game_tick = (tick_counter >= current_speed);

  always @(posedge CLK or posedge RST) begin
    if (RST) tick_counter <= 0;
    else if (game_tick) tick_counter <= 0;
    else tick_counter <= tick_counter + 1;
  end

  // OBSŁUGA ENKODERA (SKOK)
  reg EncA_QA_d, EncA_QA_dd, EncA_QB_d;
  always @(posedge CLK) begin
    EncA_QA_d  <= EncA_QA;
    EncA_QA_dd <= EncA_QA_d; 
    EncA_QB_d  <= EncA_QB;
  end

  wire enc_tick = (EncA_QA_dd == 1'b1 && EncA_QA_d == 1'b0); 
  // Ruch w prawo jako skok (możesz zmienić EncA_QB_d na 1'b1 jeśli ma być w lewo)
  wire jump = enc_tick && (EncA_QB_d == 1'b0);

  // ZMIENNE STANU GRY
  reg [10:0] bird_y;           // Wysokość ptaka
  reg [10:0] pipe_x [0:2];     // Pozycje X trzech rur
  reg [10:0] pipe_gap_y [0:2]; // Wysokość początkowa dziury między rurami
  reg [3:0] score_thousands, score_hundreds, score_tens, score_ones;
  reg game_over; 

  // DETEKCJA KOLIZJI
  wire crash_ground = (bird_y + BIRD_H >= SCR_H);
  
  wire crash_pipe0 = (BIRD_X + BIRD_W > pipe_x[0]) && (BIRD_X < pipe_x[0] + PIPE_W) && 
                     ((bird_y < pipe_gap_y[0]) || (bird_y + BIRD_H > pipe_gap_y[0] + GAP_H));
                     
  wire crash_pipe1 = (BIRD_X + BIRD_W > pipe_x[1]) && (BIRD_X < pipe_x[1] + PIPE_W) && 
                     ((bird_y < pipe_gap_y[1]) || (bird_y + BIRD_H > pipe_gap_y[1] + GAP_H));
                     
  wire crash_pipe2 = (BIRD_X + BIRD_W > pipe_x[2]) && (BIRD_X < pipe_x[2] + PIPE_W) && 
                     ((bird_y < pipe_gap_y[2]) || (bird_y + BIRD_H > pipe_gap_y[2] + GAP_H));

  wire crash = crash_ground | crash_pipe0 | crash_pipe1 | crash_pipe2;

  integer i;
  always @(posedge CLK or posedge RST) begin
    if(RST) begin
      bird_y <= SCR_H/2;
      pipe_x[0] <= SCR_W;      pipe_gap_y[0] <= 10;
      pipe_x[1] <= SCR_W + 25; pipe_gap_y[1] <= 15;
      pipe_x[2] <= SCR_W + 50; pipe_gap_y[2] <= 8;
      
      score_thousands <= 0; score_hundreds <= 0;
      score_tens <= 0; score_ones <= 0;
      level <= 0;
      game_over <= 0;
    end
    else if (game_over) begin
      if (jump) begin // Reset gry po skoku
        bird_y <= SCR_H/2;
        pipe_x[0] <= SCR_W;      pipe_gap_y[0] <= 10;
        pipe_x[1] <= SCR_W + 25; pipe_gap_y[1] <= 15;
        pipe_x[2] <= SCR_W + 50; pipe_gap_y[2] <= 8;
        score_thousands <= 0; score_hundreds <= 0;
        score_tens <= 0; score_ones <= 0;
        level <= 0;
        game_over <= 0;
      end
    end
    else begin
      if (crash) begin
        game_over <= 1;
      end 
      else begin
        // SKOK PTAKA (Natychmiastowa reakcja)
        if (jump && bird_y > 3) begin
            bird_y <= bird_y - 6; // Podrzuca ptaka do góry o 6 pikseli
        end

        // GRAWITACJA I RUCH RUR
        if(game_tick) begin
          // Opadanie (grawitacja)
          if (bird_y < SCR_H - BIRD_H) bird_y <= bird_y + 1;

          // Przesuwanie rur i punktacja
          for(i=0; i<3; i=i+1) begin
            if (pipe_x[i] == 0) begin
              // Rura wraca na początek ekranu, przesunięta o odpowiedni bufor
              pipe_x[i] <= SCR_W + 10; 
              // Losowa pozycja prześwitu. Używamy 4 bitów LFSR (0-15) + margines 5.
              // To daje nam prześwit zaczynający się w Y między 5 a 20.
              pipe_gap_y[i] <= 5 + lfsr[(i*4)+3 -: 4]; 
            end else begin
              pipe_x[i] <= pipe_x[i] - 1;
            end
            
            // NALICZANIE PUNKTÓW, GDY RURA MIJA PTAKA
            if (pipe_x[i] == BIRD_X) begin
              if (score_ones == 9) begin
                score_ones <= 0;
                if (level < 9) level <= level + 1;
                if (score_tens == 9) begin
                  score_tens <= 0;
                  if (score_hundreds == 9) begin
                    score_hundreds <= 0;
                    if (score_thousands != 9) score_thousands <= score_thousands + 1;
                  end else score_hundreds <= score_hundreds + 1;
                end else score_tens <= score_tens + 1;
              end else score_ones <= score_ones + 1;
            end
          end
        end
      end
    end
  end

  //-----------------------------------------
  // RENDEROWANIE TEKSTU I GRAFIKI UI (zostaje z oryginału)
  //-----------------------------------------
  wire is_score_thou = (H_CNT >= 48 && H_CNT <= 50 && V_CNT >= 1 && V_CNT <= 5);
  wire is_score_hund = (H_CNT >= 52 && H_CNT <= 54 && V_CNT >= 1 && V_CNT <= 5);
  wire is_score_tens = (H_CNT >= 56 && H_CNT <= 58 && V_CNT >= 1 && V_CNT <= 5);
  wire is_score_ones = (H_CNT >= 60 && H_CNT <= 62 && V_CNT >= 1 && V_CNT <= 5);
  wire is_char_L      = (H_CNT >= 2 && H_CNT <= 4 && V_CNT >= 1 && V_CNT <= 5);
  wire is_level_digit = (H_CNT >= 6 && H_CNT <= 8 && V_CNT >= 1 && V_CNT <= 5);
  wire is_text_area = is_score_thou | is_score_hund | is_score_tens | is_score_ones | is_char_L | is_level_digit;

  wire [3:0] cur_digit = is_score_thou  ? score_thousands :
                         is_score_hund  ? score_hundreds  :
                         is_score_tens  ? score_tens      :
                         is_score_ones  ? score_ones      :
                         is_char_L      ? 4'd10           : 
                         is_level_digit ? level           : 4'd0;

  reg [14:0] digit_rom;
  always @(*) begin
    case(cur_digit)
      4'd0: digit_rom = 15'b111_101_101_101_111;
      4'd1: digit_rom = 15'b010_110_010_010_111;
      4'd2: digit_rom = 15'b111_001_111_100_111;
      4'd3: digit_rom = 15'b111_001_111_001_111;
      4'd4: digit_rom = 15'b101_101_111_001_001;
      4'd5: digit_rom = 15'b111_100_111_001_111;
      4'd6: digit_rom = 15'b111_100_111_101_111;
      4'd7: digit_rom = 15'b111_001_001_001_001;
      4'd8: digit_rom = 15'b111_101_111_101_111;
      4'd9: digit_rom = 15'b111_101_111_001_111;
      4'd10: digit_rom= 15'b100_100_100_100_111; // Litera 'L'
      default: digit_rom = 15'b000_000_000_000_000;
    endcase
  end

  wire [2:0] char_x = is_score_thou  ? (H_CNT - 48) :
                      is_score_hund  ? (H_CNT - 52) :
                      is_score_tens  ? (H_CNT - 56) :
                      is_score_ones  ? (H_CNT - 60) :
                      is_char_L      ? (H_CNT - 2)  :
                      is_level_digit ? (H_CNT - 6)  : 3'd0;

  wire [2:0] char_y = V_CNT - 1;
  wire [4:0] bit_idx = 14 - (char_y * 3 + char_x); 
  
  reg draw_text_pixel;
  always @(*) begin
    draw_text_pixel = 1'b0;
    if (is_text_area) begin
      if (bit_idx < 15) draw_text_pixel = digit_rom[bit_idx];
    end
  end

  //-----------------------------------------
  // RYSOWANIE PIKSELI
  //-----------------------------------------
  wire blink_state = heartbeat[16]; 
  wire show_score = (!game_over) || blink_state;

  always @(*) begin
    // DOMYŚLNE TŁO - Błękitne niebo
    RED = 8'h60; GREEN = 8'hA0; BLUE = 8'hFF;
    
    // RYSOWANIE RUR
    for(i=0; i<3; i=i+1) begin
      if(H_CNT >= pipe_x[i] && H_CNT < pipe_x[i] + PIPE_W) begin
        // Rysuj na zielono, o ile NIE jesteśmy w dziurze (prześwicie)
        if (V_CNT < pipe_gap_y[i] || V_CNT > pipe_gap_y[i] + GAP_H) begin
          RED = 8'h00; GREEN = 8'hC0; BLUE = 8'h00; // Zielony kolor rury
        end
      end
    end

    // RYSOWANIE PTAKA
    if(H_CNT >= BIRD_X && H_CNT < BIRD_X + BIRD_W && V_CNT >= bird_y && V_CNT < bird_y + BIRD_H) begin
      if (crash) begin
        // Jeśli ptak ginie, rysuj na czerwono
        RED = 8'hFF; GREEN = 8'h00; BLUE = 8'h00; 
      end else begin
        // Żółty ptaszek, z lekkim pomarańczowym odcieniem
        RED = 8'hFF; GREEN = 8'hE0; BLUE = 8'h00;
      end
    end

    // RYSOWANIE UI (Wynik i Poziom) na biało
    if (draw_text_pixel && show_score) begin
        RED = 8'hFF; GREEN = 8'hFF; BLUE = 8'hFF;
    end
  end
endmodule