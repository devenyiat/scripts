-- **********************************************************************************************************************
-- * HEADER
-- * @File    : P2oo34U500.Peripheral.Teach.2.ada
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
-- * @txt Teach the multiplexed line data during education
-- *
-- **********************************************************************************************************************


separate (P2oo34U500.Peripheral)


-- /*?
-- **********************************************************************************************************************
-- * OPERATION
-- * @op Teach
-- *
-- * DESCRIPTION
-- * @descr Teach peripheral data
-- *
-- * SOURCE REQUIREMENT
-- * @source  [2oo34U500-A431846-SwMD-0126]
-- ?*********************************************************************************************************************/
   procedure Teach (This : in T_Peripheral_Ptr) is
      use type T_Peripheral_Ptr;
   begin
      if This /= null then
         Teach (This => This.all);
      end if;
   end Teach;
