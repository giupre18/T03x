
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
  type pmp_exceptions is record
    load_exception_pmp  : std_logic;
    store_exception_pmp : std_logic;
    exc_exception_pmp   : std_logic;
  end record;

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

function check_exception_pmp(
    pmpcfg_in       : pmpcfg_array;
    pmpaddr_in      : pmpaddr_array; -- sostituisci con il tuo tipo corretto
    instr_addr_o    : std_logic_vector(31 downto 0);
    data_addr_o     : std_logic_vector(31 downto 0);
    i               : integer
) return pmp_exceptions is
    variable pmpcfg_in_field           : std_logic_vector(7 downto 0);
    variable match_type                : pmp_match_type; -- tipo enum che definisce TOR, NAPOT, NA4
    variable addr_start :  unsigned(31 downto 0);
    variable addr_end   : unsigned(31 downto 0);
    variable diff_napot_mask : std_logic_vector(31 downto 0);
    variable napot_mask : std_logic_vector(31 downto 0);
    variable nand_result : unsigned(31 downto 0);
    variable exceptions                : pmp_exceptions := (load_exception_pmp => '0', store_exception_pmp => '0', exc_exception_pmp => '0');
begin
      pmpcfg_in_field  := extract_pmpcfg_in_field (pmpcfg_in, i );
      match_type := get_match_type(pmpcfg_in_field );


case match_type is 

      when TOR =>
          if i = 0 then
            addr_start := (others => '0'); 
          else
            addr_start := unsigned(pmpaddr_in(i-1)) sll 2; 
          end if;
         addr_end := unsigned(pmpaddr_in(i)) sll 2; 






     when NAPOT =>
        -- Per NAPOT, l'indirizzo pmpaddr_in è centrato sulla regione
        napot_mask := ((pmpaddr_in(i)) xor std_logic_vector(unsigned(pmpaddr_in(i)) + 1)); ------- con questa parte "prendiamo" tutti i bit finali messi a 1
        diff_napot_mask := std_logic_vector((unsigned(napot_mask) +1)sll 2); ------- con questo calcoliamo l'intervallo e con otto aggiungiamo gli 2^3 che richieno ( segna la differenza giusta) 
        nand_result := unsigned(std_logic_vector(unsigned(pmpaddr_in(i)) and unsigned(napot_mask)));
        addr_start := unsigned(pmpaddr_in(i) xor std_logic_vector(nand_result)) sll 2;
        addr_end := addr_start + unsigned(diff_napot_mask);






      when NA4 =>
        addr_start := unsigned(pmpaddr_in(i)) sll 2 ;
        addr_end := addr_start + 4;

      when others =>
      null;
      end case;

if data_addr_o >= std_logic_vector(addr_start) then
        if data_addr_o <= std_logic_vector(addr_end) then
           --access_valid_found := '1'; -- Accesso valido trovato
            if check_permissions(pmpcfg_in_field , "00") = '0' then
                  exceptions.load_exception_pmp := '1';
          end if;
          if check_permissions(pmpcfg_in_field , "01") = '0' then
                  exceptions.store_exception_pmp := '1';
          end if;
        end if;  
      end if;

----instr_addr_o
    if instr_addr_o >= std_logic_vector(addr_start) then
       if instr_addr_o <= std_logic_vector(addr_end) then
         --access_valid_found_instr:= '1'; -- Accesso valido trovato
          if check_permissions(pmpcfg_in_field , "10") = '0' then
             exceptions.exc_exception_pmp := '1';
          end if;
       end if;   
    end if;
    
    

    return exceptions;
end function;

  type exceptions_array is array (0 to 31) of pmp_exceptions;

begin

process (pmpcfg_in, pmpaddr_in, data_addr_o,instr_addr_o)
    --variable pmpcfg_in_field : std_logic_vector(7 downto 0) ;
    --variable match_type : pmp_match_type ; 
    --variable addr_start :  unsigned(31 downto 0);
    --variable addr_end   : unsigned(31 downto 0);
    --variable diff_napot_mask : std_logic_vector(31 downto 0);
    --variable napot_mask : std_logic_vector(31 downto 0);
    --variable nand_result : unsigned(31 downto 0);
    --variable access_valid_found, access_valid_found_instr :  std_logic  := '0';
variable error_inst, error_load, error_store   : unsigned (31 downto 0) := (others => '0');
variable exception_pmp_0  : pmp_exceptions;
variable exception_pmp_1  : pmp_exceptions;
variable exception_pmp_2  : pmp_exceptions;
variable exception_pmp_3  : pmp_exceptions;
variable exception_pmp_4  : pmp_exceptions;
variable exception_pmp_5  : pmp_exceptions;
variable exception_pmp_6  : pmp_exceptions;
variable exception_pmp_7  : pmp_exceptions;
variable exception_pmp_8  : pmp_exceptions;
variable exception_pmp_9  : pmp_exceptions;
variable exception_pmp_10 : pmp_exceptions;
variable exception_pmp_11 : pmp_exceptions;
variable exception_pmp_12 : pmp_exceptions;
variable exception_pmp_13 : pmp_exceptions;
variable exception_pmp_14 : pmp_exceptions;
variable exception_pmp_15 : pmp_exceptions;
variable exception_pmp_16 : pmp_exceptions;
variable exception_pmp_17 : pmp_exceptions;
variable exception_pmp_18 : pmp_exceptions;
variable exception_pmp_19 : pmp_exceptions;
variable exception_pmp_20 : pmp_exceptions;
variable exception_pmp_21 : pmp_exceptions;
variable exception_pmp_22 : pmp_exceptions;
variable exception_pmp_23 : pmp_exceptions;
variable exception_pmp_24 : pmp_exceptions;
variable exception_pmp_25 : pmp_exceptions;
variable exception_pmp_26 : pmp_exceptions;
variable exception_pmp_27 : pmp_exceptions;
variable exception_pmp_28 : pmp_exceptions;
variable exception_pmp_29 : pmp_exceptions;
variable exception_pmp_30 : pmp_exceptions;
variable exception_pmp_31 : pmp_exceptions;


begin
    store_exception_pmp <='0' ;
    load_exception_pmp <= '0';
    exception_pmp <= '0';
    --access_valid_found := '0';
    --access_valid_found_instr := '0';



--addr_start_debug <= std_logic_vector(addr_start);
--addr_end_debug <= std_logic_vector(addr_end);
--report "addr_start_debug = " & to_hstring(addr_start_debug);
--report "addr_end_debug = " & to_hstring(addr_end_debug);

exception_pmp_0  := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 0);
error_inst(0)    := exception_pmp_0.exc_exception_pmp;
error_load(0)    := exception_pmp_0.load_exception_pmp;
error_store(0)   := exception_pmp_0.store_exception_pmp;

exception_pmp_1  := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 1);
error_inst(1)    := exception_pmp_1.exc_exception_pmp or error_inst(0);
error_load(1)    := exception_pmp_1.load_exception_pmp or error_load(0);
error_store(1)   := exception_pmp_1.store_exception_pmp or error_store(0);

exception_pmp_2  := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 2);
error_inst(2)    := exception_pmp_2.exc_exception_pmp or error_inst(1);
error_load(2)    := exception_pmp_2.load_exception_pmp or error_load(1);
error_store(2)   := exception_pmp_2.store_exception_pmp or error_store(1);

exception_pmp_3  := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 3);
error_inst(3)    := exception_pmp_3.exc_exception_pmp or error_inst(2);
error_load(3)    := exception_pmp_3.load_exception_pmp or error_load(2);
error_store(3)   := exception_pmp_3.store_exception_pmp or error_store(2);

exception_pmp_4  := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 4);
error_inst(4)    := exception_pmp_4.exc_exception_pmp or error_inst(3);
error_load(4)    := exception_pmp_4.load_exception_pmp or error_load(3);
error_store(4)   := exception_pmp_4.store_exception_pmp or error_store(3);

exception_pmp_5  := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 5);
error_inst(5)    := exception_pmp_5.exc_exception_pmp or error_inst(4);
error_load(5)    := exception_pmp_5.load_exception_pmp or error_load(4);
error_store(5)   := exception_pmp_5.store_exception_pmp or error_store(4);

exception_pmp_6  := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 6);
error_inst(6)    := exception_pmp_6.exc_exception_pmp or error_inst(5);
error_load(6)    := exception_pmp_6.load_exception_pmp or error_load(5);
error_store(6)   := exception_pmp_6.store_exception_pmp or error_store(5);

exception_pmp_7  := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 7);
error_inst(7)    := exception_pmp_7.exc_exception_pmp or error_inst(6);
error_load(7)    := exception_pmp_7.load_exception_pmp or error_load(6);
error_store(7)   := exception_pmp_7.store_exception_pmp or error_store(6);

exception_pmp_8  := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 8);
error_inst(8)    := exception_pmp_8.exc_exception_pmp or error_inst(7);
error_load(8)    := exception_pmp_8.load_exception_pmp or error_load(7);
error_store(8)   := exception_pmp_8.store_exception_pmp or error_store(7);

exception_pmp_9  := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 9);
error_inst(9)    := exception_pmp_9.exc_exception_pmp or error_inst(8);
error_load(9)    := exception_pmp_9.load_exception_pmp or error_load(8);
error_store(9)   := exception_pmp_9.store_exception_pmp or error_store(8);

exception_pmp_10 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 10);
error_inst(10)   := exception_pmp_10.exc_exception_pmp or error_inst(9);
error_load(10)   := exception_pmp_10.load_exception_pmp or error_load(9);
error_store(10)  := exception_pmp_10.store_exception_pmp or error_store(9);

exception_pmp_11 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 11);
error_inst(11)   := exception_pmp_11.exc_exception_pmp or error_inst(10);
error_load(11)   := exception_pmp_11.load_exception_pmp or error_load(10);
error_store(11)  := exception_pmp_11.store_exception_pmp or error_store(10);

exception_pmp_12 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 12);
error_inst(12)   := exception_pmp_12.exc_exception_pmp or error_inst(11);
error_load(12)   := exception_pmp_12.load_exception_pmp or error_load(11);
error_store(12)  := exception_pmp_12.store_exception_pmp or error_store(11);

exception_pmp_13 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 13);
error_inst(13)   := exception_pmp_13.exc_exception_pmp or error_inst(12);
error_load(13)   := exception_pmp_13.load_exception_pmp or error_load(12);
error_store(13)  := exception_pmp_13.store_exception_pmp or error_store(12);

exception_pmp_14 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 14);
error_inst(14)   := exception_pmp_14.exc_exception_pmp or error_inst(13);
error_load(14)   := exception_pmp_14.load_exception_pmp or error_load(13);
error_store(14)  := exception_pmp_14.store_exception_pmp or error_store(13);

exception_pmp_15 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 15);
error_inst(15)   := exception_pmp_15.exc_exception_pmp or error_inst(14);
error_load(15)   := exception_pmp_15.load_exception_pmp or error_load(14);
error_store(15)  := exception_pmp_15.store_exception_pmp or error_store(14);

exception_pmp_16 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 16);
error_inst(16)   := exception_pmp_16.exc_exception_pmp or error_inst(15);
error_load(16)   := exception_pmp_16.load_exception_pmp or error_load(15);
error_store(16)  := exception_pmp_16.store_exception_pmp or error_store(15);

exception_pmp_17 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 17);
error_inst(17)   := exception_pmp_17.exc_exception_pmp or error_inst(16);
error_load(17)   := exception_pmp_17.load_exception_pmp or error_load(16);
error_store(17)  := exception_pmp_17.store_exception_pmp or error_store(16);

exception_pmp_18 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 18);
error_inst(18)   := exception_pmp_18.exc_exception_pmp or error_inst(17);
error_load(18)   := exception_pmp_18.load_exception_pmp or error_load(17);
error_store(18)  := exception_pmp_18.store_exception_pmp or error_store(17);

exception_pmp_19 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 19);
error_inst(19)   := exception_pmp_19.exc_exception_pmp or error_inst(18);
error_load(19)   := exception_pmp_19.load_exception_pmp or error_load(18);
error_store(19)  := exception_pmp_19.store_exception_pmp or error_store(18);

exception_pmp_20 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 20);
error_inst(20)   := exception_pmp_20.exc_exception_pmp or error_inst(19);
error_load(20)   := exception_pmp_20.load_exception_pmp or error_load(19);
error_store(20)  := exception_pmp_20.store_exception_pmp or error_store(19);

exception_pmp_21 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 21);
error_inst(21)   := exception_pmp_21.exc_exception_pmp or error_inst(20);
error_load(21)   := exception_pmp_21.load_exception_pmp or error_load(20);
error_store(21)  := exception_pmp_21.store_exception_pmp or error_store(20);

exception_pmp_22 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 22);
error_inst(22)   := exception_pmp_22.exc_exception_pmp or error_inst(21);
error_load(22)   := exception_pmp_22.load_exception_pmp or error_load(21);
error_store(22)  := exception_pmp_22.store_exception_pmp or error_store(21);

exception_pmp_23 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 23);
error_inst(23)   := exception_pmp_23.exc_exception_pmp or error_inst(22);
error_load(23)   := exception_pmp_23.load_exception_pmp or error_load(22);
error_store(23)  := exception_pmp_23.store_exception_pmp or error_store(22);

exception_pmp_24 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 24);
error_inst(24)   := exception_pmp_24.exc_exception_pmp or error_inst(23);
error_load(24)   := exception_pmp_24.load_exception_pmp or error_load(23);
error_store(24)  := exception_pmp_24.store_exception_pmp or error_store(23);

exception_pmp_25 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 25);
error_inst(25)   := exception_pmp_25.exc_exception_pmp or error_inst(24);
error_load(25)   := exception_pmp_25.load_exception_pmp or error_load(24);
error_store(25)  := exception_pmp_25.store_exception_pmp or error_store(24);

exception_pmp_26 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 26);
error_inst(26)   := exception_pmp_26.exc_exception_pmp or error_inst(25);
error_load(26)   := exception_pmp_26.load_exception_pmp or error_load(25);
error_store(26)  := exception_pmp_26.store_exception_pmp or error_store(25);

exception_pmp_27 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 27);
error_inst(27)   := exception_pmp_27.exc_exception_pmp or error_inst(26);
error_load(27)   := exception_pmp_27.load_exception_pmp or error_load(26);
error_store(27)  := exception_pmp_27.store_exception_pmp or error_store(26);

exception_pmp_28 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 28);
error_inst(28)   := exception_pmp_28.exc_exception_pmp or error_inst(27);
error_load(28)   := exception_pmp_28.load_exception_pmp or error_load(27);
error_store(28)  := exception_pmp_28.store_exception_pmp or error_store(27);

exception_pmp_29 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 29);
error_inst(29)   := exception_pmp_29.exc_exception_pmp or error_inst(28);
error_load(29)   := exception_pmp_29.load_exception_pmp or error_load(28);
error_store(29)  := exception_pmp_29.store_exception_pmp or error_store(28);

exception_pmp_30 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 30);
error_inst(30)   := exception_pmp_30.exc_exception_pmp or error_inst(29);
error_load(30)   := exception_pmp_30.load_exception_pmp or error_load(29);
error_store(30)  := exception_pmp_30.store_exception_pmp or error_store(29);

exception_pmp_31 := check_exception_pmp(pmpcfg_in, pmpaddr_in, instr_addr_o, data_addr_o, 31);
error_inst(31)   := exception_pmp_31.exc_exception_pmp or error_inst(30);
error_load(31)   := exception_pmp_31.load_exception_pmp or error_load(30);
error_store(31)  := exception_pmp_31.store_exception_pmp or error_store(30);





   --if access_valid_found = '0' then
   --   load_exception_pmp <= '1';
    --  store_exception_pmp <= '1';
  -- end if;


 --  if access_valid_found_instr = '0' then
 --     exception_pmp<= '1';
 --  end if;
exception_pmp <= error_inst(31);
                 
                 
load_exception_pmp <= error_load(31);
                      
                      
store_exception_pmp <= error_store(31);

   --if access_valid_found = '0' then
   --   load_exception_pmp <= '1';
    --  store_exception_pmp <= '1';
  -- end if;


 --  if access_valid_found_instr = '0' then
 --     exception_pmp<= '1';
 --  end if;





end process;


end RTL;