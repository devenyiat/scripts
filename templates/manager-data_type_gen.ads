-- *******************************************************************************************************************************
-- * HEADER
-- * @File    : Manager.Data_Type_Gen.ads
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
-- * @txt Contains the basic operations for software datatypes.
-- *
-- *******************************************************************************************************************************

with Types;
with Manager.Interfaces;

with TYPE_PREFIX;
with USE

--generic
--   type g_Value_Type is private;
--   g_Default_Value   : in g_Value_Type;
--   g_Unit_Of_Measure : in Types.T_Unit_Of_Measure := Types.None;
--   g_Precision       : in Types.T_Precision_Accuracy := 1;

package Manager.INSTANCE_NAME is

--   type T_Data_Info is new T_Abstract_Data with private;
   subtype G_Value_Type is G_VALUE_TYPE_PARAMATER;
   G_Default_Value   : G_Value_Type := G_DEFAULT_VALUE_PARAMATER;
   G_Unit_Of_Measure : Types.T_Unit_Of_Measure := G_UNIT_OF_MEASURE_PARAMETER;
   G_Precision       : Types.T_Precision_Accuracy := G_PRECISION_PARAMETER;

-- *******************************************************************************************************************************
-- * OPERATION
-- * @op Get_Value
-- *
-- * DESCRIPTION
-- * @descr Return the value associated to a data.
-- *
-- *******************************************************************************************************************************
   procedure Get_Value (Variable : in T_Data_R_Access;
                        Value    : out g_Value_Type);

-- *******************************************************************************************************************************
-- * OPERATION
-- * @op Set_Value
-- *
-- * DESCRIPTION
-- * @descr
-- *
-- *******************************************************************************************************************************
   procedure Set_Value (Variable : in T_Data_Access;
                        Value    : in g_Value_Type);

-- *******************************************************************************************************************************
-- * OPERATION
-- * @op Observe_Value
-- *
-- * DESCRIPTION
-- * @descr
-- *
-- *******************************************************************************************************************************
   procedure Observe_Value
     (Variable : in T_Data_R_Access;
      Value    : out g_Value_Type);

-- *******************************************************************************************************************************
-- * OPERATION
-- * @op Read
-- *
-- * DESCRIPTION
-- * @descr
-- *
-- *******************************************************************************************************************************
   procedure Read (Component : in T_Component;
                   Port      : in T_Internal_Port;
                   Node      : in T_Node := c_First_Node;
                   Value     : out g_Value_Type);

-- *******************************************************************************************************************************
-- * OPERATION
-- * @op Write
-- *
-- * DESCRIPTION
-- * @descr
-- *
-- *******************************************************************************************************************************
   procedure Write (Component : in T_Component;
                    Port      : in T_Internal_Port;
                    Node      : in T_Node := c_First_Node;
                    Value     : in g_Value_Type);

-- *******************************************************************************************************************************
-- * OPERATION
-- * @op Define_Internal_Port
-- *
-- * DESCRIPTION
-- * @descr
-- *
-- *******************************************************************************************************************************
   procedure Define_Internal_Port
     (PD_reference       : out T_Internal_Port;
      CTD_reference      : in  T_Component_Type;
      Name               : in  T_Name_R_Access;
      Identifier         : in T_Identifier_R_Access := null);

-- *******************************************************************************************************************************
-- * OPERATION
-- * @op Define_Port_Type_Couple
-- *
-- * DESCRIPTION
-- * @descr
-- *
-- *******************************************************************************************************************************
   procedure Define_Port_Type_Couple
     (PTCD_Reference     : out T_Port_Type_Couple;
      Name               : in T_Name_R_Access;
      Identifier         : in T_Identifier_R_Access);

-- *******************************************************************************************************************************
-- * OPERATION
-- * @op Create_Interface
-- *
-- * DESCRIPTION
-- * @descr Create an interface for the datatype.
-- * @descr An interface allows Component to send/receive messages to/from disant equipements.
-- * @descr It publish the encoding/decoding/description methods for an interface.
-- *
-- *******************************************************************************************************************************
   procedure Create_Interface
     (Interface_Type  : in Interfaces.T_Interface_Type;
      Value_Type_Size : in II_Types.T_Bit_Count            := g_Value_Type'Size;
      Serialize_Acc   : in Interfaces.T_Serialize_Access   := null;
      Deserialize_Acc : in Interfaces.T_Deserialize_Access := null;
      Describe_Acc    : in Interfaces.T_Describe_Access    := null);

-- *******************************************************************************************************************************
-- * OPERATION
-- * @op Create_Display
-- *
-- * DESCRIPTION
-- * @descr Create a display for the datatype.
-- * @descr A display allows Datatype to register an operation that return a string for a given value
-- *
-- *******************************************************************************************************************************
   procedure Create_Display
     (Display_Acc     : in Interfaces.T_Display_Access);

-- *******************************************************************************************************************************
-- * OPERATION
-- * @func Get_Attribute
-- *
-- *******************************************************************************************************************************
   function Get_Attribute return T_Attribute;

-- *******************************************************************************************************************************
-- * OPERATION
-- * @proc Set_Attribute
-- *
-- *******************************************************************************************************************************
   procedure Set_Attribute (Attr : in T_Attribute);

--private

   type T_Data_Info is new T_Abstract_Data with
      record
         Value           : g_Value_Type;
         Unit_Of_Measure : Types.T_Unit_Of_Measure    := g_Unit_Of_Measure;
         Precision       : Types.T_Precision_Accuracy := g_Precision;
      end record;

   function Create_Data return T_Data_Access;
   c_Create_Data_Access : constant T_Create_Data_Access := Create_Data'Access;

end Manager.INSTANCE_NAME;
