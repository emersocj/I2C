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
  generic (BUSSIZE    		: integer:=4;							-- Number of I2C devices on the bus
  		   MAXCHANNELS 		: integer:= 8;							-- Number of channels on the I2C devices being used( May need to change)
  		   STARTADDRESS		: std_logic_vector:="0001001";			-- First I2C address "1001000"
  		   INITDATA			: std_logic_vector:="10000000"			-- Data sent to the I2C devices to init them
  	);
  Port ( 
  	BUSY			: in 	 	std_logic;							-- Indicates that a transfer is occuring
  	INIT            : in 		std_logic;							-- Restart I2C device initalization
  	READ_ENABLE     : in        std_logic;							-- Enables reading from the devices
  	ACK_ERROR		: buffer 	std_logic;							-- Indicastes an acknowledgement error has occured
  	RW				: out 		std_logic;							-- Indicates read or write operation, 0 for a write, 1 for a read
  	ADDR			: out 		std_logic_vector(6 downto 0);		-- Address of the I2C device in
  	ENA 			: out 		std_logic;							-- Enables the I2C master device
  	DATA_WR			: out		std_logic_vector(7 downto 0);		-- Data to be writen to the I2C master device
  	DATA_RD			: in 		std_logic_vector(7 downto 0);		-- data read from the I2C master device
  	INIT_ERROR      : out 		std_logic_vector(3 downto 0);		-- Indicates which devices failed to init
  	POLL_ERROR		: out		std_logic_vector(3 downto 0);		-- Indicates which devices failed to poll
  	DATA_OUT		: out 		std_logic_vector(17 downto 0);		-- Data sent to output fifo
  	DATA_VLD        : out       std_logic:='0';						-- Indicates data out is valid

  	RESET_N			: in		std_logic;							-- Async Reset
  	CLK				: in        std_logic        					-- Board clk
  );
end i2c_userapp;

architecture Behavioral of i2c_userapp is

-- I2C registers/buffers
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

-- For reset delay
signal start_cnt   : integer:=200;									-- Delay before start up
signal start_ena   : std_logic:='0';								-- Counter finished flag

-- For I2C device retries
signal retry_cnt   : integer:=0;									-- Counts the amount of init or poll failues
signal retry_rst   : std_logic:='0';								-- Reset the retry_cnt counter							

-- For Switching I2C devices and channels
signal init_cnt    : integer:=0;
signal channel_cnt : integer:=0;
signal read_cnt    : integer:=0;
signal wait_cnt    : integer:=10000;


-- Buffers
signal dout	   	   : std_logic_vector(17 downto 0);
signal i2c_addr    : std_logic_vector(6 downto 0):="0000000";		-- Address buffer

-- I2C UserApp state machine
type INIT_STATE_TYPE is (start,ena_in,ack_in,next_in,idle,command,commandAck,channelSelect,readUpper,readLower,readAck,wait_s,done);
signal init_cs 			: init_state_type:=start;

begin

	-- Connect I2C wires
	i2c_busy 	<= BUSY;
	RW 			<= i2c_rw;
	DATA_WR 	<= i2c_datawr;
	i2c_datard  <= DATA_RD;
	ENA 		<= i2c_enable;
	i2c_ackerror<= ACK_ERROR;
	ADDR <= i2c_addr;
	DATA_OUT <= dout;

	-- Registers for Edge detectors
	RISING_INIT: process(CLK)
	begin
		if(rising_edge(CLK))then        						-- Synchronize
			init_prev <= INIT;									-- Register for init
			busy_prev <= i2c_busy;								-- Register for busy
			ack_prev  <= ACK_ERROR;								-- Register for Ack errors
		end if;
	end process;

	-- Timer used to delay the start of the initialization process
	ENABLE_DELAY: process(CLK)
	begin
		if(rising_edge(CLK)) then                           				-- Synchronize
			start_ena <= '0';												-- To prevent latches
			if(RESET_N = '0' or (init_prev = '0' and INIT = '1')) then   	-- If reset or reinitialize
				start_cnt <= 200;											-- Reset the counter
			elsif(start_cnt /= 0) then
				start_cnt <= start_cnt - 1;									-- Count down
			else
				start_ena <= '1';											-- When count is finished init state machine
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
			i2c_rw <= '0';		   										
			i2c_enable <= '0';
			i2c_datawr <= i2c_datawr;
			i2c_addr <= i2c_addr;
			retry_rst <='0';											
			data_vld  <= '0';											
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
						i2c_addr <= "10010" & std_logic_vector(to_unsigned(read_cnt,2)) ; 	-- Address of first I2C device
						i2c_datawr <= '1' & std_logic_vector(to_unsigned(channel_cnt,3) & "1100") ;  				-- Data to enable channel 1										
						i2c_enable <= '1';						-- Start I2C transfer
						init_cs <= command;						-- Move on to command state
					end if;				
				when command =>									-- Holds enable high until transfer begins
					i2c_enable <= '1';
					if(i2c_busy = '1' and busy_prev = '0') then 	-- Wait for transfer to start
						i2c_enable <= '0';								-- Disable I2C master so only 1 transfer occurs
						init_cs <= commandACK ;					-- Enter ack state
					end if;
				when commandAck =>
					if(i2c_busy = '0' and busy_prev = '1') then -- Wait for the transfer to finish
						if(ACK_ERROR = '1') then             	-- If the device did not acknowledge the transfer
							if(retry_cnt = 3) then              -- If failed to initialize 3 times
								poll_error(init_cnt) <= '1';	-- Set flag that device 1 did not ack
								retry_rst <= '1';				-- Reset the retry_cnt counter 
								read_cnt <= read_cnt + 1;		-- Move to next Device
								channel_cnt <= 0;				-- Reset channel pointer
								i2c_enable <= '0';				-- Disable transfer
								init_cs <= channelSelect;		-- Enter channel select
							else                                -- Try to initialze the device again
								i2c_enable <= '1';				-- Turn on the I2C master
								init_cs <= command;				-- Move to initialize device
							end if;
						else                                    -- Transfer was successful
							retry_rst <= '1';					-- Reset the retry_cnt counter
							i2c_rw <= '1';						-- Set rw flag to READ
							i2c_enable <= '1';					-- Start Device Read
							init_cs <= readUpper;				-- Move to read states
						end if;
					end if;
				when readUpper =>								-- Read upper nibble of 12-bit data and append identifier info
					i2c_rw <= '1';								-- Hold read flag
					i2c_enable <= '1';
					if(i2c_busy = '0' and busy_prev = '1') then     -- When transfer is finished
						dout(17 downto 16) <= std_logic_vector(to_unsigned(read_cnt,2)); 	-- Append Device number
						dout(15 downto 12) <= std_logic_vector(to_unsigned(channel_cnt,4));  -- Append Channel Number
						dout(11 downto 8)  <= DATA_RD(3 downto 0);							-- Appen upper 4 bytes of data
						init_cs <= readLower;					-- Enter read lower byte state
					end if;	
				when readLower =>
					i2c_rw <= '1';									-- Hold read flag
					if(i2c_busy = '0' and busy_prev = '1') then     -- Wait for transfer to finish
						dout(7 downto 0) <= DATA_RD;			-- Append lower byte of data
						data_vld <= '1';						-- Push data into fifo
						init_cs <= channelSelect;				-- Enter channel select state
					end if;
				when channelSelect =>
					if(read_cnt = BUSSIZE)then 					-- If at last device
						read_cnt 	<= 0;						-- Move to first device
						channel_cnt <= 0;						-- Move to fist channel
					elsif(channel_cnt = MAXCHANNELS - 1) then       -- If at the last channel
						read_cnt <= read_cnt + 1;				-- Move to next device
						channel_cnt <= 0;						-- Move to first channel
					else
						channel_cnt <= channel_cnt + 1;			-- Increment channel
					end if;
					init_cs <= wait_s;							-- Move to idle state
				when wait_s =>
					if(wait_cnt /= 0) then
						wait_cnt <= wait_cnt - 1;
					else 
						wait_cnt <= 1000;
						init_cs <= idle;
					end if;
			-- Unsafe State machine is implemented			
			when others =>
				init_cs <= start;
		end case;
		end if;
	end if;
end process;

end Behavioral;
