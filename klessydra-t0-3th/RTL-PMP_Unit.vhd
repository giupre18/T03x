
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
    pmpcfg_in                  : in  pmpcfg_array;
    pmpaddr_in                 : in  pmpaddr_array
  );
end PMP_Unit;


architecture RTL of PMP_Unit is
  -- Defining Addressing Types
  type pmp_match_type is (OFF,TOR, NA4, NAPOT);

  -- Function to determine the type of matching
function get_match_type(pmpcfg_in_field  : std_logic_vector(7 downto 0)) return pmp_match_type is
  begin
    if pmpcfg_in_field (4) = '1' and pmpcfg_in_field (3) = '1' then
      return NAPOT;
    elsif pmpcfg_in_field (4) = '1' and pmpcfg_in_field (3) = '0' then
      return NA4;
    elsif pmpcfg_in_field (4) = '0' and pmpcfg_in_field (3) = '1' then
      return TOR;
     else 
      return OFF;
    end if;
  end function;


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

process (pmpcfg_in, pmpaddr_in, data_addr_o,instr_addr_o)
    variable pmpcfg_in_field : std_logic_vector(7 downto 0) ;
    variable match_type : pmp_match_type ; 
    variable addr_start :  unsigned(31 downto 0);
    variable addr_end   : unsigned(31 downto 0);
    variable diff_napot_mask : std_logic_vector(31 downto 0);
    variable napot_mask : std_logic_vector(31 downto 0);
    variable nand_result : unsigned(31 downto 0);
    variable access_valid_found, access_valid_found_instr :  std_logic  := '0';
   

begin
    store_exception_pmp <= '0';
    load_exception_pmp <= '0';
    exception_pmp <= '0';
    access_valid_found := '0';
    access_valid_found_instr := '0';

for i in 0 to PMP_REGIONS-1 loop

      -- Extract the current pmpcfg_in register (32 bits) and the pmpcfg_in_field segment (8 bits)
      pmpcfg_in_field  := extract_pmpcfg_in_field (pmpcfg_in, i );

      -- Determine the type of matching
      match_type := get_match_type(pmpcfg_in_field );



      if match_type = TOR then
        if i = 0 then
          addr_start := (others => '0'); 
        else
          addr_start := unsigned(pmpaddr_in(i-1)) sll 2; -- Multiply by granularity
        end if;
        addr_end := unsigned(pmpaddr_in(i)) sll 2;






      elsif match_type = NAPOT then
        napot_mask := ((pmpaddr_in(i)) xor std_logic_vector(unsigned(pmpaddr_in(i)) + 1)); ------- con questa parte "prendiamo" tutti i bit finali messi a 1
        diff_napot_mask := std_logic_vector((unsigned(napot_mask) +1)sll 2); ------- con questo calcoliamo l'intervallo e con otto aggiungiamo gli 2^3 che richieno ( segna la differenza giusta) 
        nand_result := unsigned(std_logic_vector(unsigned(pmpaddr_in(i)) and unsigned(napot_mask)));
        addr_start := unsigned(pmpaddr_in(i) xor std_logic_vector(nand_result)) sll 2;
        addr_end := addr_start + unsigned(diff_napot_mask);






      elsif match_type = NA4 then
        addr_start := unsigned(pmpaddr_in(i)) sll 2 ;
        addr_end := addr_start + 4;
      end if;

-----data_addr_o


      -- Check if the login address is within the region
      if data_addr_o >= std_logic_vector(addr_start) then
       	if data_addr_o <= std_logic_vector(addr_end) then
           access_valid_found := '1'; -- Accesso valido trovato
    	    if check_permissions(pmpcfg_in_field , "00") = '0' then
                  load_exception_pmp <= '1';
          end if;
          if check_permissions(pmpcfg_in_field , "01") = '0' then
                  store_exception_pmp <= '1';
          end if;
        exit;
        end if;  
      end if;
end loop;

   addr_start_debug<= std_logic_vector(addr_start);
   addr_end_debug <= std_logic_vector(addr_end);

for i in 0 to PMP_REGIONS-1 loop

      pmpcfg_in_field  := extract_pmpcfg_in_field (pmpcfg_in, i );
      match_type := get_match_type(pmpcfg_in_field );



      if match_type = TOR then
          if i = 0 then
            addr_start := (others => '0'); 
          else
            addr_start := unsigned(pmpaddr_in(i-1)) sll 2; 
          end if;
         addr_end := unsigned(pmpaddr_in(i)) sll 2; 






      elsif match_type = NAPOT then
        -- Per NAPOT, l'indirizzo pmpaddr_in è centrato sulla regione
        napot_mask := ((pmpaddr_in(i)) xor std_logic_vector(unsigned(pmpaddr_in(i)) + 1)); ------- con questa parte "prendiamo" tutti i bit finali messi a 1
        diff_napot_mask := std_logic_vector((unsigned(napot_mask) +1)sll 2); ------- con questo calcoliamo l'intervallo e con otto aggiungiamo gli 2^3 che richieno ( segna la differenza giusta) 
        nand_result := unsigned(std_logic_vector(unsigned(pmpaddr_in(i)) and unsigned(napot_mask)));
        addr_start := unsigned(pmpaddr_in(i) xor std_logic_vector(nand_result)) sll 2;
        addr_end := addr_start + unsigned(diff_napot_mask);






      elsif match_type = NA4 then
        addr_start := unsigned(pmpaddr_in(i)) sll 2 ;
        addr_end := addr_start + 4;
      end if;



----instr_addr_o
    if instr_addr_o >= std_logic_vector(addr_start) then
       if instr_addr_o <= std_logic_vector(addr_end) then
         access_valid_found_instr:= '1'; -- Accesso valido trovato
          if check_permissions(pmpcfg_in_field , "10") = '0' then
             exception_pmp<= '1';
          end if;
          exit;
       end if;   
    end if;
end loop;





   if access_valid_found = '0' then
      load_exception_pmp <= '1';
      store_exception_pmp <= '1';
   end if;


   if access_valid_found_instr = '0' then
      exception_pmp<= '1';
   end if;





end process;


end RTL;