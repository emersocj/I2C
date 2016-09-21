----------------------------------------------------------------------------------
-- Company: Alion Science and Technology
-- Engineer: Cody Emerson
-- 
-- Create Date: 09/02/2016 12:29:19 PM
-- Design Name: 
-- Module Name: i2c_userapp - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 				Userapp for power monitor ADCs
-- Dependencies: 
-- 				
-- Revision: 0.00
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity i2c_userapp is
  generic (BUSSIZE    		: integer:=4;
  		   MAXCHANNELS 		: integer:= 8;
  		   STARTADDRESS		: std_logic_vector:="1010000";
  		   INITDATA			: std_logic_vector:="10101010"
  	);
  Port ( 
  	BUSY			: in 	 	std_logic;
  	INIT            : in 		std_logic;
  	READ_ENABLE     : in        std_logic;
  	ACK_ERROR		: buffer 	std_logic;
  	RW				: out 		std_logic;
  	ADDR			: out 		std_logic_vector(6 downto 0);
  	ENA 			: out 		std_logic;
  	DATA_WR			: out		std_logic_vector(7 downto 0);
  	DATA_RD			: in 		std_logic_vector(7 downto 0);
  	INIT_ERROR      : out 		std_logic_vector(3 downto 0);
  	POLL_ERROR		: out		std_logic_vector(3 downto 0);
  	DATA_OUT		: out 		std_logic_vector(17 downto 0);
  	DATA_VLD        : out       std_logic:='0';

  	RESET_N			: in		std_logic;
  	CLK				: in        std_logic        
  );
end i2c_userapp;

architecture Behavioral of i2c_userapp is

signal i2c_enable    : std_logic:='0';
signal i2c_datawr	 : std_logic_vector(7 downto 0):=x"00";
signal i2c_datard	 : std_logic_vector(7 downto 0):=x"00";
signal i2c_rw        : std_logic:='0';
signal i2c_busy      : std_logic:='0';
signal i2c_ackerror  : std_logic:='0';

-- For edge detectors
signal busy_prev   : std_logic;										-- For busy edge detectors
signal ack_prev    : std_logic:='0';								-- For ack error edge detectors
signal init_prev   : std_logic:='0';								-- For init edge detector

signal start_cnt   : integer:=200;									-- Delay before start up
signal start_ena   : std_logic:='0';								-- Counter finished flag

-- For I2C device retries
signal retry_cnt   : integer:=0;									-- Counts the amount of init or poll failues
signal retry_rst   : std_logic:='0';								-- Reset the retry_cnt counter							

-- For Switching I2C devices and channels
signal init_cnt    : integer:=0;
signal channel_cnt : integer:=0;
signal read_cnt    : integer:=0;


-- Buffers
signal data_in	   : std_logic_vector(17 downto 0);
signal i2c_addr      : std_logic_vector(6 downto 0):="0000000";		-- Address buffer

-- I2C UserApp state machine
type INIT_STATE_TYPE is (start,ena_in,ack_in,next_in,idle,command,commandAck,channelSelect,readUpper,readLower,readAck,done);
signal init_cs 			: init_state_type:=start;

begin

	i2c_busy <= BUSY;
	RW <= i2c_rw;
	DATA_WR <= i2c_datawr;
	i2c_datard  <= DATA_RD;
	ENA <= i2c_enable;
	i2c_ackerror <= ACK_ERROR;

	ADDR <= i2c_addr;
	DATA_OUT <= data_in;
	-- Registers for Edge detectors
	RISING_INIT: process(CLK)
	begin
		if(rising_edge(CLK))then        					-- Synchronize
			init_prev <= INIT;									-- Register for init
			busy_prev <= i2c_busy;									-- Register for busy
			ack_prev  <= ACK_ERROR;								-- Register for Ack errors
		end if;
	end process;

	-- Timer used to delay the start of the initialization process
	ENABLE_DELAY: process(CLK)
	begin
		if(rising_edge(CLK)) then                           	-- Synchronize
			start_ena <= '0';									-- State Machine enable
			if(RESET_N = '0' or (init_prev = '0' and INIT = '1')) then   	-- If reset or reinitialize
				start_cnt <= 200;								-- Reset the counter
			elsif(start_cnt /= 0) then
				start_cnt <= start_cnt - 1;						-- Count down
			else
				start_ena <= '1';								-- When count is finished init state machine
			end if;
		end if;
	end process;

	-- retry_cnt counter used to try an I2C device again when an ack error occurs
	retry_cnt_CONTROL: process(CLK)
	begin
		if(rising_edge(CLK)) then
			if(retry_rst = '1') then
				retry_cnt <= 0;
			elsif(ACK_ERROR = '1' and ack_prev = '0') then
				retry_cnt <= retry_cnt + 1;
			end if;
		end if;
	end process;

	I2C_STATE_MACHINE: process(clk) 								--Start state machine for controlling ADCs
	begin
	if(rising_edge(CLK)) then
		if((init_prev = '0' and INIT = '1') or RESET_N = '0')then
			init_cs <= start;
		else
			-- Inertial Delay
			i2c_rw <= '0';		   										-- Set flag to write
			i2c_enable <= '0';
			i2c_datawr <= i2c_datawr;
			i2c_addr <= i2c_addr;

			retry_rst <='0';											-- Turn on reset counter
			data_vld  <= '0';											-- To push onto fifo
			init_cs   <= init_cs;

			case init_cs is
				when start => 								
					if(start_ena = '1' and i2c_busy = '0') then     -- Wait for the startup delay to finish
						i2c_addr <= STARTADDRESS; 					-- Address of first I2C device
						i2c_datawr <= INITDATA;  					-- Data to init the I2C device
						i2c_enable <= '1';							-- Enable the I2C transfer
						init_cs <= ena_in;							-- Enter first init state							
					else                   							-- Start first device init 
						init_cs <= start;							-- Stay in start state
					end if;
				when ena_in =>
					i2c_enable <= '1';
					if(i2c_busy = '1' and busy_prev = '0') then 	-- Wait for the transfer to start
						i2c_enable <= '0';							-- Disable the device so only 1 transfer occurs
						init_cs <= ack_in;							-- Enter first ack state
					end if;
				when ack_in =>
					if(i2c_busy = '0' and busy_prev = '1') then 	-- Wait for the transfer to finish
						if(ACK_ERROR = '1') then             		-- If the device did not acknowledge the transfer
							if(retry_cnt = 3) then              	-- If failed to initialize 3 times
								init_error(init_cnt) <= '1';		-- Set flag that device 1 did not initalize	
								retry_rst <= '1';					-- Reset the retry_cnt counter 
								init_cnt <= init_cnt + 1;	
								init_cs <= next_in;					-- Move on to initalize device 2
							else                                
								i2c_addr <= STARTADDRESS; 			-- Address of first I2C device
								i2c_datawr <= INITDATA;  			-- Data to init the I2C device								
								i2c_enable <= '1';					-- retry_cnt the transfer
								init_cs <= ena_in;					-- Move to initialize first device
							end if;
						else                                    	-- Transfer was successful
							retry_rst <= '1';						-- Reset the retry_cnt counter
							init_cnt <= init_cnt + 1;				-- Move onto next device
							init_cs <= next_in;						-- Move to next device state
						end if;
					end if;
				when next_in =>
					if(init_cnt /= BUSSIZE)  then   			-- Check if all devices have been initialized
						i2c_addr <= std_logic_vector(unsigned(i2c_addr) + 1 );					-- Set Address of next I2C device
						i2c_enable <= '1';								-- Turn on the I2C master
						init_cs <= ena_in;						-- Move to init2 state
					else
						i2c_enable <= '0';						-- Enable the I2C master
						init_cnt <= 0;							-- Move back to first device
						init_cs <= idle;						-- Enter idle state
					end if;
				when idle =>
					if(READ_ENABLE = '1') then
						i2c_addr <= "10010" & std_logic_vector(to_unsigned(init_cnt,2)) ; 	-- Address of first I2C device
						i2c_datawr <= "10101010";  			-- Data to enable channel 1											-- TODO Data that will be written to the device
						i2c_enable <= '1';					-- STart I2C transfer
						init_cs <= command;					-- Move on to command state
					end if;				
				when command =>									-- Holds enable high until transfer begins
					i2c_enable <= '1';
					if(i2c_busy = '1' and busy_prev = '0') then 	-- Wait for transfer to start
						i2c_enable <= '0';								-- Disable I2C master so only 1 transfer occurs
						init_cs <= commandACK ;					-- Enter ack state
					end if;
				when commandAck =>
					if(i2c_busy = '0' and busy_prev = '1') then 	-- Wait for the transfer to finish
						if(ACK_ERROR = '1') then             	-- If the device did not acknowledge the transfer
							if(retry_cnt = 3) then              -- If failed to initialize 3 times
								poll_error(init_cnt) <= '1';	-- Set flag that device 1 did not ack
								retry_rst <= '1';				-- Reset the retry_cnt counter 
								read_cnt <= read_cnt + 1;		-- Move to next Device
								channel_cnt <= 0;				-- Reset channel pointer
								i2c_enable <= '0';						-- Disable transfer
								init_cs <= channelSelect;		-- Enter channel select
							else                                -- Try to initialze the device again
								i2c_enable <= '1';						-- Turn on the I2C master
								init_cs <= command;				-- Move to initialize first device
							end if;
						else                                    -- Transfer was successful
							retry_rst <= '1';					-- Reset the retry_cnt counter
							i2c_rw <= '1';							-- Set rw flag to READ
							i2c_enable <= '1';							-- Start Device Read
							init_cs <= readUpper;				-- Move to init2 state
						end if;
					end if;
				when readUpper =>								-- Read upper nibble of 12-bit data and append identifier info
					i2c_rw <= '1';									-- Hold read flag
					i2c_enable <= '1';					
					if(i2c_busy = '0' and busy_prev = '1') then     -- When transfer is finished
						data_in(17 downto 16) <= std_logic_vector(to_unsigned(read_cnt,2)); 	-- Append Device number
						data_in(15 downto 12) <= std_logic_vector(to_unsigned(channel_cnt,4));  -- Append Channel Number
						data_in(11 downto 8)  <= DATA_RD(3 downto 0);							-- Appen upper 4 bytes of data
						init_cs <= readLower;					-- Enter read lower byte state
					end if;	
				when readLower =>
					i2c_rw <= '1';								-- Hold read flag
					i2c_enable <= '0';
					if(i2c_busy = '0' and busy_prev = '1') then -- Wait for transfer to finish
						data_in(7 downto 0) <= DATA_RD;			-- Append lower byte of data
						data_vld <= '1';						-- Push data into fifo
						init_cs <= channelSelect;				-- Enter channel select state
					end if;
				when channelSelect =>
					if(read_cnt = BUSSIZE)then 					-- If at last device
						read_cnt 	<= 0;						
						channel_cnt <= 0;
					elsif(channel_cnt = MAXCHANNELS) then
						read_cnt <= init_cnt + 1;
						channel_cnt <= 0;
					else
						channel_cnt <= channel_cnt + 1;
					end if;
					init_cs <= idle;
			-- Unsafe State machine is implemented			
			when others =>
				init_cs <= start;
		end case;
		end if;
	end if;
end process;

end Behavioral;
