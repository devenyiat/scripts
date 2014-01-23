-- *******************************************************************************************************************************
-- * HEADER
-- * @File    : Manager.Port_Type.ads
-- *
-- * COPYRIGHT
-- *  | All rights reserved (c) 2012
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
-- * @Package_Kind      : generic package specification
-- * @Classification    : SIL 4
-- * @Component         : Manager
-- *
-- * GENERAL COMMENTS
-- * @txt As long as Port_Type_Couples are shared between Component and Unsafe.Component,
-- * @txt package Types cannot be set as PRIVATE
-- *
-- * NOTES
-- * @note History from Previous Projects
-- *
-- *******************************************************************************************************************************

--with Manager.Data_Type_Gen;
with DATA_TYPE_INSTANCE;
with Manager.Operations;

--generic
--   with package g_Data_Package is new Data_Type_Gen (<>);
--
--   g_Name       : in T_Name_R_Access;
--   g_Identifier : in T_Identifier_R_Access;

package Manager.INSTANCE_NAME is

   package g_Data_Package renames DATA_TYPE_INSTANCE;

   g_Name       : T_Name_R_Access := G_NAME_PARAMETERS;
   g_Identifier : T_Identifier_R_Access := G_IDENTIFIER_PARAMETERS;

-------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------  Public types  ------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------

-- **********************************************************************************************************************
-- * OPERATION
-- * #proc Get
-- *
-- **********************************************************************************************************************
  procedure Get (Component : in T_Component;
                 Port      : in T_Port_In;
                 Node      : in T_Node := c_First_Node;
                 Value     : out g_Data_Package.g_Value_Type);

-- **********************************************************************************************************************
-- * OPERATION
-- * #proc Supply
-- *
-- **********************************************************************************************************************
   procedure Supply (Component  : in T_Component;
                     Port       : in T_Port_Out;
                     Node       : in T_Node := c_First_Node;
                     Value      : in g_Data_Package.g_Value_Type);

-- **********************************************************************************************************************
-- * OPERATION
-- * #proc Define_Input_Port
-- *
-- **********************************************************************************************************************
   procedure Define_Input_Port
     (PD_reference       : out T_Port_In;
      CTD_reference      : in  T_Component_Type;
      Name               : in  T_Name_R_Access;
      Identifier         : in  T_Identifier_R_Access;
      Lower_Bound        : in  T_Node;
      Upper_Bound        : in  T_Node := c_Max_Nodes;
      Static_Internal_Cardinality    : in  T_Static_Internal_Cardinality := True;
      Give_Internal_Cardinality_Acc  : in  T_Give_Internal_Cardinality_Access := null);

-- **********************************************************************************************************************
-- * OPERATION
-- * #proc Define_Output_Port
-- *
-- **********************************************************************************************************************
   procedure Define_Output_Port
     (PD_reference                  : out T_Port_Out;
      CTD_reference                 : in  T_Component_Type;
      Name                          : in  T_Name_R_Access;
      Identifier                    : in  T_Identifier_R_Access;
      Lower_Bound                   : in  T_Node;
      Upper_Bound                   : in  T_Node := c_Max_Nodes;
      Initialize_Acc                : in  T_Node_Initialize_Access := null;
      Update_Acc                    : in  T_Node_Update_Access := null;
      Circular_Check_Acc            : in  T_Node_Circular_Check_Access := Operations.Node_Circular_check'Access;
      Static_Internal_Cardinality   : in  T_Static_Internal_Cardinality := True;
      Give_Internal_Cardinality_Acc : in  T_Give_Internal_Cardinality_Access := null);

-- **********************************************************************************************************************
-- * OPERATION
-- * #proc Define_Internal_Port
-- *
-- **********************************************************************************************************************
   procedure Define_Internal_Port
     (PD_reference       : out T_Internal_Port;
      CTD_reference      : in  T_Component_Type;
      Name               : in  T_Name_R_Access;
      Identifier         : in  T_Identifier_R_Access := null)
     renames g_Data_Package.Define_Internal_Port;

-- **********************************************************************************************************************
-- * OPERATION
-- * #proc Read
-- *
-- **********************************************************************************************************************
   procedure Read
     (Component : in T_Component;
      Port      : in T_Internal_Port;
      Node      : in T_Node := c_First_Node;
      Value     : out g_Data_Package.g_Value_Type)
     renames g_Data_Package.Read;

-- **********************************************************************************************************************
-- * OPERATION
-- * #proc Write
-- *
-- **********************************************************************************************************************
   procedure Write
     (Component : in T_Component;
      Port      : in T_Internal_Port;
      Node      : in T_Node := c_First_Node;
      Value     : in g_Data_Package.g_Value_Type)
     renames g_Data_Package.Write;

end Manager.INSTANCE_NAME;
