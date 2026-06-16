module pong_main
#(
  parameter SCR_W = 64,
  parameter SCR_H = 40,
  parameter BIRD_W = 4,    
  parameter BIRD_H = 3,    
  parameter PIPE_W = 6,    
  parameter GAP_H = 14     
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

  wire [10:0] BIRD_X = SCR_W / 3;

  // ----------------------------------------------------
  // MASZYNA STANÓW GRY
  // ----------------------------------------------------
  reg [1:0] state;
  localparam ST_MENU = 2'd0;
  localparam ST_PLAY = 2'd1;
  localparam ST_OVER = 2'd2;
  localparam ST_DEMO = 2'd3; // NOWY STAN: DEMO

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

  reg [3:0] level;
  wire [31:0] current_speed = 2500 - (level * 200); 
  reg [31:0] tick_counter;
  wire game_tick = (tick_counter >= current_speed);

  always @(posedge CLK or posedge RST) begin
    if (RST) tick_counter <= 0;
    else if (game_tick) tick_counter <= 0;
    else tick_counter <= tick_counter + 1;
  end

  // ----------------------------------------------------
  // OBSŁUGA WEJŚĆ (ENKODERY I PRZYCISKI)
  // ----------------------------------------------------
  reg EncA_QA_d, EncA_QA_dd, EncA_QB_d;
  reg EncB_QB_d, EncB_QB_dd;

  always @(posedge CLK) begin
    EncA_QA_d  <= EncA_QA;
    EncA_QA_dd <= EncA_QA_d; 
    EncA_QB_d  <= EncA_QB;
    
    EncB_QB_d  <= EncB_QB;
    EncB_QB_dd <= EncB_QB_d;
  end

  wire enc_tick = (EncA_QA_dd == 1'b1 && EncA_QA_d == 1'b0); 
  wire jump = enc_tick && (EncA_QB_d == 1'b0); 
  wire start_trigger = (EncB_QB_dd == 1'b1 && EncB_QB_d == 1'b0);

  // ----------------------------------------------------
  // LICZNIK NIEAKTYWNOŚCI (5 SEKUND DLA DEMO)
  // ----------------------------------------------------
  reg [28:0] inactivity_timer;
  wire demo_timeout = (inactivity_timer >= 29'd400_000); // 5s przy 75MHz

  always @(posedge CLK or posedge RST) begin
      if (RST) begin
          inactivity_timer <= 0;
      end else if (state == ST_MENU) begin
          // Zresetuj licznik jeśli gracz cokolwiek kliknie/przekręci
          if (start_trigger || enc_tick) inactivity_timer <= 0;
          else if (!demo_timeout) inactivity_timer <= inactivity_timer + 1;
      end else begin
          inactivity_timer <= 0;
      end
  end

  // ----------------------------------------------------
  // ZMIENNE STANU GRY I AI DLA DEMA
  // ----------------------------------------------------
  reg [10:0] bird_y;           
  reg [10:0] pipe_x [0:2];     
  reg [10:0] pipe_gap_y [0:2]; 
  reg [3:0] score_thousands, score_hundreds, score_tens, score_ones;

  // AI DEMA: Szukanie najbliższej rury przed ptakiem
  wire [10:0] dist0 = (pipe_x[0] + PIPE_W > BIRD_X) ? (pipe_x[0] + PIPE_W - BIRD_X) : 11'd1000;
  wire [10:0] dist1 = (pipe_x[1] + PIPE_W > BIRD_X) ? (pipe_x[1] + PIPE_W - BIRD_X) : 11'd1000;
  wire [10:0] dist2 = (pipe_x[2] + PIPE_W > BIRD_X) ? (pipe_x[2] + PIPE_W - BIRD_X) : 11'd1000;

  wire p0_closest = (dist0 <= dist1) && (dist0 <= dist2);
  wire p1_closest = (dist1 <= dist0) && (dist1 <= dist2);

  wire [10:0] active_gap = p0_closest ? pipe_gap_y[0] :
                           p1_closest ? pipe_gap_y[1] : pipe_gap_y[2];

  // Skok Dema: jeśli ptak zbliży się na 1 piksel do dolnej krawędzi prześwitu
  wire auto_jump = (bird_y + BIRD_H >= active_gap + GAP_H - 1);

  // Kolizje
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
      state <= ST_MENU;
      bird_y <= SCR_H/2;
      pipe_x[0] <= SCR_W;      pipe_gap_y[0] <= 10;
      pipe_x[1] <= SCR_W + 25; pipe_gap_y[1] <= 15;
      pipe_x[2] <= SCR_W + 50; pipe_gap_y[2] <= 8;
      score_thousands <= 0; score_hundreds <= 0;
      score_tens <= 0; score_ones <= 0;
      level <= 0;
    end
    else if (state == ST_MENU || state == ST_OVER) begin
      if (start_trigger) begin 
        state <= ST_PLAY;
        bird_y <= SCR_H/2;
        pipe_x[0] <= SCR_W;      pipe_gap_y[0] <= 10;
        pipe_x[1] <= SCR_W + 25; pipe_gap_y[1] <= 15;
        pipe_x[2] <= SCR_W + 50; pipe_gap_y[2] <= 8;
        score_thousands <= 0; score_hundreds <= 0;
        score_tens <= 0; score_ones <= 0;
        level <= 0;
      end else if (state == ST_MENU && demo_timeout) begin
        state <= ST_DEMO; // Odpalenie automatycznego DEMA po 5s
        bird_y <= SCR_H/2;
        pipe_x[0] <= SCR_W;      pipe_gap_y[0] <= 10;
        pipe_x[1] <= SCR_W + 25; pipe_gap_y[1] <= 15;
        pipe_x[2] <= SCR_W + 50; pipe_gap_y[2] <= 8;
        score_thousands <= 0; score_hundreds <= 0;
        score_tens <= 0; score_ones <= 0;
        level <= 0;
      end
    end
    else if (state == ST_PLAY || state == ST_DEMO) begin
      // PRZERWANIE DEMA: Dowolna akcja gracza zaczyna normalną grę
      if (state == ST_DEMO && (start_trigger || enc_tick)) begin
        state <= ST_PLAY;
        bird_y <= SCR_H/2;
        pipe_x[0] <= SCR_W;      pipe_gap_y[0] <= 10;
        pipe_x[1] <= SCR_W + 25; pipe_gap_y[1] <= 15;
        pipe_x[2] <= SCR_W + 50; pipe_gap_y[2] <= 8;
        score_thousands <= 0; score_hundreds <= 0;
        score_tens <= 0; score_ones <= 0;
        level <= 0;
      end
      else if (crash) begin
        // W razie porażki w DEMO wracamy dyskretnie do Menu
        state <= (state == ST_DEMO) ? ST_MENU : ST_OVER;
      end 
      else begin
        // Ręczny skok gracza (tylko w PLAY)
        if (jump && bird_y > 3 && state == ST_PLAY) begin
            bird_y <= bird_y - 6; 
        end

        if(game_tick) begin
          // AI SKOK (tylko w DEMO)
          if (state == ST_DEMO && auto_jump && bird_y > 3) begin
              bird_y <= bird_y - 6;
          end else if (bird_y < SCR_H - BIRD_H) begin
              bird_y <= bird_y + 1; // Grawitacja
          end

          for(i=0; i<3; i=i+1) begin
            if (pipe_x[i] == 0) begin
              pipe_x[i] <= SCR_W + 10; 
              pipe_gap_y[i] <= 5 + lfsr[(i*4)+3 -: 4]; 
            end else begin
              pipe_x[i] <= pipe_x[i] - 1;
            end
            
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
  // RENDEROWANIE TEKSTÓW (MENU I UI)
  //-----------------------------------------
  wire blink_state = heartbeat[16]; 

  wire is_score_thou = (H_CNT >= 48 && H_CNT <= 50 && V_CNT >= 1 && V_CNT <= 5);
  wire is_score_hund = (H_CNT >= 52 && H_CNT <= 54 && V_CNT >= 1 && V_CNT <= 5);
  wire is_score_tens = (H_CNT >= 56 && H_CNT <= 58 && V_CNT >= 1 && V_CNT <= 5);
  wire is_score_ones = (H_CNT >= 60 && H_CNT <= 62 && V_CNT >= 1 && V_CNT <= 5);
  wire is_char_L      = (H_CNT >= 2 && H_CNT <= 4 && V_CNT >= 1 && V_CNT <= 5);
  wire is_level_digit = (H_CNT >= 6 && H_CNT <= 8 && V_CNT >= 1 && V_CNT <= 5);
  wire is_text_area = is_score_thou | is_score_hund | is_score_tens | is_score_ones | is_char_L | is_level_digit;

  wire [4:0] cur_digit = is_score_thou  ? {1'b0, score_thousands} :
                         is_score_hund  ? {1'b0, score_hundreds}  :
                         is_score_tens  ? {1'b0, score_tens}      :
                         is_score_ones  ? {1'b0, score_ones}      :
                         is_char_L      ? 5'd15                   : 
                         is_level_digit ? {1'b0, level}           : 5'd0;

  wire in_title_y = (V_CNT >= 10 && V_CNT <= 14);
  wire in_start_y = (V_CNT >= 25 && V_CNT <= 29);
  wire in_demo_y  = (V_CNT >= 34 && V_CNT <= 38); // Obszar dla napisu DEMO w rogu

  reg [4:0] menu_char;
  reg is_menu_text;

  always @(*) begin
      is_menu_text = 1'b0;
      menu_char = 5'd0;
      if (state == ST_MENU || state == ST_DEMO) begin
          if (in_title_y && state == ST_MENU) begin
              if (H_CNT >= 6 && H_CNT <= 8)        {is_menu_text, menu_char} = {1'b1, 5'd13}; 
              else if (H_CNT >= 10 && H_CNT <= 12) {is_menu_text, menu_char} = {1'b1, 5'd15}; 
              else if (H_CNT >= 14 && H_CNT <= 16) {is_menu_text, menu_char} = {1'b1, 5'd10}; 
              else if (H_CNT >= 18 && H_CNT <= 20) {is_menu_text, menu_char} = {1'b1, 5'd17}; 
              else if (H_CNT >= 22 && H_CNT <= 24) {is_menu_text, menu_char} = {1'b1, 5'd17}; 
              else if (H_CNT >= 26 && H_CNT <= 28) {is_menu_text, menu_char} = {1'b1, 5'd21}; 
              else if (H_CNT >= 30 && H_CNT <= 32) {is_menu_text, menu_char} = {1'b1, 5'd16}; 
              else if (H_CNT >= 34 && H_CNT <= 36) {is_menu_text, menu_char} = {1'b1, 5'd10}; 
              else if (H_CNT >= 38 && H_CNT <= 40) {is_menu_text, menu_char} = {1'b1, 5'd18}; 
              else if (H_CNT >= 42 && H_CNT <= 44) {is_menu_text, menu_char} = {1'b1, 5'd11}; 
              else if (H_CNT >= 46 && H_CNT <= 48) {is_menu_text, menu_char} = {1'b1, 5'd12}; 
              else if (H_CNT >= 50 && H_CNT <= 52) {is_menu_text, menu_char} = {1'b1, 5'd15}; 
              else if (H_CNT >= 54 && H_CNT <= 56) {is_menu_text, menu_char} = {1'b1, 5'd14}; 
          end
          else if (in_start_y && state == ST_MENU && blink_state) begin
              if (H_CNT >= 22 && H_CNT <= 24)      {is_menu_text, menu_char} = {1'b1, 5'd19}; 
              else if (H_CNT >= 26 && H_CNT <= 28) {is_menu_text, menu_char} = {1'b1, 5'd20}; 
              else if (H_CNT >= 30 && H_CNT <= 32) {is_menu_text, menu_char} = {1'b1, 5'd10}; 
              else if (H_CNT >= 34 && H_CNT <= 36) {is_menu_text, menu_char} = {1'b1, 5'd18}; 
              else if (H_CNT >= 38 && H_CNT <= 40) {is_menu_text, menu_char} = {1'b1, 5'd20}; 
          end
          else if (in_demo_y && state == ST_DEMO && blink_state) begin // Migające "DEMO"
              if (H_CNT >= 2 && H_CNT <= 4)        {is_menu_text, menu_char} = {1'b1, 5'd22}; // D
              else if (H_CNT >= 6 && H_CNT <= 8)   {is_menu_text, menu_char} = {1'b1, 5'd12}; // E
              else if (H_CNT >= 10 && H_CNT <= 12) {is_menu_text, menu_char} = {1'b1, 5'd16}; // M
              else if (H_CNT >= 14 && H_CNT <= 16) {is_menu_text, menu_char} = {1'b1, 5'd0};  // O (0 z romu wygląda jak O)
          end
      end
  end

  wire is_active_text = (state == ST_MENU) ? is_menu_text :
                        (state == ST_DEMO) ? (is_menu_text | is_text_area) : is_text_area;

  wire [4:0] render_char = (state == ST_MENU) ? menu_char :
                           (state == ST_DEMO && is_menu_text) ? menu_char : cur_digit;

  wire [2:0] char_x = is_score_thou ? (H_CNT - 48) : is_score_hund ? (H_CNT - 52) : is_score_tens ? (H_CNT - 56) : is_score_ones ? (H_CNT - 60) : is_char_L ? (H_CNT - 2) : is_level_digit ? (H_CNT - 6) : 3'd0;
  
  wire [2:0] text_x_menu = (H_CNT + 11'd2) & 11'h3;
  wire [2:0] text_x = (state == ST_MENU || (state == ST_DEMO && is_menu_text)) ? text_x_menu : char_x;

  wire [2:0] char_y = V_CNT - 1;
  wire [2:0] text_y_menu = in_title_y ? (V_CNT - 11'd10) : 
                           in_start_y ? (V_CNT - 11'd25) : 
                           in_demo_y  ? (V_CNT - 11'd34) : 3'd0;
  wire [2:0] text_y = (state == ST_MENU || (state == ST_DEMO && is_menu_text)) ? text_y_menu : char_y;

  wire [4:0] bit_idx = 14 - (text_y * 3 + text_x);

  reg [14:0] digit_rom;
  always @(*) begin
    case(render_char)
      5'd0:  digit_rom = 15'b111_101_101_101_111; 
      5'd1:  digit_rom = 15'b010_110_010_010_111; 
      5'd2:  digit_rom = 15'b111_001_111_100_111; 
      5'd3:  digit_rom = 15'b111_001_111_001_111; 
      5'd4:  digit_rom = 15'b101_101_111_001_001; 
      5'd5:  digit_rom = 15'b111_100_111_001_111; 
      5'd6:  digit_rom = 15'b111_100_111_101_111; 
      5'd7:  digit_rom = 15'b111_001_001_001_001; 
      5'd8:  digit_rom = 15'b111_101_111_101_111; 
      5'd9:  digit_rom = 15'b111_101_111_001_111; 
      5'd10: digit_rom = 15'b010_101_111_101_101; 
      5'd11: digit_rom = 15'b011_100_100_100_011; 
      5'd12: digit_rom = 15'b111_100_110_100_111; 
      5'd13: digit_rom = 15'b111_100_110_100_100; 
      5'd14: digit_rom = 15'b111_010_010_010_111; 
      5'd15: digit_rom = 15'b100_100_100_100_111; 
      5'd16: digit_rom = 15'b101_111_101_101_101; 
      5'd17: digit_rom = 15'b110_101_110_100_100; 
      5'd18: digit_rom = 15'b110_101_110_101_101; 
      5'd19: digit_rom = 15'b011_100_010_001_110; 
      5'd20: digit_rom = 15'b111_010_010_010_010; 
      5'd21: digit_rom = 15'b101_101_010_010_010; 
      5'd22: digit_rom = 15'b110_101_101_101_110; // Litera D
      default: digit_rom = 15'b000_000_000_000_000;
    endcase
  end

  reg draw_text_pixel;
  always @(*) begin
    draw_text_pixel = 1'b0;
    if (is_active_text) begin
      if (bit_idx < 15) draw_text_pixel = digit_rom[bit_idx];
    end
  end

  //-----------------------------------------
  // RYSOWANIE PIKSELI
  //-----------------------------------------
  wire show_score = (state == ST_PLAY || state == ST_DEMO) || blink_state;

  wire is_cloud1 = (H_CNT >= 12 && H_CNT <= 22 && V_CNT >= 6 && V_CNT <= 9) ||
                   (H_CNT >= 15 && H_CNT <= 19 && V_CNT >= 4 && V_CNT <= 6);
  wire is_cloud2 = (H_CNT >= 42 && H_CNT <= 52 && V_CNT >= 14 && V_CNT <= 17) ||
                   (H_CNT >= 45 && H_CNT <= 49 && V_CNT >= 12 && V_CNT <= 14);
  wire is_cloud3 = (H_CNT >= 24 && H_CNT <= 34 && V_CNT >= 22 && V_CNT <= 25) ||
                   (H_CNT >= 27 && H_CNT <= 31 && V_CNT >= 20 && V_CNT <= 22);

  wire is_cloud = is_cloud1 | is_cloud2 | is_cloud3;

  always @(*) begin
    // 1. WARSTWA NAJNIŻSZA: Błękitne niebo
    RED = 8'h00; GREEN = 8'hFF; BLUE = 8'hFF;
    
    // 2. CHMURY
    if (is_cloud) begin
      RED = 8'hFF; GREEN = 8'hFF; BLUE = 8'hFF;
    end

    // 3 i 4. RURY I PTAK (Rysowane zawsze poza głównym menu)
    if (state != ST_MENU) begin
        // Rury
        for(i=0; i<3; i=i+1) begin
          if(H_CNT >= pipe_x[i] && H_CNT < pipe_x[i] + PIPE_W) begin
            if (V_CNT < pipe_gap_y[i] || V_CNT > pipe_gap_y[i] + GAP_H) begin
              RED = 8'h00; GREEN = 8'hFF; BLUE = 8'h00;
            end
          end
        end

        // Ptak
        if(H_CNT >= BIRD_X && H_CNT < BIRD_X + BIRD_W && V_CNT >= bird_y && V_CNT < bird_y + BIRD_H) begin
          if (state == ST_OVER) begin
            RED = 8'hFF; GREEN = 8'h00; BLUE = 8'h00; // Zgnieciony, czerwony ptaszek
          end else begin
            RED = 8'hFF; GREEN = 8'hFF; BLUE = 8'h00; // Lecący żółty ptaszek
          end
        end
    end

    // 5. NAJWYŻSZA WARSTWA: TEKSTY I UI
    if (draw_text_pixel) begin
        if (state == ST_MENU) begin
            if (in_title_y) begin
                RED = 8'hFF; GREEN = 8'hFF; BLUE = 8'h00; // Żółte 'FlappyMarceli'
            end else begin
                RED = 8'hFF; GREEN = 8'hFF; BLUE = 8'hFF; // Biały 'START'
            end
        end 
        else if (state == ST_DEMO && is_menu_text) begin
            RED = 8'hFF; GREEN = 8'h00; BLUE = 8'h00; // Czerwony napis 'DEMO' żeby zwracał uwagę
        end 
        else if (show_score && is_text_area) begin
            RED = 8'hFF; GREEN = 8'hFF; BLUE = 8'hFF; // Białe punkty i level (zarówno w DEMO jak i PLAY)
        end
    end
  end
endmodule