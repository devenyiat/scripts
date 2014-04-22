package TestPackage is
	type PrivateType; -- is private;
	-- Variable : PrivateType;
	-- type PrivateTypeAccess is access all PrivateType;

	procedure TestProcedure ( param1 : in PrivateType );

private
	type PrivateType is new Integer range 0..1000;
	Variable : PrivateType;
end TestPackage;
