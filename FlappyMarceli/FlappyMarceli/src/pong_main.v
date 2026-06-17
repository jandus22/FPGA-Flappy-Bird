module pong_main // Główny moduł układu (zostawiliśmy starą nazwę, żeby kompilator jej nie zgubił)
#( // Blok parametrów, czyli stałych wartości dla naszej gry
  parameter SCR_W = 64,    // Całkowita szerokość ekranu w pikselach
  parameter SCR_H = 40,    // Całkowita wysokość ekranu w pikselach
  parameter BIRD_W = 4,    // Szerokość żółtego ptaka (w pikselach)
  parameter BIRD_H = 3,    // Wysokość żółtego ptaka (w pikselach)
  parameter PIPE_W = 6,    // Szerokość zielonych rur (przeszkód)
  parameter GAP_H = 14     // Wysokość "prześwitu" między górną a dolną rurą
)
( // Deklaracja wejść i wyjść fizycznych z FPGA
	input wire        CLK,     // Główny zegar sprzętowy (np. 75 MHz)
	input wire        RST,     // Przycisk resetu (służy do awaryjnego restartu całego układu)
	input wire [10:0] H_CNT,   // Aktualnie rysowany piksel w poziomie (X)
	input wire [10:0] V_CNT,   // Aktualnie rysowany piksel w pionie (Y)
	input wire        EncA_QA, EncA_QB, // Piny pierwszego enkodera (A - do skakania)
    input wire        EncB_QA, EncB_QB, // Piny drugiego enkodera (B - do przycisku START)
	output reg [7:0]  RED, GREEN, BLUE, // 8-bitowe wyjścia kolorów (RGB) na monitor
	output wire [3:0] LED      // Diody LED na płytce do testów/diagnostyki
);

  wire [10:0] BIRD_X = SCR_W / 3; // Stała pozycja ptaka na osi X (ptak stoi, rury lecą)

  // ----------------------------------------------------
  // MASZYNA STANÓW GRY (Określa, w jakim trybie jesteśmy)
  // ----------------------------------------------------
  reg [1:0] state; // Rejestr 2-bitowy, przechowuje aktualny stan (od 0 do 3)
  localparam ST_MENU = 2'd0; // Stan 0: Ekran startowy
  localparam ST_PLAY = 2'd1; // Stan 1: Właściwa gra
  localparam ST_OVER = 2'd2; // Stan 2: Ekran przegranej (Game Over)
  localparam ST_DEMO = 2'd3; // Stan 3: Tryb pokazu (gra gra sama w siebie)

  // LFSR - Sprzętowy generator liczb pseudolosowych (do losowania wysokości rur)
  reg [15:0] lfsr; // 16-bitowy rejestr przesuwający
  wire lfsr_feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]; // Bramki XOR "mieszające" bity
  always @(posedge CLK or posedge RST) begin // Wykonuje się co takt zegara
    if (RST) lfsr <= 16'hACE1; // Jeżeli reset, ustawiamy losowe "ziarno" początkowe
    else     lfsr <= {lfsr[14:0], lfsr_feedback}; // W przeciwnym razie przesuwamy bity i dopinamy nowy z XORa
  end

  reg [31:0] heartbeat; // Prosty licznik ogólnego przeznaczenia (m.in. do migania tekstów)
  always@(posedge CLK or posedge RST) // Co takt zegara...
    if(RST) heartbeat <= 0; // Zerujemy przy resecie
    else    heartbeat <= heartbeat + 1; // Zwiększamy o 1
  assign LED = heartbeat[26:23]; // Podpinamy wyższe bity licznika do LEDów, żeby widać było, że układ "żyje"

  reg [3:0] level; // Rejestr poziomu trudności (od 0 do 9)
  wire [31:0] current_speed = 2500 - (level * 200); // Oblicza co ile taktów gra ma się zaktualizować (im wyższy level, tym mniejsza liczba = szybciej)
  reg [31:0] tick_counter; // Licznik "odczekujący" swój czas do następnej klatki gry
  wire game_tick = (tick_counter >= current_speed); // Sygnał (flaga) dający znać, że czas zaktualizować ruch na ekranie

  always @(posedge CLK or posedge RST) begin // Pętla odliczająca czas klatki
    if (RST) tick_counter <= 0; // Reset
    else if (game_tick) tick_counter <= 0; // Zaczynamy liczyć od nowa po odpaleniu klatki
    else tick_counter <= tick_counter + 1; // Nabijamy zegar
  end

  // ----------------------------------------------------
  // OBSŁUGA WEJŚĆ (ENKODERY I PRZYCISKI - Synchronizacja)
  // ----------------------------------------------------
  reg EncA_QA_d, EncA_QA_dd, EncA_QB_d; // Rejestry "opóźniające" Enkoder A dla sprzętowego Debouncingu
  reg EncB_QB_d, EncB_QB_dd;            // Rejestry "opóźniające" Enkoder B

  always @(posedge CLK) begin // Co takt układ zapamiętuje stany enkoderów...
    EncA_QA_d  <= EncA_QA;    // ...stan z tej chwili
    EncA_QA_dd <= EncA_QA_d;  // ...stan z poprzedniej chwili
    EncA_QB_d  <= EncA_QB;    // Inny pin w Enkoderze A
    
    EncB_QB_d  <= EncB_QB;    // Stan Enkodera B z tej chwili
    EncB_QB_dd <= EncB_QB_d;  // Stan z poprzedniej chwili
  end

  // Kiedy poprzedni takt QA był 1, a obecny jest 0, to wiemy, że gałka przekręciła jeden "klik"
  wire enc_tick = (EncA_QA_dd == 1'b1 && EncA_QA_d == 1'b0); 
  wire jump = enc_tick && (EncA_QB_d == 1'b0); // Reagujemy na skok tylko, jeśli kręcimy w odpowiednią stronę (QB jest 0)
  wire start_trigger = (EncB_QB_dd == 1'b1 && EncB_QB_d == 1'b0); // To samo, ale dla enkodera B (jako przycisk START)

  // ----------------------------------------------------
  // LICZNIKI CZASU (5 SEKUND W MENU, 10 SEKUND W DEMO)
  // ----------------------------------------------------
  reg [29:0] state_timer; // Duży, 30-bitowy licznik na bardzo długi czas (miliony taktów)
  wire demo_start_timeout = (state_timer >= 30'd400_000); // Flaga: minęło 5 sekund (375 mln taktów / 75 MHz)
  wire demo_loop_timeout  = (state_timer >= 30'd300_000); // Flaga: minęło 10 sekund (750 mln taktów)

  always @(posedge CLK or posedge RST) begin // Pętla pilnująca czasu dla trybu DEMO
      if (RST) begin
          state_timer <= 0; // Awaryjny reset
      end else if (state == ST_MENU) begin // Gdy jesteśmy w głównym menu:
          if (start_trigger || enc_tick || demo_start_timeout) state_timer <= 0; // Zeruj timer po każdym ruchu gracza LUB jeśli minęło 5s
          else state_timer <= state_timer + 1; // Odliczaj dalej w ciszy
      end else if (state == ST_DEMO) begin // Gdy jesteśmy w trakcie trybu Demo:
          if (start_trigger || enc_tick || crash || demo_loop_timeout) state_timer <= 0; // Zeruj jeśli zderzenie, koniec 10s lub klik gracza
          else state_timer <= state_timer + 1; // Odliczaj czas dema
      end else begin
          state_timer <= 0; // We właściwej grze timer dema ma być wyłączony (na 0)
      end
  end

  // ----------------------------------------------------
  // ZMIENNE STANU GRY I AI DLA DEMA
  // ----------------------------------------------------
  reg [10:0] bird_y;           // Wysokość, na której aktualnie lata ptak
  reg [10:0] pipe_x [0:2];     // Zestaw pozycj X dla trzech rur (0, 1 i 2)
  reg [10:0] pipe_gap_y [0:2]; // Pozycja "dziury" w każdej z trzech rur
  reg [3:0] score_thousands, score_hundreds, score_tens, score_ones; // Pamięć punktacji rozdzielona na cyfry

  // SZTUCZNA INTELIGENCJA DLA DEMA: Matematyczne liczenie dystansu od ptaka do prawej krawędzi rur
  wire [10:0] dist0 = (pipe_x[0] + PIPE_W > BIRD_X) ? (pipe_x[0] + PIPE_W - BIRD_X) : 11'd1000; // Dystans od Rury 0
  wire [10:0] dist1 = (pipe_x[1] + PIPE_W > BIRD_X) ? (pipe_x[1] + PIPE_W - BIRD_X) : 11'd1000; // Dystans od Rury 1
  wire [10:0] dist2 = (pipe_x[2] + PIPE_W > BIRD_X) ? (pipe_x[2] + PIPE_W - BIRD_X) : 11'd1000; // Dystans od Rury 2 (1000 = rura miniona)

  // Ustalanie logiczne, która rura jest najbliżej ptaka przed nim
  wire p0_closest = (dist0 <= dist1) && (dist0 <= dist2); // Rura 0 jest nabliżej
  wire p1_closest = (dist1 <= dist0) && (dist1 <= dist2); // Rura 1 jest najbliżej

  // Odczytujemy dokładną wysokość "prześwitu" tej rury, która w tej sekundzie atakuje ptaka
  wire [10:0] active_gap = p0_closest ? pipe_gap_y[0] :
                           p1_closest ? pipe_gap_y[1] : pipe_gap_y[2];

  // AI odpala skok, kiedy stopy ptaka dotkną poziomu 1 piksel nad dolną rurą
  wire auto_jump = (bird_y + BIRD_H >= active_gap + GAP_H - 1);

  // KOLIZJE: Sprawdzanie, czy ptak uderzył
  wire crash_ground = (bird_y + BIRD_H >= SCR_H); // Oraz w glebę (podłogę ekranu)
  wire crash_pipe0 = (BIRD_X + BIRD_W > pipe_x[0]) && (BIRD_X < pipe_x[0] + PIPE_W) && 
                     ((bird_y < pipe_gap_y[0]) || (bird_y + BIRD_H > pipe_gap_y[0] + GAP_H)); // Warunek na wejście z Rurę 0 poza dziurą
  wire crash_pipe1 = (BIRD_X + BIRD_W > pipe_x[1]) && (BIRD_X < pipe_x[1] + PIPE_W) && 
                     ((bird_y < pipe_gap_y[1]) || (bird_y + BIRD_H > pipe_gap_y[1] + GAP_H)); // Kolizja dla Rury 1
  wire crash_pipe2 = (BIRD_X + BIRD_W > pipe_x[2]) && (BIRD_X < pipe_x[2] + PIPE_W) && 
                     ((bird_y < pipe_gap_y[2]) || (bird_y + BIRD_H > pipe_gap_y[2] + GAP_H)); // Kolizja dla Rury 2

  wire crash = crash_ground | crash_pipe0 | crash_pipe1 | crash_pipe2; // Złączenie wszystkich kolizji w jeden sygnał (OR)

  integer i; // Zmienna ułatwiająca pętlę "for"
  always @(posedge CLK or posedge RST) begin // Pętla wykonująca ruchy co takt zegara
    if(RST) begin // Pełny "twardy" reset układu
      state <= ST_MENU; // Wracamy do menu
      bird_y <= SCR_H/2; // Ptak na środek
      pipe_x[0] <= SCR_W;      pipe_gap_y[0] <= 10; // Rura 1 poza ekranem
      pipe_x[1] <= SCR_W + 25; pipe_gap_y[1] <= 15; // Rura 2 dalej w tyle
      pipe_x[2] <= SCR_W + 50; pipe_gap_y[2] <= 8;  // Rura 3 jeszcze dalej
      score_thousands <= 0; score_hundreds <= 0; score_tens <= 0; score_ones <= 0; // Punkty do zera
      level <= 0; // Level od zera
    end
    else if (state == ST_MENU || state == ST_OVER) begin // Jeśli gra po prostu stoi na MENU lub GAME OVER
      if (start_trigger) begin // Gracz nacisnął START - uruchamiamy nową grę
        state <= ST_PLAY; // Tryb gry na żywo
        bird_y <= SCR_H/2; // Reset wszystkich pozycji jak przy pełnym twardym resecie
        pipe_x[0] <= SCR_W;      pipe_gap_y[0] <= 10;
        pipe_x[1] <= SCR_W + 25; pipe_gap_y[1] <= 15;
        pipe_x[2] <= SCR_W + 50; pipe_gap_y[2] <= 8;
        score_thousands <= 0; score_hundreds <= 0; score_tens <= 0; score_ones <= 0;
        level <= 0;
      end else if (state == ST_MENU && demo_start_timeout) begin // Gracz nie nacisnął nic przez 5 sekund (timeout)
        state <= ST_DEMO; // System wchodzi w ukryty tryb pokazu
        bird_y <= SCR_H/2; // Reset ustawień jak do nowej gry, ale to układ zagra sam ze sobą
        pipe_x[0] <= SCR_W;      pipe_gap_y[0] <= 10;
        pipe_x[1] <= SCR_W + 25; pipe_gap_y[1] <= 15;
        pipe_x[2] <= SCR_W + 50; pipe_gap_y[2] <= 8;
        score_thousands <= 0; score_hundreds <= 0; score_tens <= 0; score_ones <= 0;
        level <= 0;
      end
    end
    else if (state == ST_PLAY || state == ST_DEMO) begin // PĘTLA WYKONYWANA PODCZAS RUCHU (Dla człowieka lub dla Dema)
      if (state == ST_DEMO && (start_trigger || enc_tick)) begin // Jeśli leciało Demo i gracz szarpnął gałkę...
        state <= ST_PLAY; // Wchodzimy natychmiast do normalnej gry (Przerywamy demo)
        bird_y <= SCR_H/2; // Oraz dla bezpieczeństwa resetujemy planszę żeby go nie ubić
        pipe_x[0] <= SCR_W;      pipe_gap_y[0] <= 10;
        pipe_x[1] <= SCR_W + 25; pipe_gap_y[1] <= 15;
        pipe_x[2] <= SCR_W + 50; pipe_gap_y[2] <= 8;
        score_thousands <= 0; score_hundreds <= 0; score_tens <= 0; score_ones <= 0;
        level <= 0;
      end
      else if (state == ST_DEMO && (crash || demo_loop_timeout)) begin // Jeśli w DEMO ptak zginie ALBO minie 10 sekund..
        state <= ST_DEMO; // Odświeżamy tryb DEMO (Zapętlamy)
        bird_y <= SCR_H/2; // Znowu reset wszystkich rur i ptaków
        pipe_x[0] <= SCR_W;      pipe_gap_y[0] <= 10;
        pipe_x[1] <= SCR_W + 25; pipe_gap_y[1] <= 15;
        pipe_x[2] <= SCR_W + 50; pipe_gap_y[2] <= 8;
        score_thousands <= 0; score_hundreds <= 0; score_tens <= 0; score_ones <= 0;
        level <= 0;
      end
      else if (state == ST_PLAY && crash) begin // Jeśli CZŁOWIEK uderzy w rurę w normalnej grze...
        state <= ST_OVER; // Koniec gry, tryb Porażki
      end 
      else begin // KOD WYKONYWANY, JEŚLI NIKT NIE ZDERZYŁ SIĘ W TEJ MILISEKUNDZIE
        if (jump && bird_y > 3 && state == ST_PLAY) begin // Jeśli jesteśmy na żywo i gracz ruszy gałką (oraz nie wyleci sufitem)
            bird_y <= bird_y - 6; // Podrzucamy ptaka o 6 piksele w GÓRĘ
        end

        if(game_tick) begin // Czy wybił moment na odświeżenie klatki? (Prędkość kontrolowana lewelem)
          if (state == ST_DEMO && auto_jump && bird_y > 3) begin // Sztuczna Inteligencja wchodzi tylko w Demo
              bird_y <= bird_y - 6; // AI samo klika przycisk skoku w górę!
          end else if (bird_y < SCR_H - BIRD_H) begin // W każdym innym razie...
              bird_y <= bird_y + 1; // Silnik Grawitacyjny dociąga ptaka w DÓŁ (Zwiększa współrzędną Y)
          end

          for(i=0; i<3; i=i+1) begin // Odśwież pozycję wszystkich trzech rur
            if (pipe_x[i] == 0) begin // Rura wyleciała poza lewą krawędź ekranu (zniknęła)
              pipe_x[i] <= SCR_W + 10; // Przenieś ją całkiem za prawą krawędź z buforem 10 pikseli
              pipe_gap_y[i] <= 5 + lfsr[(i*4)+3 -: 4]; // Użyj naszego generatora losowego żeby ustawić wysokość "dziury"
            end else begin
              pipe_x[i] <= pipe_x[i] - 1; // Rura nie wyjechała z ekranu, więc przesuń w Lewo
            end
            
            // SYSTEM NALICZANIA PUNKTÓW W OPARCIU O POZYCJĘ
            if (pipe_x[i] == BIRD_X) begin // Gdy oś przemieszczającej się rury przetnie się w osi ptaka (czyli ją pokonaliśmy)
              if (score_ones == 9) begin // Limit jedności (0 do 9)
                score_ones <= 0; // Jedności reset do 0
                if (level < 9) level <= level + 1; // Zwiększamy level (i przyśpieszamy!) z każdą dychą
                if (score_tens == 9) begin // Mechanizm doliczania setek, gdy dziesiątki wybiją 9 (99 punktów)
                  score_tens <= 0;
                  if (score_hundreds == 9) begin // Analogicznie wybijanie tysięcy 
                    score_hundreds <= 0;
                    if (score_thousands != 9) score_thousands <= score_thousands + 1;
                  end else score_hundreds <= score_hundreds + 1; // Uzupełnianie setki
                end else score_tens <= score_tens + 1; // Dodawanie dziesiątek
              end else score_ones <= score_ones + 1; // Normalne nabijanie punktu jedności (np. z 1 na 2)
            end
          end
        end
      end
    end
  end

  //-----------------------------------------
  // RENDEROWANIE TEKSTÓW (MENU I UI) ORAZ LOKALIZACJA WYŚWIETLANIA
  //-----------------------------------------
  wire blink_state = heartbeat[16]; // Wykorzystujemy określony bit Timera jako przełącznik Prawda/Fałsz (do efektu migania Start)

  // Ustawienie koordynat, gdzie mają pojawiać się poszczególne cyferki wyniku
  wire is_score_thou = (H_CNT >= 48 && H_CNT <= 50 && V_CNT >= 1 && V_CNT <= 5); // Tysiące
  wire is_score_hund = (H_CNT >= 52 && H_CNT <= 54 && V_CNT >= 1 && V_CNT <= 5); // Setki
  wire is_score_tens = (H_CNT >= 56 && H_CNT <= 58 && V_CNT >= 1 && V_CNT <= 5); // Dziesiątki
  wire is_score_ones = (H_CNT >= 60 && H_CNT <= 62 && V_CNT >= 1 && V_CNT <= 5); // Jedności
  wire is_char_L      = (H_CNT >= 2 && H_CNT <= 4 && V_CNT >= 1 && V_CNT <= 5);  // Litera "L" (jak Level) z lewej u góry
  wire is_level_digit = (H_CNT >= 6 && H_CNT <= 8 && V_CNT >= 1 && V_CNT <= 5);  // Obecny cyfrowy poziom
  // "ORowanie" czyli uogólnianie: To po prostu cała połać przewidziana na UI (będzie odświeżane)
  wire is_text_area = is_score_thou | is_score_hund | is_score_tens | is_score_ones | is_char_L | is_level_digit;

  // Moduł decydujący JAKI NUMER ma pojawić się w danej ćwiartce interfejsu 
  wire [4:0] cur_digit = is_score_thou  ? {1'b0, score_thousands} :
                         is_score_hund  ? {1'b0, score_hundreds}  :
                         is_score_tens  ? {1'b0, score_tens}      :
                         is_score_ones  ? {1'b0, score_ones}      :
                         is_char_L      ? 5'd15                   : // Pozycja nr 15 z romu to "L" 
                         is_level_digit ? {1'b0, level}           : 5'd0;

  wire in_title_y = (V_CNT >= 10 && V_CNT <= 14); // Pasek, gdzie wyswietli się FlappyMarceli
  wire in_start_y = (V_CNT >= 25 && V_CNT <= 29); // Pasek, gdzie pojawi się przycisk START
  wire in_demo_y  = (V_CNT >= 34 && V_CNT <= 38); // Ciasny paseczek dla małego napisu DEMO na samym dole

  reg [4:0] menu_char; // Zmienna mówiąca, z której pozycji ROMU pobieramy alfabet
  reg is_menu_text; // Informacja "Tak, to tutaj mamy narysować napis menu"

  always @(*) begin // Logika odpowiadająca "co jakaś literka z Tytułu/Demo oznacza i gdzie się znajduje"
      is_menu_text = 1'b0; // Standardowo nie rysujemy tekstu
      menu_char = 5'd0;    // Standardowo ustawieni na ZERO
      if (state == ST_MENU || state == ST_DEMO) begin // Odpalanie alfabetu tylko dla Trybu Menu i Demo
          if (in_title_y && state == ST_MENU) begin // Literowanie wyrazu "FlappyMarceli" za pomocą skrzyżowania X z Y w tabeli
              if (H_CNT >= 6 && H_CNT <= 8)        {is_menu_text, menu_char} = {1'b1, 5'd13}; // Pozycja 13 w ROMie: F
              else if (H_CNT >= 10 && H_CNT <= 12) {is_menu_text, menu_char} = {1'b1, 5'd15}; // 15: L
              else if (H_CNT >= 14 && H_CNT <= 16) {is_menu_text, menu_char} = {1'b1, 5'd10}; // 10: A
              else if (H_CNT >= 18 && H_CNT <= 20) {is_menu_text, menu_char} = {1'b1, 5'd17}; // 17: P
              else if (H_CNT >= 22 && H_CNT <= 24) {is_menu_text, menu_char} = {1'b1, 5'd17}; // 17: P
              else if (H_CNT >= 26 && H_CNT <= 28) {is_menu_text, menu_char} = {1'b1, 5'd21}; // 21: Y
              else if (H_CNT >= 30 && H_CNT <= 32) {is_menu_text, menu_char} = {1'b1, 5'd16}; // 16: M
              else if (H_CNT >= 34 && H_CNT <= 36) {is_menu_text, menu_char} = {1'b1, 5'd10}; // 10: A
              else if (H_CNT >= 38 && H_CNT <= 40) {is_menu_text, menu_char} = {1'b1, 5'd18}; // 18: R
              else if (H_CNT >= 42 && H_CNT <= 44) {is_menu_text, menu_char} = {1'b1, 5'd11}; // 11: C
              else if (H_CNT >= 46 && H_CNT <= 48) {is_menu_text, menu_char} = {1'b1, 5'd12}; // 12: E
              else if (H_CNT >= 50 && H_CNT <= 52) {is_menu_text, menu_char} = {1'b1, 5'd15}; // 15: L
              else if (H_CNT >= 54 && H_CNT <= 56) {is_menu_text, menu_char} = {1'b1, 5'd14}; // 14: I
          end
          else if (in_start_y && state == ST_MENU && blink_state) begin // Słowo START i mruganie zależne od TIMERA (blink_state)
              if (H_CNT >= 22 && H_CNT <= 24)      {is_menu_text, menu_char} = {1'b1, 5'd19}; // S
              else if (H_CNT >= 26 && H_CNT <= 28) {is_menu_text, menu_char} = {1'b1, 5'd20}; // T
              else if (H_CNT >= 30 && H_CNT <= 32) {is_menu_text, menu_char} = {1'b1, 5'd10}; // A
              else if (H_CNT >= 34 && H_CNT <= 36) {is_menu_text, menu_char} = {1'b1, 5'd18}; // R
              else if (H_CNT >= 38 && H_CNT <= 40) {is_menu_text, menu_char} = {1'b1, 5'd20}; // T
          end
          else if (in_demo_y && state == ST_DEMO && blink_state) begin // Dodany, mrugający znaczek DEMO 
              if (H_CNT >= 2 && H_CNT <= 4)        {is_menu_text, menu_char} = {1'b1, 5'd22}; // D
              else if (H_CNT >= 6 && H_CNT <= 8)   {is_menu_text, menu_char} = {1'b1, 5'd12}; // E
              else if (H_CNT >= 10 && H_CNT <= 12) {is_menu_text, menu_char} = {1'b1, 5'd16}; // M
              else if (H_CNT >= 14 && H_CNT <= 16) {is_menu_text, menu_char} = {1'b1, 5'd0};  // Do O użyto klasycznego "0"
          end
      end
  end

  // Filtrowanie, żeby odpowiednie słowa nie kolidowały z numerem levela lub punktacją w trakcie dema
  wire is_active_text = (state == ST_MENU) ? is_menu_text :
                        (state == ST_DEMO) ? (is_menu_text | is_text_area) : is_text_area;

  // Przełączanie źródła czcionki (jeśli jesteśmy w grze, bierzemy cyfry Punktów)
  wire [4:0] render_char = (state == ST_MENU) ? menu_char :
                           (state == ST_DEMO && is_menu_text) ? menu_char : cur_digit;

  // Matematyka mapowania każdego rysowanego punktu z ekranu fizycznego do wirtualnej siatki 3x5 literki (X)
  wire [2:0] char_x = is_score_thou ? (H_CNT - 48) : is_score_hund ? (H_CNT - 52) : is_score_tens ? (H_CNT - 56) : is_score_ones ? (H_CNT - 60) : is_char_L ? (H_CNT - 2) : is_level_digit ? (H_CNT - 6) : 3'd0;
  
  wire [2:0] text_x_menu = (H_CNT + 11'd2) & 11'h3; // Zabezpieczenie szerokości dla alfabetu Menu 
  wire [2:0] text_x = (state == ST_MENU || (state == ST_DEMO && is_menu_text)) ? text_x_menu : char_x;

  // To samo dla mapowania matematycznego ekranu w Y dla siatki literki
  wire [2:0] char_y = V_CNT - 1;
  wire [2:0] text_y_menu = in_title_y ? (V_CNT - 11'd10) : 
                           in_start_y ? (V_CNT - 11'd25) : 
                           in_demo_y  ? (V_CNT - 11'd34) : 3'd0;
  wire [2:0] text_y = (state == ST_MENU || (state == ST_DEMO && is_menu_text)) ? text_y_menu : char_y;

  wire [4:0] bit_idx = 14 - (text_y * 3 + text_x); // Obliczanie odpowiedniego Indeksu Bita na podstawie XY zdefiniowanego wyżej

  reg [14:0] digit_rom; // Definiowanie matrycy 15 bitowej (3x5 pikseli to dokładnie 15 kropek dla literki)
  always @(*) begin // Moduł słownika dla literek
    case(render_char) // Switch odczytujący 1 i 0 ułożone fizycznie jak znak
      5'd0:  digit_rom = 15'b111_101_101_101_111; // 0
      5'd1:  digit_rom = 15'b010_110_010_010_111; // 1
      5'd2:  digit_rom = 15'b111_001_111_100_111; // 2
      5'd3:  digit_rom = 15'b111_001_111_001_111; // 3
      5'd4:  digit_rom = 15'b101_101_111_001_001; // 4
      5'd5:  digit_rom = 15'b111_100_111_001_111; // 5
      5'd6:  digit_rom = 15'b111_100_111_101_111; // 6
      5'd7:  digit_rom = 15'b111_001_001_001_001; // 7
      5'd8:  digit_rom = 15'b111_101_111_101_111; // 8
      5'd9:  digit_rom = 15'b111_101_111_001_111; // 9
      5'd10: digit_rom = 15'b010_101_111_101_101; // A
      5'd11: digit_rom = 15'b011_100_100_100_011; // C
      5'd12: digit_rom = 15'b111_100_110_100_111; // E
      5'd13: digit_rom = 15'b111_100_110_100_100; // F
      5'd14: digit_rom = 15'b111_010_010_010_111; // I
      5'd15: digit_rom = 15'b100_100_100_100_111; // L
      5'd16: digit_rom = 15'b101_111_101_101_101; // M
      5'd17: digit_rom = 15'b110_101_110_100_100; // P
      5'd18: digit_rom = 15'b110_101_110_101_101; // R
      5'd19: digit_rom = 15'b011_100_010_001_110; // S
      5'd20: digit_rom = 15'b111_010_010_010_010; // T
      5'd21: digit_rom = 15'b101_101_010_010_010; // Y
      5'd22: digit_rom = 15'b110_101_101_101_110; // D (Dodane)
      default: digit_rom = 15'b000_000_000_000_000; // Na błędy nic
    endcase
  end

  reg draw_text_pixel; // Flaga weryfikacyjna przed wypluciem do monitora, czy rysujemy puste (0) czy "świecące" pole czcionki
  always @(*) begin // Logika ciągłego przełożenia bita z cyfry/znaku do naświetlania
    draw_text_pixel = 1'b0; // Oczywiście standardowo 0 pikseli zapalonych
    if (is_active_text) begin // Jeśli laser przejeżdża po polu na czcionkę...
      if (bit_idx < 15) draw_text_pixel = digit_rom[bit_idx]; // Wydobądź z czcionki i "naświetl" kropkę dla tego rzędu!
    end
  end

  //-----------------------------------------
  // RYSOWANIE PIKSELI: Pędzel dla FPGA (kolejność nadpisuje barwy)
  //-----------------------------------------
  wire show_score = (state == ST_PLAY || state == ST_DEMO) || blink_state; // Wynik miga tylko jeśli zginiemy poza demo (blink) 

  // Pasy chmurek, zrobione z dwóch prostokątów każdy za pomocą warunków || (OR). Pierwszy mniejszy na czubku, drugi płaski na dnie.
  wire is_cloud1 = (H_CNT >= 12 && H_CNT <= 22 && V_CNT >= 6 && V_CNT <= 9) ||
                   (H_CNT >= 15 && H_CNT <= 19 && V_CNT >= 4 && V_CNT <= 6); // Pierwsza (Lewa chmurka)
  wire is_cloud2 = (H_CNT >= 42 && H_CNT <= 52 && V_CNT >= 14 && V_CNT <= 17) ||
                   (H_CNT >= 45 && H_CNT <= 49 && V_CNT >= 12 && V_CNT <= 14); // Środkowa, lekko niżej
  wire is_cloud3 = (H_CNT >= 24 && H_CNT <= 34 && V_CNT >= 22 && V_CNT <= 25) ||
                   (H_CNT >= 27 && H_CNT <= 31 && V_CNT >= 20 && V_CNT <= 22); // Prawa chmurka

  wire is_cloud = is_cloud1 | is_cloud2 | is_cloud3; // Scalenie sygnału "rysuj jakąkolwiek chmurę"

  always @(*) begin // Główna maszyna malująca tło monitora
    // 1. WARSTWA NAJNIŻSZA: Błękitne niebo (Rysowane zawsze podstępnie wszędzie)
    RED = 8'h00; GREEN = 8'hFF; BLUE = 8'hFF; // Kolor Cyjan Hexadecymalnie
    
    // 2. CHMURY (Malowanie Pół-przezroczystych obłoków)
    if (is_cloud) begin // Weryfikacja: Jesteśmy w obrysie chmury? Nadpisujemy cyjan!
      RED = 8'hFF; GREEN = 8'hFF; BLUE = 8'hFF; // Pełny RGB dla idealnego błękitnobiałego obłoku
    end

    // 3 i 4. RURY I PTAK (Zasłaniają Niebo i Chmury)
    if (state != ST_MENU) begin // Pokazujemy Ptaka i przeszkody tylko poza ekranem powitalnym Start
        for(i=0; i<3; i=i+1) begin // Przewidujemy fizykę 3 Rur...
          if(H_CNT >= pipe_x[i] && H_CNT < pipe_x[i] + PIPE_W) begin // Kiedy piksel rysujący leci od lewej rury po prawą oś x...
            if (V_CNT < pipe_gap_y[i] || V_CNT > pipe_gap_y[i] + GAP_H) begin // ...i gdy jednoczenie nie jest wewnątrz dziury w osi Y
              RED = 8'h00; GREEN = 8'hFF; BLUE = 8'h00; // Zamaluj to na czysty jaskrawy Zielony
            end
          end
        end

        // Rysowanie modelu ptaka, czyli u nas piękny prostokąt, też działa jak nadrzędna maska na niebie:
        if(H_CNT >= BIRD_X && H_CNT < BIRD_X + BIRD_W && V_CNT >= bird_y && V_CNT < bird_y + BIRD_H) begin
          if (state == ST_OVER) begin // Po zderzeniu
            RED = 8'hFF; GREEN = 8'h00; BLUE = 8'h00; // Malujemy placka w 100% Czerwieni 
          end else begin
            RED = 8'hFF; GREEN = 8'hFF; BLUE = 8'h00; // Malujemy lecącego ziomka z gry FlappyBird - Żółty RGB
          end
        end
    end

    // 5. NAJWYŻSZA WARSTWA: TEKSTY I UI (Malowane na samiutkim końcu, wszystko inne przykrywa)
    if (draw_text_pixel) begin // Moduł litery/Punktu odpalił nam zapalenie diody:
        if (state == ST_MENU) begin // Wykrycie stanu Menu...
            if (in_title_y) begin // ...w obrębie nagłówka FlappyMarceli
                RED = 8'hFF; GREEN = 8'hFF; BLUE = 8'h00; // Pomaluj nagłówek na zółto jak Flappy!
            end else begin
                RED = 8'hFF; GREEN = 8'hFF; BLUE = 8'hFF; // Ale START u dołu mruga na czysto biało 
            end
        end 
        else if (state == ST_DEMO && is_menu_text) begin // Wykrycie "napisów tekstowych" w trakcie lecącego demo 
            RED = 8'hFF; GREEN = 8'h00; BLUE = 8'h00; // "DEMO" pojawia się wyrysowane Czerwienią, żeby zwracać uwagę graczy
        end 
        else if (show_score && is_text_area) begin // Zostały nam same liczby i punkty "L" 
            RED = 8'hFF; GREEN = 8'hFF; BLUE = 8'hFF; // Malujemy je na zewnątrz gier i podczas Dema, i u Siebie po prostu jako biały score
        end
    end
  end
endmodule // Koniec fizycznego modułu "flappy marceli"