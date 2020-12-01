-- ADC test
-- can I use the 10M adc clock for UART TX? Then they will be phase locked
-- think about syncing between ADC and sampler, if they are not exaclty in sync, samples will be lost or duplicated
-----------------------------------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
------------------------------------------------------------------------------------------------------------------------------
entity ADC_UART is
	port(
		clk_50M : in std_logic;
		clk_10M : in std_logic;
		rst : in std_logic;
		sample : in std_logic;
		txd : out std_logic;
		--debug
		fft_real : out std_logic_vector(15 downto 0);
		fft_imag : out std_logic_vector(15 downto 0)
		);
end ADC_UART;
-------------------------------------------------------------------------------------------------------------------------------
architecture behaviour of ADC_UART is
		
	
	component ADC is
	port (
		CLOCK : in  std_logic; 
		RESET : in  std_logic; 
		CH0   : out std_logic_vector(11 downto 0)        
		);
	end component;
	
 	component uart_pll is
		PORT (
			inclk0 : in std_logic;
			c0 : out std_logic;
			C1 : out std_logic
			);
		end component uart_pll;
				
  
  component uart_tx is
    generic (
      g_CLKS_PER_BIT : integer := 87   -- Needs to be set correctly
      );
    port (
      i_clk       : in  std_logic;
      i_tx_dv     : in  std_logic;
      i_tx_byte   : in  std_logic_vector(7 downto 0);
      o_tx_active : out std_logic;
      o_tx_serial : out std_logic;
      o_tx_done   : out std_logic
      );
  end component uart_tx;
	
-------------------------------------------------------------------------------------------------------------------------------------------	
	type t_sm_main is (idle, sampling, send_sample, waiting);
	signal sm_main : t_sm_main := idle;
	
	signal test : unsigned(13 downto 0);
	signal test2 : std_logic_vector(13 downto 0);
	signal sign1 : signed(13 downto 0);
	signal sign2 : signed(13 downto 0);
	signal signresult : signed(13 downto 0);
	
	-- uses a 100 MHz Clock
	-- Want to interface to 115200 baud UART
	-- 10000000 / 115200 = 87 Clocks Per Bit.
	constant c_CLKS_PER_BIT : integer := 87;
	
	signal clk_50M_s : std_logic;				-- system clock
	signal clk_10M_s : std_logic;				-- pll generated for UART
	
	signal s_rst : std_logic;					-- connected to push button for reset (not currently, held low)
	signal sample_s : std_logic;				-- connected to a puch button, used to know when to send a sample
	
	--LFSR signals
	signal s_rand_num : std_logic_vector(5 downto 0);
	signal s_rand_enb : std_logic;
	signal s_seed : std_logic_vector(5 downto 0) := "000000";
	signal s_seed_dv : std_logic := '0';
	signal noise : std_logic_vector(11 downto 0) := "000000000000";
	
	-- NCO Noise signals
	signal NCO_clock 		: std_logic;
	signal s_NCO_enb 		: std_logic := '1';
	signal s_phi_inc_i 	: std_logic_vector(31 downto 0) := "00110011001100110011001100110011";
	signal s_fsin_o 		: std_logic_vector(9 downto 0);
	signal s_NCO_valid 	: std_logic;
	signal s_NCO_reset_n : std_logic := '1';
	signal s_noise_temp	: std_logic_vector(13 downto 0);
	
	-- UART TX signals
	signal r_CLOCK     	: std_logic                    := '0';
	signal r_TX_DV     	: std_logic                    := '0';
	signal r_TX_BYTE   	: std_logic_vector(7 downto 0) := (others => '0');
	signal w_TX_ACTIVE	: std_logic;
	signal w_TX_SERIAL 	: std_logic;
	signal w_TX_DONE   	: std_logic;
	
	-- ADC signals
	signal s_ch0 			: std_logic_vector(11 downto 0);
	
	-- TX signals
	signal tx_upper1 : std_logic_vector(7 downto 0);
	signal tx_lower1 : std_logic_vector(7 downto 0);
	signal tx_upper2 : std_logic_vector(7 downto 0);
	signal tx_lower2 : std_logic_vector(7 downto 0);
	signal tx_upper3 : std_logic_vector(7 downto 0);
	signal tx_lower3 : std_logic_vector(7 downto 0);
	signal last_byte_was_upper :  boolean := true;
	
	-- State machine timing 
	signal counter : natural := 0;
	signal counter2 : natural := 0;
	signal sample_count : integer := 0;
	signal send_count : integer := 0;
	
	-- Arrays for storing data
	type array_512x14_t is array (511 downto 0) of std_logic_vector(13 downto 0);
	signal s_sample_data : array_512x14_t;
	
	
	-- debug
	signal test_value : std_logic_vector(13 downto 0);
	signal test_output : std_logic_vector(15 downto 0);

	
	
begin
	
	-- instantiate pll for 10MHz clock gen
	uart_pll_inst : uart_pll 
		PORT MAP (
			inclk0	 => clk_50M_s,
			c0	 => r_CLOCK,
			c1 => NCO_clock
			);
		
 
  -- instantiate UART transmitter
  UART_TX_INST : uart_tx
		generic map (
			g_CLKS_PER_BIT => c_CLKS_PER_BIT
			)
		port map (
			i_clk       => r_CLOCK,
			i_tx_dv     => r_TX_DV,
			i_tx_byte   => r_TX_BYTE,
			o_tx_active => W_TX_ACTIVE,
			o_tx_serial => w_TX_SERIAL,
			o_tx_done   => w_TX_DONE
			);

	-- instanciate ADC
	u0 : ADC port map(
		CLOCK => clk_10M_s,
		RESET => s_rst,
		CH0 => s_ch0
		);

	-- port wiring
	clk_50M_s <= clk_50M;
	clk_10M_s <= clk_10M;
	txd <= W_TX_SERIAL;	
	sample_s <= sample;
	
	s_rst <= '0';							-- hold ADC out of reset
	s_rand_enb <= '1';					-- hold enable lfsr
----------------------------------------------------------------------------------------------------------------------------------------	
	main : process(clk_50M_s)
	begin
		if(rising_edge(clk_50M_s)) then
			
			case sm_main is
				
				when idle =>															-- sit in idle until sample button is pressed		
					if (sample_s = '0') then
						counter <= 0;
						test_value <= "00000000000000";
						sample_count <= 0;
						sm_main <= sampling;
					else
						sm_main <= idle;
					end if;

				when sampling =>
					if (sample_count = 512) then										-- check to see if 512 samples have been taken
						sample_count <= 0;
						counter <= 0;
						--s_NCO_reset_n <= '1';
						--s_NCO_enb <= '1';
						sm_main <= send_sample;
					else
						if(counter < 598) then         								-- wait 50 clocks (every 1 us), adjust this to change sample rate
							counter <= counter + 1;
							sm_main <= sampling;
						elsif(counter > 597) then 										-- reset counter, increment sample count and sample the adc channel
							counter <= 0;
							s_sample_data(sample_count - 1) <= "00" & s_ch0;	-- stores 12 bit ADC value and padds to 14 bits
							sample_count <= sample_count + 1;
							-- USE FOR DEBUG, samples 1,2,3,4...
							--test_value <= std_logic_vector(to_unsigned(to_integer(unsigned( test_value )) + 1, 14));
							--s_samples14(sample_count) <= test_value;
							sm_main <= sampling;
						end if;
					end if;
				
				when send_sample =>
					if (send_count = 512) then									
						if (counter < 1000) then
							counter <= counter + 1;
						else
							counter <= 0;
							send_count <= 0;
							r_TX_DV <= '0';
							last_byte_was_upper <= true;
							sm_main <= waiting;
						end if;
					elsif (send_count < 512) then																	
						tx_upper1 <= std_logic_vector(resize(signed(s_sample_data(send_count)(13 downto 8)), tx_upper1'length));
						tx_lower1 <= s_sample_data(send_count)(7 downto 0);					-- CAN I MOVE THESE TWO STATEMENTS INTO THE IF STATEMENTS BELOW TO IMPROVE EFFICIENCY????????
						
						-- USE THESE LINES FOR DEBUG, SENDS SEND COUNT INSTEAD OF VALUES IN ARRAY
						test_output <= std_logic_vector(to_unsigned(send_count, 16));
						--tx_upper1 <= test_output(15 downto 8);		-- split the array item into two bytes, upper and lower
						--tx_lower1 <= test_output(7 downto 0);
						
						if (w_TX_ACTIVE = '0') then								-- ensure not already sending
							if (counter < 1000) then								-- wait 100 ticks to be safe
								counter <= counter + 1;
							elsif (counter > 99) then
								counter <= 0;
								if (last_byte_was_upper = true) then				-- if the last byte sent was an upper, send lower
									r_TX_BYTE <= tx_lower1;
									r_TX_DV <= '1';
									last_byte_was_upper <= false;
									sm_main <= send_sample;
								else															-- if the last byte sent was a lower, send upper and increment the sending index
									r_TX_BYTE <= tx_upper1;
									r_TX_DV <= '1';
									last_byte_was_upper <= true;
									send_count <= send_count + 1;
									sm_main <= send_sample;
								end if;
							end if;
						else
							r_TX_DV <= '0';												-- stop trying to send if already sending
						end if;
					end if;		

				when waiting =>														-- wait for 1 second after sample if sent to prevent chaining samples unintentionally 
					if (counter > 49999999) then
						counter <= 0;
						sm_main <= idle;
					else
						counter <= counter + 1;
						sm_main <= waiting;
					end if;
					
					
				when others =>															-- just in case
					sm_main <= idle;
				
			end case;
		end if;
	end process;
end behaviour;