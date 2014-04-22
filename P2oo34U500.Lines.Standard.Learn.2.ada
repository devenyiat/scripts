-- **********************************************************************************************************************
-- * HEADER
-- * @File    : P2oo34U500.Lines.Standard.Learn.2.ada
-- * @ModelVersion : 1
-- *
-- * COPYRIGHT
-- *  | All rights reserved (c) 2014
-- *  |
-- *  | ALSTOM (SAINT OUEN, FRANCE)
-- *  |
-- *  | This computer program may not be used, copied, distributed,
-- *  | corrected,  modified,  translated,  transmitted or assigned
-- *  | without ALSTOM's prior written authorization.
-- *
-- * IDENTIFICATION
-- * @Program           : U500
-- * @Program_Component : U500 Control Software
-- * @Package_Kind      : package specification
-- * @Classification    : SIL4
-- *
-- * @DesignPart         : Maintenance
-- *
-- * GENERAL COMMENTS
-- * @txt Learn the standard line data during education
-- *
-- **********************************************************************************************************************
with P2oo34U500.Lines.Educate;

-- * @source [2oo34U500-A431846-SwMD-DP-0556]

separate (P2oo34U500.Lines.Standard)

-- /*?
-- **********************************************************************************************************************
-- * OPERATION
-- * @op Learn
-- *
-- * DESCRIPTION
-- * @descr Learn the standard line during education
-- *
-- * SOURCE REQUIREMENT
-- * @source [2oo34U500-A431846-SwMD-0291]
-- ?*********************************************************************************************************************/
   procedure Learn (Line : in out T_Standard_Line) is
      use type T_Peripheral_Access;
   begin
      Lines.Educate.Learn (Line => T_Line (Line));
      if Line.Peripheral /= null then
         Learn (This => Line.Peripheral);
      end if;
   end Learn;
