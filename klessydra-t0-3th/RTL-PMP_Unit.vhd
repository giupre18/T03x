
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
    data_we_pmp              :out std_logic;
    data_we_o               : in std_logic;

    data_addr_pmp        :out std_logic_vector(31 downto 0);
    data_addr_o             : in std_logic_vector(31 downto 0);

    data_gnt_pmp             :out std_logic;
    data_gnt_effettivo       : in std_logic;

  -- program memory interface
    instr_addr_o	       : in std_logic_vector(31 downto 0);
    instr_addr_pmp       : out std_logic_vector(31 downto 0);

    instr_pmpvalid_o	       : out  std_logic;


    instr_gnt_pmp             :out std_logic;
    instr_gnt_effettivo       : in std_logic;
    



    ie_except_data            : in std_logic_vector(31 downto 0);
    IE_except_condition       : in std_logic;
    ie_taken_branch           : in std_logic; 

    ie_except_data_pmp           : out std_logic_vector(31 downto 0);
    IE_except_condition_pmp       : out std_logic;
    ie_taken_branch_pmp           : out std_logic; 

    set_except_condition          : in std_logic;
    taken_branch                  : in std_logic;

    set_except_condition_pmp          : out std_logic;
    taken_branch_pmp                  : out std_logic;

  -- segnali di debug
    addr_start_debug: out std_logic_vector(31 downto 0);
    addr_end_debug: out std_logic_vector(31 downto 0);

    --PMP Registers Inputs
    pmpcfg_in       : in  pmpcfg_array;
    pmpaddr_in      : in  pmpaddr_array;
    clk_i                      : in  std_logic;
    rst_ni                     : in  std_logic

  );
end PMP_Unit;


architecture RTL of PMP_Unit is
  -- Definizione dei tipi di indirizzamento
  type pmp_match_type is (OFF,TOR, NA4, NAPOT);

  -- Funzione per determinare il tipo di matching
function get_match_type(pmpcfg_in_field  : std_logic_vector(7 downto 0)) return pmp_match_type is
  begin
    if pmpcfg_in_field (4) = '1' and pmpcfg_in_field (3) = '1' then
      return NAPOT;
    elsif pmpcfg_in_field (4) = '1' and pmpcfg_in_field (3) = '0' then
      return NA4;
    elsif pmpcfg_in_field (4) = '0' and pmpcfg_in_field (3) = '1' then
      return TOR;
     else 
     --pmpcfg_in_field (4) = '0' and pmpcfg_in_field (3) = '0' then
      return OFF;
    end if;
  end function;


function extract_pmpcfg_in_field(
        pmpcfg_in : pmpcfg_array; 
        segment_index : integer
    ) return std_logic_vector is
        variable reg_index   : integer;  -- Indice del registro
        variable field_index : integer;  -- Indice del campo all'interno del registro
        variable pmpcfg_in_reg  : std_logic_vector(31 downto 0); -- Registro corrente
        variable extracted_field : std_logic_vector(7 downto 0); -- Campo estratto
    begin
        -- Calcola quale registro contiene il segmento richiesto
        reg_index := segment_index / 4;
        -- Calcola quale segmento del registro Ã¨ richiesto
        field_index := segment_index mod 4;

        -- Estrai il registro corrispondente
        pmpcfg_in_reg := pmpcfg_in(reg_index);

        -- Estrai il campo specifico (8 bit) dal registro
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
    -- Estrarre i bit di permesso
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


--signal access_type_datamem : std_logic_vector(1 downto 0); 
--signal data_we_pmp_int :std_logic;

begin

process (pmpcfg_in, pmpaddr_in, data_addr_o, data_we_o, instr_addr_o,data_gnt_effettivo,instr_gnt_effettivo,ie_except_data,IE_except_condition,ie_taken_branch,set_except_condition,taken_branch)
    variable pmpcfg_in_field : std_logic_vector(7 downto 0) ;
    variable match_type : pmp_match_type ; 
    variable addr_start :  unsigned(31 downto 0);
    variable addr_end   : unsigned(31 downto 0);
    variable diff_napot_mask : std_logic_vector(31 downto 0);
    variable napot_mask : std_logic_vector(31 downto 0);
    variable nand_result : unsigned(31 downto 0);
    variable access_valid_found, access_valid_found_instr :  std_logic  := '0';
   

begin
      set_except_condition_pmp <= set_except_condition;
      taken_branch_pmp <= taken_branch;



    ie_except_data_pmp <= ie_except_data;
    IE_except_condition_pmp <= IE_except_condition;
    ie_taken_branch_pmp <= ie_taken_branch;

    instr_addr_pmp <= instr_addr_o;
    ---instr_rvalid_effettivo <= '0';
    access_valid_found := '0';
    access_valid_found_instr := '0';
    data_gnt_pmp <= data_gnt_effettivo;
    data_we_pmp <= data_we_o;
    data_addr_pmp <= data_addr_o;

   instr_gnt_pmp<=instr_gnt_effettivo;

for i in 0 to PMP_REGIONS-1 loop

    -- Loop attraverso le regioni PMP
      -- Estrai il registro pmpcfg_in corrente (32 bit) e il segmento pmpcfg_in_field  (8 bit)
      pmpcfg_in_field  := extract_pmpcfg_in_field (pmpcfg_in, i );

      -- Determina il tipo di matching
      match_type := get_match_type(pmpcfg_in_field );



      if match_type = TOR then
        if i = 0 then
          addr_start := (others => '0'); -- Inizio memoria
        else
          addr_start := unsigned(pmpaddr_in(i-1)) sll 2; -- Moltiplica per granularità
        end if;
        addr_end := unsigned(pmpaddr_in(i)) sll 2; -- Fine regione






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


      -- Verifica se l'indirizzo di accesso rientra nella regione
      if data_addr_o >= std_logic_vector(addr_start) then
       	if data_addr_o <= std_logic_vector(addr_end) then
           access_valid_found := '1'; -- Accesso valido trovato
    	    if check_permissions(pmpcfg_in_field , "01") = '0' or check_permissions(pmpcfg_in_field , "00") = '0' then
                  data_gnt_pmp<='0';
                  data_we_pmp <= '0';
                  data_addr_pmp<=(others => '0');
          end if;
        exit;
        end if;  
      end if;
end loop;

   addr_start_debug<= std_logic_vector(addr_start);
   addr_end_debug <= std_logic_vector(addr_end);

for i in 0 to PMP_REGIONS-1 loop

  
      -- Estrai il registro pmpcfg_in corrente (32 bit) e il segmento pmpcfg_in_field  (8 bit)
      pmpcfg_in_field  := extract_pmpcfg_in_field (pmpcfg_in, i );

      -- Determina il tipo di matching
      match_type := get_match_type(pmpcfg_in_field );



      if match_type = TOR then
        if i = 0 then
          addr_start := (others => '0'); -- Inizio memoria
        else
          addr_start := unsigned(pmpaddr_in(i-1)) sll 2; -- Moltiplica per granularità
        end if;
        addr_end := unsigned(pmpaddr_in(i)) sll 2; -- Fine regione






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
                  instr_gnt_pmp<='0';
                  ie_taken_branch_pmp <= '1';
                  IE_except_condition_pmp <= '1';
                   set_except_condition_pmp <= '1';
                   taken_branch_pmp <= '1';
                  ie_except_data_pmp <= ILLEGAL_INSN_EXCEPT_CODE;
                  --instr_addr_pmp<= x"00000013";
          end if;
          exit;
       end if;   
    end if;
end loop;





   if access_valid_found = '0' then
      data_gnt_pmp<='0';
   end if;


   --if access_valid_found_instr = '0' then
    --   instr_rvalid_effettivo <= '0';
   --end if;



--end if;



  end process;



end RTL;