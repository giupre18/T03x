
-- IEEE packages
library ieee;
use ieee.math_real.all;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

-- Local packages
use work.riscv_klessydra.all;

entity PMP_Unit is
  generic (
    PMP_REGIONS : natural := 64 -- Numero di regioni PMP supportate
  );
  port (
    -- Data Memory interfece 
    data_addr_o                : in std_logic_vector(31 downto 0);
    load_exception_pmp         : out std_logic;
    store_exception_pmp        : out std_logic;
    -- program memory interface
    instr_addr_o               : in std_logic_vector(31 downto 0);
    exception_pmp              : out std_logic;
    -- signal for debug
    addr_start_debug           : out std_logic_vector(31 downto 0);
    addr_end_debug             : out std_logic_vector(31 downto 0);
    --PMP Registers Inputs
    addr_start                 : in addr_unsigend ;
    addr_end                   : in addr_unsigend ;
    pmpcfg_in                  : in  pmpcfg_array;
    pmpaddr_in                 : in  pmpaddr_array
  );
end PMP_Unit;


architecture RTL of PMP_Unit is
  -- Defining Addressing Types


  -- Function to determine the type of matching


function extract_pmpcfg_in_field(
        pmpcfg_in : pmpcfg_array; 
        segment_index : integer
    ) return std_logic_vector is
        variable reg_index   : integer;  -- Register Index
        variable field_index : integer;  -- Field index within the register
        variable pmpcfg_in_reg  : std_logic_vector(31 downto 0); 
        variable extracted_field : std_logic_vector(7 downto 0);
    begin
        -- Calculate which register contains the requested segment
        reg_index := segment_index / 4;
        field_index := segment_index mod 4;
        pmpcfg_in_reg := pmpcfg_in(reg_index);

        -- Extract the specific field (8 bits) from the register
        case field_index is
            when 0 => extracted_field := pmpcfg_in_reg(7 downto 0);
            when 1 => extracted_field := pmpcfg_in_reg(15 downto 8);
            when 2 => extracted_field := pmpcfg_in_reg(23 downto 16);
            when 3 => extracted_field := pmpcfg_in_reg(31 downto 24);
            when others =>
                extracted_field := (others => '0'); -- Caso di errore, valore di default
        end case;

        return extracted_field;
    end function;


  function check_permissions(pmpcfg_in_field  : std_logic_vector(7 downto 0); access_type : std_logic_vector(1 downto 0)) return std_logic is
  begin
    -- cfg(2): X (Execute)
    -- cfg(1): W (Write)
    -- cfg(0): R (Read)
    case access_type is
      when "10" => -- Fetch
        return pmpcfg_in_field (2); -- Bit X
      when "00" => -- Load
        return pmpcfg_in_field (0); -- Bit R
     when "01" => -- Store 
        return pmpcfg_in_field (1); -- Bit W
      when others =>
        return '0';
    end case;
  end function;



begin

process (pmpcfg_in, pmpaddr_in, data_addr_o,instr_addr_o,addr_start,addr_end)
    --variable pmpcfg_in_field : std_logic_vector(7 downto 0) ;
    --variable match_type : pmp_match_type ; 
    --variable addr_start :  unsigned(31 downto 0);
    --variable addr_end   : unsigned(31 downto 0);
    --variable diff_napot_mask : std_logic_vector(31 downto 0);
    --variable napot_mask : std_logic_vector(31 downto 0);
    --variable nand_result : unsigned(31 downto 0);
    --variable access_valid_found, access_valid_found_instr :  std_logic  := '0';
variable data_addr_unsigned : unsigned(31 downto 0) ;
variable instr_addr_unsigned : unsigned(31 downto 0) ;

variable pmpcfg_in_field : std_logic_vector(7 downto 0) ;

begin
    store_exception_pmp <='0' ;
    load_exception_pmp <= '0';
    exception_pmp <= '0';
    data_addr_unsigned := unsigned(data_addr_o);
    instr_addr_unsigned := unsigned(instr_addr_o);
    --access_valid_found := '0';
    --access_valid_found_instr := '0';
    for i in 0 to 63 loop 


if data_addr_unsigned >= addr_start(i) and data_addr_unsigned <= addr_end(i) then
              pmpcfg_in_field  := extract_pmpcfg_in_field (pmpcfg_in, i );
     -- report "pmpcfg_in_field(" & integer'image(i) & ") = " & to_hstring(pmpcfg_in_field);

           --access_valid_found := '1'; -- Accesso valido trovato
            if check_permissions(pmpcfg_in_field , "00") = '0' then
    load_exception_pmp <= '1';
    --report "addr_start_pmp: " & to_hstring(addr_start(i));
    --report "addr_end_pmp: " & to_hstring(addr_end(i));
    --report "data_addr: " & to_hstring(data_addr_unsigned);
    exit;
          end if;
          if check_permissions(pmpcfg_in_field , "01") = '0' then
    store_exception_pmp <='1' ;
   -- report "addr_start_pmp: " & to_hstring(addr_start(i));
    --report "addr_end_pmp: " & to_hstring(addr_end(i));
   -- report "data_addr: " & to_hstring(data_addr_unsigned);
        exit;

          end if;
        end if;  
        end loop;
    for i in 0 to 63 loop 

-------instr_addr_o
    if instr_addr_unsigned >= addr_start(i) and instr_addr_unsigned <= addr_end(i) then
     ---    --access_valid_found_instr:= '1'; -- Accesso valido trovato
               pmpcfg_in_field  := extract_pmpcfg_in_field (pmpcfg_in, i );

          if check_permissions(pmpcfg_in_field , "10") = '0' then
    exception_pmp <= '1';
        exit;

          end if;
       end if;   
end loop;

--addr_start_debug <= std_logic_vector(addr_start);
--addr_end_debug <= std_logic_vector(addr_end);
--report "addr_start_debug = " & to_hstring(addr_start_debug);
--report "addr_end_debug = " & to_hstring(addr_end_debug);









   --if access_valid_found = '0' then
   --   load_exception_pmp <= '1';
    --  store_exception_pmp <= '1';
  -- end if;


 --  if access_valid_found_instr = '0' then
 --     exception_pmp<= '1';
 --  end if;


   --if access_valid_found = '0' then
   --   load_exception_pmp <= '1';
    --  store_exception_pmp <= '1';
  -- end if;


 --  if access_valid_found_instr = '0' then
 --     exception_pmp<= '1';
 --  end if;





end process;


end RTL;