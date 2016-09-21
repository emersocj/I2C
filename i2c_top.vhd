----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 09/02/2016 01:36:33 PM
-- Design Name: 
-- Module Name: i2c_top - Structural
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity i2c_top is
  Port ( 
  	INIT   			: in        std_logic;
  	READ_ENABLE     : in        std_logic;
  	SDA				: inout		std_logic;
  	SCL             : inout	    std_logic;
  	DATA_VLD		: out       std_logic;
  	DATA_OUT        : out       std_logic_vector(17 downto 0);

  	RESET_N			: in        std_logic;
    CLK 			: in 		std_logic

  	);
end i2c_top;

architecture Structural of i2c_top is

component i2c_userapp is
  generic (
  	BUSSIZE    			: integer:=4;
  	MAXCHANNELS 		: integer:= 8;
    STARTADDRESS		: std_logic_vector:="1010000";
    INITDATA			: std_logic_vector:="10101010"
  	);
  Port ( 
  	DATA_RD			: in 		std_logic_vector(7 downto 0);
  	BUSY			: in 	 	std_logic;
  	INIT            : in 		std_logic;
  	READ_ENABLE     : in        std_logic;
  	ACK_ERROR		: buffer 	std_logic;
  	RW				: out 		std_logic;
  	ADDR			: out 		std_logic_vector(6 downto 0);
  	ENA 			: out 		std_logic;
  	DATA_WR			: out		std_logic_vector(7 downto 0);

  	INIT_ERROR      : out 		std_logic_vector(3 downto 0);
  	POLL_ERROR		: out		std_logic_vector(3 downto 0);
  	DATA_OUT		: out 		std_logic_vector(17 downto 0);
  	DATA_VLD        : out       std_logic:='0';

  	RESET_N			: in		std_logic;
  	CLK				: in        std_logic        
  );
end component;

component i2c_master is
  generic(
    input_clk : integer := 100_000_000; --input clock speed from user logic in hz
    bus_clk   : integer := 400_000);   --speed the i2c bus (scl) will run at in hz
  port(
    ENA       : in     std_logic;                    --latch in command
    ADDR      : in     std_logic_vector(6 downto 0); --address of target slave
    RW        : in     std_logic;                    --'0' is write, '1' is read
    DATA_WR   : in     std_logic_vector(7 downto 0); --data to write to slave
    BUSY      : out    std_logic;                    --indicates transaction in progress
    DATA_RD   : out    std_logic_vector(7 downto 0); --data read from slave
    ACK_ERROR : buffer std_logic;                    --flag if improper acknowledge from slave
    SDA       : inout  std_logic;                    --serial data output of i2c bus
    SCL       : inout  std_logic;                    --serial clock output of i2c bus

    RESET_N   : in     std_logic;                    --active low reset
	CLK       : in     std_logic                     --system clock    
  );
end component;

signal ena_i			: std_logic:='0';
signal addr_i			: std_logic_vector(6 downto 0):="0000000";
signal rw_i     		: std_logic:='0';
signal data_wr_i		: std_logic_vector(7 downto 0):=x"00";
signal busy_i   		: std_logic:='0';
signal data_rd_i		: std_logic_vector(7 downto 0):=x"00";
signal ack_error_i		: std_logic:='0';

begin 

master: i2c_master 
generic map(
		input_clk  => 100_000_000,
		bus_clk    => 400_000
)
port map(
		ENA 		=> 	ena_i,
		ADDR 		=> 	addr_i,
		RW 			=>	rw_i,
		DATA_WR 	=> 	data_wr_i,
		BUSY		=> 	busy_i,
		DATA_RD 	=> 	data_rd_i,
		ACK_ERROR 	=> 	ack_error_i,
		SDA 		=> 	SDA,
		SCL 		=>	SCL,

		RESET_N 	=> 	RESET_N,
		CLK 		=> 	CLK
);
	
user_app: i2c_userapp
generic map (
  	BUSSIZE    		=> 4,
  	MAXCHANNELS 	=> 8,
    STARTADDRESS    => "1010000",
    INITDATA	    => "10101010"
  	)
port map(
		DATA_RD    => data_rd_i,

		ENA        => ena_i,
		ADDR       => addr_i,
		RW         => rw_i,
		DATA_WR    => data_wr_i,
		BUSY       => busy_i,
		ACK_ERROR  => ack_error_i,

		READ_ENABLE => READ_ENABLE,		
		INIT       => INIT,
		DATA_VLD   => DATA_VLD,
		DATA_OUT   => DATA_OUT,

		RESET_N	   => RESET_N,
		CLK        => CLK
	);

end Structural;
