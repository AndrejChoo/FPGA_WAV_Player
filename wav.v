module wav(
	input wire clk,
	input wire rst,
	input wire MISO,
	output wire MOSI,
	output wire SCK,
	output wire CS,
	output wire WP,
	output wire HOLD,
	output wire BEEP
   );

parameter inclock = 50_000_000; //Входная частота
parameter wav_freq = 24_000; //Частота дискретизации wav
parameter half_freq = inclock/wav_freq/2-1; //Делитель
parameter cnt_wide = $clog2(half_freq); //Разрядность счётчика делителя

reg[(cnt_wide-1):0]div;
reg wav_clk;

wire[7:0]data;
wire[22:0]add;

//Делитель входной частоты до частоты дискретизации wav
always@(posedge clk or negedge rst)
	begin
		if(!rst)
			begin
				div <= 0;
				wav_clk <= 0;
			end
		else
			begin
				div <= div + 1;
				if(div == half_freq)
					begin
						div <= 0;
						wav_clk <= ~wav_clk;
					end
			end
	end
	

//Регистр адреса
reg[23:0]add_cnt;

always@(negedge wav_clk or negedge rst) 
	begin
		if(!rst)add_cnt <= 0;
		else add_cnt <= add_cnt + 1;
	end


//ШИМ
wire[7:0]CMP;
reg[7:0]compare, pwm_cnt;
reg pwm_out;

always@(negedge wav_clk) compare <= CMP;

always@(posedge clk or negedge rst)
	begin
		if(!rst)
			begin
				pwm_out <= 0;
				pwm_cnt <= 0;
			end
		else
			begin
				pwm_cnt <= pwm_cnt + 1;
				if(pwm_cnt <= compare) pwm_out <= 1;
				else pwm_out <= 0;
			end
	end

assign BEEP = pwm_out;

//Конечный автомат SPI 
localparam prescaller = 1;
//Wires
wire SPI_START,SPI_BSY;
wire[7:0]SPI_DIN,SPI_DOUT;
//Registers
reg[7:0]spdr_r,spdr_t, spidr_w;
reg[4:0]spi_state, spi_cnt;
reg[7:0]spi_delay;
reg spi_sck, spi_so, spi_rdy;

//Защёлкиваем данные для отправки в SPI
always@(posedge SPI_START) spidr_w <= SPI_DIN;

always@(posedge clk or negedge rst)
begin
    if(!rst)
        begin
            spi_state <= 0;
            spi_delay <= 0;
            spi_sck <= 0;
            spi_so <= 0;
            spi_rdy <= 0;
            spdr_r <= 0;
            spdr_t <= 0;
            spi_cnt <= 0;
        end
    else
        begin
            if(spi_delay > 0) spi_delay <= spi_delay - 1;
            case(spi_state)
                0: //IDDLE
                    begin
                        spi_sck <= 0;
                        spi_so <= 0;
                        spi_rdy <= 0;
                        spi_state <= 0;
                        if(SPI_START)spi_state <= 1;
                    end
                1: //
                    begin
                        spi_cnt <= 8;
                        spi_rdy <= 1;
                        spi_state <= 2;
                    end
                2: //
                    begin
                        spi_so <= spidr_w[spi_cnt - 1];
                        spi_delay <= prescaller;
                        spi_state <= 3;
                    end              
                3: //
                    begin
                        if(spi_delay == 0)
                            begin
                                spi_sck <= 1;
                                spi_delay <= prescaller;
                                spi_state <= 4;
                            end
                        else spi_state <= 3;
                    end
                4: //
                    begin
                        if(spi_delay == 0)
                            begin
                                spi_sck <= 0;
                                spdr_t[spi_cnt - 1] <= MISO;
                                spi_cnt <= spi_cnt - 1;
                                spi_delay <= prescaller;
                                spi_state <= 5;
                            end
                        else spi_state <= 4;
                    end  
                5: //
                    begin
                        if(spi_cnt == 0) spi_state <= 6;
                        else spi_state <= 2;
                    end                                           
                6: //END
                    begin
			spdr_r <= spdr_t;
                        spi_state <= 0;
                        spi_rdy <= 0;
                        spi_so <= 0;
                    end
            endcase
        end
end

assign SPI_DOUT = spdr_r;
assign SPI_BSY = spi_rdy;
assign MOSI = spi_so;
assign SCK = spi_sck;
assign WP = 1;
assign HOLD = 1;

//Конечный автомат проигрывателя
reg[4:0]play_state,ret;
reg[7:0]dspi,pcm;
reg cs, run_spi;

localparam SPI_EXCHANGE = 29;

always@(posedge clk or negedge rst)
begin
	if(!rst)
		begin
			play_state <= 0;
			cs <= 0;
			run_spi <= 0;
			dspi <= 0;
			ret <= 0;
			pcm <= 0;
		end
	else
		begin
			case(play_state)
				0://IDDLE
					begin
						if(wav_clk) play_state <= 1;
						else play_state <= 0;
					end
				1://Начало цикла чтения SPI (отправка команды 0x03)
					begin
						cs <= 1;
						dspi <= 8'h03;
						ret <= 2;
						play_state <= SPI_EXCHANGE;
					end
				2://Отправка старшего байта адреса
					begin
						dspi <= add_cnt[23:16];
						ret <= 3;
						play_state <= SPI_EXCHANGE;
					end
				3://Отправка среднего байта адреса
					begin
						dspi <= add_cnt[15:8];
						ret <= 4;
						play_state <= SPI_EXCHANGE;
					end
				4://Отправка младшего байта адреса
					begin
						dspi <= add_cnt[7:0];
						ret <= 5;
						play_state <= SPI_EXCHANGE;
					end
				5://Отправка байта ожидания 0xFF
					begin
						dspi <= 8'hFF;
						ret <= 6;
						play_state <= SPI_EXCHANGE;
					end
				6://Деактивируем флешку
					begin
						cs <= 0;
						pcm <= SPI_DOUT;
						play_state <= 7;
					end
				7://Ожидаем, пока wav_clk == 1, чтобы не пойти на второй круг
					begin
						if(wav_clk)play_state <= 7;
						else play_state <= 0;
					end					
///////////////////////////////////////////////////////////////////////////////////					
				29://SPI_EXCHANGE_ROUTINE (подпрограма обмена по SPI)
					begin
						run_spi <= 1; //Start SPI
						play_state <= 30;
					end
				30://Ожидаем, пока !SPI_BSY
					begin
						if(SPI_BSY)
							begin
								run_spi <= 0;
								play_state <= 31;
							end
						else play_state <= 30;
					end
				31://Ожидаем, пока SPI_BSY
					begin
						if(SPI_BSY)play_state <= 31;
						else play_state <= ret;
					end
			endcase
		end
end

assign CMP = pcm;
assign CS = ~cs;
assign SPI_DIN = dspi;
assign SPI_START = run_spi;

endmodule






