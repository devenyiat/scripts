use Cwd;
use File::Copy;
use File::Path;
use Understand;

my @CC_list = ();

my %filehash;
my $workdir = cwd();


# --------------
# globals for reading files
@g_lines = ();
@g_error = ();

# globals for storing file lists
@g_temp = ();
@g_additional_sources = ();
@g_original_sources = ();
@g_all_sources = ();
%g_exceptions = ();
# --------------

sub scan {
	@g_temp = ();
	scandirs($_[0]);
	chdir($workdir);
	return @g_temp;
}

sub scandirs {
	my $dir;
	if ($_[1] =~ /(\w+)/){
		$dir = $_[0] . "/" . $_[1];
	}
	else {
		$dir = $_[0];
	}
	chdir($dir);
	local @files = <*>;
	foreach $file (@files) {
		chdir($dir);
		if (-f $file) {
			if (($file =~ /\.ads$/) or ($file =~ /\.adb$/) or ($file =~ /\.ada$/)) {	
				$number_of_files = $number_of_files + 1;
				my $string = "#dir: " . $dir . "/ #file: " . $file;
				push(@g_temp, $string);
			}
		}
		if (-d $file) {
			scandirs($dir, $file);
		}
	}
}

sub extract {
	$_[0] =~ m/#dir: (.*)\/\/(.*) #file: (.*)\.(\d\.)?ad(.)/;
	$filehash{"apath"} = $1 . "/";
	$filehash{"rpath"} = $2;
	$filehash{"fname"} = $3;
	$filehash{"fext"} = "." . $4 . "ad" . $5;
}

# MEMO - 0 - copy full path; 1 - copy only the file

sub copyfile {
	extract($_[0]);

	$apath = $filehash{"apath"};
	$rpath = $filehash{"rpath"};
	$fname = $filehash{"fname"};
	$fext = $filehash{"fext"};

	$from = $apath . $rpath . $fname . $fext;

	$fext =~ m/\.(\d\.)?ad(.)/;
	$e = $2;
	if ($1 eq "1.") {
		$e = "s";
	}
	if ($1 eq "2.") {
		$e = "b";
	}

	if ($_[2] == 0) {
		$to = $_[1] . $rpath . dottohyphen($fname) . ".ad" . $e;
		mkpath($_[1] . $rpath);
	}
	else {
		$to = $_[1] . dottohyphen($fname) . ".ad" . $e;
	}

	copy($from, $to) or die "died at copying $from";
	chmod 0777, $to;
}

sub copydir {
	scan($_[0]);
	foreach $file (@g_temp) {
		if ($_[2] eq "all" or $file =~ m/\.$_[2]$/) {
			copyfile($file, $_[1], $_[3]);
		}
	}
}

sub readfile {
	@g_lines = ();
	open FH, "<$_[0]";
	@g_lines = <FH>;
	close FH;
}

sub readerror {
	@g_error = ();
	open FH, "<$workdir/error";
	@g_error = <FH>;
	close FH;
}

sub discriminant {

	@p = $db->lookup($_[0], "Ada Type");
	if (@p != ()) {
		@d = $p[0]->ents("Ada Declare", "Ada Discriminant Component");
		if ($d[0] != "") {
			return 1;
		}
	}
	return 0;
}

sub array {
	# if ($_[0] =~ /Executor_List_T/){
	# 	<STDIN>;
	# }
	@p = $db->lookup($_[0], "Ada Type");
	# print @p;
	# <STDIN>;
	if (@p != ()) {
		if ($p[0]->kindname() eq "Type Array" and $p[0]->type !~ m/\((.*)\d(.*)\)/) {
			return 1;
		}
	}
	return 0;
}

sub createBodyFromSpecFile
{
	# $param = $_[0];
	# $param =~ m/(.*)\/(.*)/;
	# $file = $2;
	# $dir = $1 . "/";

	# $param =~ s/ads/adb/;

	if (!(-e spec_to_body($_[0]))) {
		# $param =~ s/adb/ads/;
		_generateBody($_[0], $_[1]);
		# $param =~ s/ads/adb/;

		if (-e spec_to_body($_[0])) {
			_updateBody(spec_to_body($_[0]));
		}
	}
}

sub _generateBody
{
	open STDERR, ">$workdir/error";
	print "gnatstub -f -It:/Additional_Files/ -It:/Source/ $_[0] $_[1]\n";
	system("gnatstub -f -It:/Additional_Files/ -It:/Source/ $_[0] $_[1]");
	close STDERR;
}

sub _updateBody
{
	$filename = shift;

	readfile($filename);

	$string = "";
	$package;
	$return_type;
	$infunc = 0;

	open FH, ">$filename";

	foreach (@g_lines) {

		if (m/(\s+)end (\S*);$/) {
			# $temp = $1;
			$string =~ m/(.*)\.(.*)/;
			$string = $1;
		}

		if (m/body (\S*)/ or m/procedure (\S*)/ or m/function (\S*)/ or m/entry (\S*)/) {
			if ($string ne "") {
				$sp = $1;
				$string = $string . "." . $1;
			}
			else {
				$string = $1;
				$package = $1;
			}
		}

		if (m/return (\S*)( is)?\n/ and $1 !~ m/;/) {
			$return_type = $1;
			print $return_type . "\n";
			if (discriminant($return_type) or discriminant("?*" . $return_type)) {
				$return_type = $return_type . "(1)";
			}
			if (array($return_type) or array("?*" . $return_type)) {
				$return_type = $return_type . "(1..1)";
			}
		}

		if ($return_type ne "") {
			if (s/(\s*)?(.*)?(\s+)is/$1$2$3is\n$1  Result : $return_type;/) {
				$return_type = "";
			}
		}

		$newstring = $string;
		$newstring =~ tr/\"/'/;
		s/(\s*)pragma Compile_Time_Warning \(Standard.True,(.*)/$1Ada.Text_IO.Put_Line \(\"$newstring is called\"\);/;

		s/package body $package is/with Ada.Text_IO;\npackage body $package is/;

		s/end $package;/begin\n\tAda.Text_IO.Put_Line \(\"$package is elaborated\"\);\nend $package;/;

		s/\s*raise Program_Error;\n//;

		s/return (.*);/return Result;/;

		print FH;
	}	

	close FH;
}

sub list_matches {
	print "\n-----------------------\n\n$_[0] file is missing\nPlease choose the most appropriate one to continue:\n\n";
	@matches = ();
	$_[0] =~ m/(.*)\.ad(.)/;
	my $package = $1;
	my $ext = $2;
	my $counter = 0;
	foreach $element (@CC_list) {
		if ($ext eq "s") {
			if ($element =~ m/#file: $package.1.ada/i or $element =~ m/#file: $package.ads/i) {
				push(@matches, $element);
				print $counter . " - $element \n\n";
				$counter = $counter + 1;
			}
		}
		else {
			if ($g_exceptions{dottohyphen($package)} and ($element =~ m/#file: $package.2.ada/i or $element =~ m/#file: $package.adb/i)) {
				push(@matches, $element);
				print $counter . " - $element \n\n";
				$counter = $counter + 1;
			}
		}
	}
	print "-----------------------";
	if ($counter == 0 and $ext eq "b") {
		$registry = isavailable($package . ".ads");
		extract($registry);
		$file = $filehash{"apath"} . $filehash{"rpath"} . dottohyphen($package) . ".ads";
		createBodyFromSpecFile($file, "t:/Additional_Files/");
	}
	if ($counter > 0) {
		if ($counter == 1) {
			print "\nautomatically selected..\n\n";
			copyfile($matches[0], "t:/Additional_Files/", 1);
		}
		else {
			print "\nfile to copy: ";
			my $in = <STDIN>;
			copyfile($matches[$in], "t:/Additional_Files/", 1);
			print "\n\n";
		}
	}
	if ($counter == 0 and $ext eq "s") {
		print "no spec file found";
		<STDIN>;
	}
}

sub spec_to_body {
	$result = $_[0];
	$result =~ s/\.ads$/\.adb/;
	return $result;
}

sub body_to_spec {
	$result = $_[0];
	$result =~ s/\.adb$/\.ads/;
	return $result;
}

sub dottohyphen {
	my $result = $_[0];
	$result =~ tr/./-/;
	$result = lc $result;
	return $result;
}

sub hyphentodot {
	my $result = $_[0];
	$result =~ tr/-/./;
	$result = lc $result;
	return $result;
}

sub isavailable {
	print "looking for $_[0]\n\n";
	foreach $source (@g_all_sources) {
		if ($source =~ m/$_[0]/) {
			return $source;
		}
	}
	return "not found";
}

sub compile_routine {

	my $file;
	my $status = 0;
	my $exit = 0;

	@g_additional_sources = scan("t:/Additional_Files/");
	@g_all_sources = (@g_additional_sources, @g_original_sources);

	open STDERR, ">$workdir/error";
	system("gprbuild -ws -d $_[0]");
	close STDERR;

	readerror();

	if ($g_error[$#error] !~ m/failed/) {
		$status = 2;
		print "\n------------------------------";
		print "\n| source compilation is done |";
		print "\n------------------------------\n";
	}

	if ($status == 0) {
		foreach $e (@g_error) {
			if ($e =~ m/file "(.*)" not found/) {
				$file = $1;
				list_matches(hyphentodot($file));
				$status = 1;
			}
			if ($e =~ m/cannot generate code for file (.*)\.ads/ or $e =~ m/but file \"(.*)\.adb\" was not found/) {
				$file = lc $1 . ".adb";
				# print "calling list_matches with $file";
				list_matches(hyphentodot($file));
				$status = 1;
			}
			if ($e =~ m/(.*?):(.*)body of generic unit \"(.*)\" not found/) {
				$file = $1;
				$generic_unit = $3;
				
				$registry = isavailable($file);
				print "REG: " . $registry;
				if ($registry ne "not found") {
					extract ($registry);
					readfile($filehash{"apath"} . $filehash{"rpath"} . $filehash{"fname"} . $filehash{"fext"});
					$idx = 0;
					while ($g_lines[$idx] !~ m/with (.*)$generic_unit;/ and $idx <= $#g_lines) {
						$idx++;
					}
					$g_lines[$idx] =~ m/with (.*)$generic_unit;/; # print $1; <STDIN>;
					$file = lc $1 . $generic_unit . ".adb";
					list_matches($file);
					$status = 1;
				}
				else {
					print $e;
					<STDIN>;
				}
			}
		}
	}

	if ($status == 0) {
		print "\n-----------------------\n\nerror occurred during compilation:\n\n";
		foreach $e (@g_error) {
			print $e;
		}
		print "\n-----------------------\n\n";
		print "\nwaiting for user interaction...\nType OK when error is eliminated...";
		do {
			$in = <STDIN>;
		} while ($in eq "OK");
	}

	if ($status != 2) {
		compile_routine($_[0]);
	}
}

sub emc_modifier {
	my @ads_files = ();
	my @adb_files = ();
	$modded = 0;

	foreach $line (@g_original_sources){
		extract($line);

		$apath = $filehash{"apath"};
		$rpath = $filehash{"rpath"};
		$fname = $filehash{"fname"};
		$fext = $filehash{"fext"};

		my $new_file = $apath . $rpath . $fname . $fext;
		if ($new_file =~ /.ads/){
			push(@ads_files, $new_file);
		}
		if ($new_file =~ /.adb/){
			push(@adb_files, $new_file);
		}
	}

	# foreach $file (@ads_files) {

	# 	open(DT, "<$file");
	# 	@g_lines = <DT>;
	# 	close DT;
	# 	open (DT, ">$file");

	# 	foreach (@g_lines) {
	# 		if (s/private package (\S*) is/--HOST_TEST_BEGIN\n--private package $1 is\npackage $1 is\n--HOST_TEST_END/){
	# 			$modded = 1;
	# 		}
	# 		print DT or die;
	# 	}

	# 	close DT;
	# }

	foreach $file (@adb_files) {

		$modded = 0;

		if ($file =~ m/Vital\./) {
			open(DT, "<$file");
			@g_lines = <DT>;
			close DT;
			open (DT, ">$file");

			foreach (@g_lines) {
				if (s/^begin/--HOST_TEST_BEGIN\nprocedure Elab is\n--HOST_TEST_END\nbegin/){
					$modded = 1;
				}
				if ($modded == 1) {
					s/end Vital/--HOST_TEST_BEGIN\nend Elab;\n--HOST_TEST_END\nend Vital/;
				}
				print DT;
			}

			close DT;

		}
	}
}

sub instance_maker {

	my $dr = '-';

	open STDERR, ">$workdir/error";

	foreach $stub (@stubs) {

		extract($stub);

		$apath = $filehash{"apath"};
		$rpath = $filehash{"rpath"};
		$fname = $filehash{"fname"};
		$fext = $filehash{"fext"};

		$file = $apath . $rpath . $fname . $fext;

		open my $fh, '<', $file or die "error opening $filename: $!";
		my $content = do { local $/; <$fh> };

		my $g_value_type;
		my $package_name;
		my $dt_package_name;
		my $original_package_name;
		my $new_package_name;
		my $value_type;
		my $default_value;
		my $unit_of_measure;
		my $type_prefix;
		my @withs = ();

		my $modded = 0;

		# DATA_TYPE BEGIN

		# if file contains Data_Type instantiation
		if ($content =~ m/\n( *)package (.*) is new Data_Type( *)/){

			$file =~ m/(.*)-(.*)\.ads/;
			$original_package_name = $2;

			while ($content =~ m/\n( *)package (.*) is new Data_Type( *)(\n?)( *)\((.*)(\n.*)(\n.*)?;/g) {
				# get package name
				$package_name = $2;

				# creating new files
				$new_package_name = "Inst_" . $original_package_name . "_" . $package_name;
				my $new_file = lc "Vital" . $dr . "EMC_Manager" . $dr . $new_package_name;
				mkdir "Data_Type_Instances";
				copy("Vital.EMC_Manager.Data_Type.ads","t:/Stubs/" . $new_file . ".ads") or die "Copy failed: $!";
				# copy("Vital.EMC_Manager.Data_Type.adb","Data_Type_Instances/" . $new_file . ".adb") or die "Copy failed: $!";
				push(@new_files, $new_file . ".ads");
				push(@new_files, $new_file . ".adb");

				# get g_value_type and g_default_value lines
				$g_value_type = $6;
				$g_default_value = $7;
				$g_unit_of_measure = $8;

				# get g_value_type
				$g_value_type =~ /G_Value_Type( *)=> (.*),/;
				$value_type = $2;
				
				# get type_prefix (what we should include)
				$value_type =~ /(.*)\./;
				$type_prefix = $1;

				# get g_dafault_value
				$g_default_value =~ /G_Default_Value( *)=> (.*)(\)|,)/;
				$default_value = $2;

				# get g_unit_of_measure if exists
				if ($g_unit_of_measure =~ /( *)G_Unit_Of_Measure( *)=> (.*)\)/) {
					$unit_of_measure = $3;
				}

				# editing the new ada spec file
				open(DT, "<t:/Stubs/$new_file.ads") or die "error opening $workdir/Data_Type_Instances/$new_file.ads";
				@g_lines = <DT>;
				close DT;
				open (DT, ">t:/Stubs/$new_file.ads");
				for (@g_lines){
					s/Vital.EMC_Manager.Data_Type.ads/$new_file.ads/;
					if ($type_prefix =~ /(\w+)/) {
						s/with Vital.Types;/with Vital.Types;\nwith $type_prefix;/;
					}
					s/INSTANCE_NAME/$new_package_name/;
					s/G_VALUE_TYPE_PARAMATER/$value_type/;
					s/G_DEFAULT_VALUE_PARAMATER/$default_value/;
					if ($unit_of_measure =~ /(\w+)/){
						s/G_UNIT_OF_MEASURE_PARAMETER/$unit_of_measure/;
					}
					else {
						s/G_UNIT_OF_MEASURE_PARAMETER/Types.None/;
					}
					s/G_PRECISION_PARAMETER/1/;
					print DT;
				}
				close DT;

				# editing the original file
				open(DT, "<$file");
				@g_lines = <DT>;
				close DT;
				open (DT, ">$file");
				foreach (@g_lines) {
					s/^([^-])*pragma Elaborate_All\s*\(Vital\.Data_Type\)/$1--pragma Elaborate_All(Vital.Data_Type)/;
					s/^( *)package $package_name is new Data_Type(.*)/--HOST_TEST_BEGIN\npackage $package_name renames Vital.EMC_Manager.$new_package_name;\n--package $package_name is new Data_Type$2/;
					s/^( *)\((.*),/--\($2,/;
					s/ G_Default_Value( *)=> (.*),/--G_Default_Value$1=> $2,/;
					s/ G_Default_Value( *)=> (.*)\);/--G_Default_Value$1=> $2\);\n--HOST_TEST_END/;
					s/ G_Unit_Of_Measure( *)=> (.*)\);/--G_Unit_Of_Measure$1=> $2\);\n--HOST_TEST_END/;
					print DT;
				}
				# close DT;

				close DT;

				push(@withs, $new_package_name);
			}

			open(DT, "<$file");
			@g_lines = <DT>;
			close DT;
			open (DT, ">$file");
			foreach (@g_lines) {
				foreach $with (@withs) {
					s/with Vital.Data_Type;/with Vital.Data_Type;\nwith Vital.EMC_Manager.$with;/;
				}
				s/with Vital.Data_Type;/--with Vital.Data_Type;/;
				print DT;
			}
			close DT;
			@withs = ();

			$modded = 1;

		}

		close $fh;

		# DATA_TYPE END

		# PORT_TYPE BEGIN

		if ($content =~ m/\n( *)package PT is new Port_Type \((.*)\n(.*)\n(.*);/) {		

			# while ($content =~ m/\n( *)package PT is new Port_Type \((.*)\n(.*)\n(.*);/g) {
				my $PTC_line = $2;
				my $Ident_line = $3;
				my $Type_line = $4;

				$PTC_line =~ /T_PTC_Name\'\(\"(.*?)\"/;
				my $PTC = $1;

				$Ident_line =~ /T_Identifier\'\(\"(.*?)\"/;
				my $Ident = $1;

				my $Type;
				if ($Type_line =~ /g_Data_Package => DT\)/){
					push(@wrong_files, $file);
				}
				else {
					$Type_line =~ /g_Data_Package => (.*?)( ?)\)/;
					$Type = $1;
					if ($Type =~ /(.*)\.(.*)\.(.*)/) {
						$dt_package_name = $3;
						$type_prefix = $2;
					}
					else {
						$Type =~ /(.*)\.(.*)/;
						$dt_package_name = $2;
						$type_prefix = $1;
					}

					$content =~ m/package Vital.(.*) is/;
					$package_name = $1;

					$new_package_name = "Inst_" . $package_name . "_PT";

					# if (!($new_file ~~ @new_files)){

						# creating new files

						my $new_file = lc "Vital" . $dr . "EMC_Manager" . $dr . $new_package_name;
						mkdir "Port_Type_Instances";
						copy("Vital.EMC_Manager.Port_Type.ads","t:/Stubs/" . $new_file . ".ads") or die "Copy failed: $!";
						# copy("Vital.EMC_Manager.Port_Type.adb","Port_Type_Instances/" . $new_file . ".adb") or die "Copy failed: $!";
						push(@new_files, $new_file . ".ads");
						push(@new_files, $new_file . ".adb");

						# editing the new ada spec file

						open(DT, "<t:/Stubs/$new_file.ads") or die "error opening $workdir/Port_Type_Instances/$new_file.ads";
						@g_lines = <DT>;
						close DT;
						open (DT, ">t:/Stubs/$new_file.ads");
						foreach (@g_lines) {
							s/Vital.EMC_Manager.Port_Type.ads/$new_file.ads/;
							s/INSTANCE_NAME/$new_package_name/;
							s/with DATA_TYPE_INSTANCE;/with Vital.EMC_Manager.Inst_$type_prefix\_$dt_package_name;\nwith Vital.Types;/;
							s/renames DATA_TYPE_INSTANCE/renames Vital.EMC_Manager.Inst_$type_prefix\_$dt_package_name/;
							s/G_NAME_PARAMETERS/new Types.T_PTC_Name'\("$PTC"\)/;
							s/G_IDENTIFIER_PARAMETERS/new Types.T_Identifier'\("$Ident"\)/;
							print DT;
						}
						close DT;
					# }
				# }

				# editing the original file
				open(DT, "<$file");
				@g_lines = <DT>;
				close DT;
				open (DT, ">$file");
				foreach (@g_lines) {
					s/^([^-])*pragma Elaborate_All\s*\(Vital\.Port_Type\)/$1--pragma Elaborate_All(Vital.Port_Type)/;
					s/^( *)package (.*) is new Port_Type(.*),/--HOST_TEST_BEGIN\npackage $2 renames Vital.EMC_Manager.$new_package_name;\n--package $2 is new Port_Type$3,/;
					s/ g_Identifier/--g_Identifier/;
					s/ g_Data_Package => (.*)\);/--g_Data_Package => $1\);\n--HOST_TEST_END/;
					print DT;
				}

				close DT;

				push(@withs, $new_package_name);
			}
			open(DT, "<$file");
			@g_lines = <DT>;
			close DT;
			open (DT, ">$file");
			foreach (@g_lines) {
				foreach $with (@withs) {
					s/with Vital.Port_Type;/with Vital.Port_Type;\nwith Vital.EMC_Manager.$with;/;
				}
				s/with Vital.Port_Type;/--with Vital.Port_Type;/;
				print DT;
			}
			close DT;
			@withs = ();

			$modded = 1;
		}

		close $fh;

		# PORT_TYPE END

		# Generic_Operator BEGIN

		if ($content =~ m/is new (.*)\.Generic_Operator( *)\(/) {

			my $comp_ident;
			my $comp_name;
			my $OUtput_pt_ident;
			my $g_PT_Package;
			my $constant_value;

			while ($content =~ m/package Vital\.(.*) is new (.*)\.Generic_Operator( *)\(\n?(.*)\n(.*)\n(.*)\n(.*)\n(.*)\);/g){

				$package_name = $1;
				my $comp_ident_line = $4;
				my $comp_name_line = $5;
				my $OUtput_pt_ident_line = $6;
				my $g_PT_Package_line = $7;
				my $constant_value_line = $8;

				$comp_ident_line =~ /Component_Identifier( *)=> (.*),/;
				$comp_ident = $2;

				$comp_name_line =~ /Component_Name( *)=> (.*),/;
				$comp_name = $2;

				$OUtput_pt_ident_line =~ /Output_PT_Identifier( *)=> (.*),/;
				$OUtput_pt_ident = $2;

				$g_PT_Package_line =~ /g_PT_Package( *)=> (.*)\.PT,/;
				if ($2 =~ /Vital\.(.*)/) {
					$g_PT_Package = $1;
				}
				else {
					$g_PT_Package = $2;
				}

				$constant_value_line =~ /Constant_Value( *)=> (.*)/;
				$constant_value = $2;
				$constant_value =~ /(.*)\.(.*)/;
				$type_prefix = $1;

				$new_package_name = "Inst_" . $package_name;

				# creating the new files

				my $new_file = lc "Vital" . $dr . "EMC_Manager" . $dr . $new_package_name;
				mkdir "Generic_Operator_Instances";	
				copy("Vital.Generic_Operator.ads","t:/Stubs/" . $new_file . ".ads") or die "Copy failed: $!";
				# copy("Vital.Generic_Operator.adb","Generic_Operator_Instances/" . $new_file . ".adb") or die "Copy failed: $!";
				push(@new_files, $new_file . ".ads");
				push(@new_files, $new_file . ".adb");

				# editing the new ada spec file

				open(DT, "<t:/Stubs/$new_file.ads");
				@g_lines = <DT>;
				close DT;
				open (DT, ">t:/Stubs/$new_file.ads");
				foreach (@g_lines) {
					s/Vital.Generic_Operator.ads/Vital-EMC_Manager-$new_package_name\.ads/;
					s/INSTANCE_NAME/$new_package_name/;
					s/COMPONENT_IDENTIFIER_INSTANCE/$comp_ident/;
					s/COMPONENT_NAME_INSTANCE/$comp_name/;
					s/OUTPUT_PT_IDENTIFIER_INSTANCE/$OUtput_pt_ident/;
					s/g_PT_PACKAGE_INSTANCE/Vital.EMC_Manager.Inst\_$g_PT_Package\_PT/;
					s/CONSTANT_VALUE_INSTANCE/$constant_value/;
					if ($type_prefix =~ /(\w+)/) {
						s/with Vital.Types;/with Vital.Types;\nwith $type_prefix;/
					}
					print DT;
				}
				close DT;		

				# editing the original file
				open(DT, "<$file");
				@g_lines = <DT>;
				close DT;
				open (DT, ">$file");
				foreach (@g_lines) {
					s/^([^-])*pragma Elaborate_All\s*\(Vital\.Generic_Operator\)/$1--pragma Elaborate_All(Vital.Generic_Operator)/;
					s/package (.*) is new (.*)\.Generic_Operator(.*)/--HOST_TEST_BEGIN\npackage $1 renames Vital\.EMC_Manager\.$new_package_name;\n--package $1 is new $2\.Generic_Operator$3/;
					s/ Component_Identifier/--Component_Identifier/;
					s/ Component_Name/--Component_Name/;
					s/ Output_PT_Identifier/--Output_PT_Identifier/;
					s/ g_PT_Package/--g_PT_Package/;
					s/ Constant_Value(.*);/--Constant_Value$1;\n--HOST_TEST_END/;
					print DT;
				}
				# close DT;

				close DT;

				# push(@withs, $new_package_name);
			}

			open(DT, "<$file");
			@g_lines = <DT>;
			close DT;
			open (DT, ">$file");
			foreach (@g_lines) {
				s/with Vital.Generic_Operator;/--with Vital.Generic_Operator;\nwith Vital\.EMC_Manager\.$new_package_name;/;				
				print DT;
			}
			close DT;
			@withs = ();

			$modded = 1;
		}

		close $fh;

		# Generic_Operator END

		if ($modded == 1){
			push(@modded_files, $file)
		}
	}
}

sub readexceptions {
	open FH, "<t:/exceptions.txt";
	@exs = <FH>;
	close FH;

	foreach $ex (@exs) {
		$ex =~ m/(.*)\n/;
		$g_exceptions{dottohyphen($1)} = 1;
	}
}

# **
# create a list of all the files on CC
# TODO
# **

($db, $status) = Understand::open("t:/U500.udb") or die "failed to open database";

@CC_list = scan("q:/");
readexceptions();

copydir("t:/temp/", "t:/Source/", "all", 1);

@g_original_sources = scan("t:/Source/");
@g_additional_sources = scan("t:/Additional_Files/");
@g_all_sources = (@g_additional_sources, @g_original_sources);

emc_modifier();

compile_routine("t:/GNAT/U500.gpr");

@g_additional_sources = scan("t:/Additional_Files/");
@g_all_sources = (@g_additional_sources, @g_original_sources);

print "\nGenerating stubs\n";

copydir("t:/Source/", "t:/Stubs/", "ads", 1);
copydir("t:/Additional_Files/", "t:/Stubs/", "ads", 1);
@stubs = scan("t:/Stubs/");

instance_maker();
# copydir("t:/known_errors/", "t:/Stubs/", "all", 1);
@stubs = scan("t:/Stubs/");

print "instances were successfully created\n";

@stubs = scan("t:/Stubs/");

$db->close();
open STDERR, ">$workdir/error";
system("und -db t:/U500.udb analyze -rescan");
system("und -db t:/U500.udb analyze");
close STDERR;

($db, $status) = Understand::open("t:/U500.udb") or die "failed to open database";

while (@stubs != ()) {
	my @newstubs = ();
	foreach $stub (@stubs) {

		extract($stub);
		$apath = $filehash{"apath"};
		$rpath = $filehash{"rpath"};
		$fname = $filehash{"fname"};
		$fext = $filehash{"fext"};

		print $fname . "\n";

		if ($g_exceptions{$fname}) {
			$registry = isavailable("$fname.adb");
			copyfile($registry, "t:/Stubs/", 1);
		}
		if (!(-e "t:/Stubs/$fname.adb")) {
			createBodyFromSpecFile("t:/Stubs/$fname.ads", "t:/Stubs/");
		}
		$fullname = $apath . $rpath . $fname . ".adb";
		if (!(-e $fullname)) {
			readerror();
			if ($g_error[0] !~ m/does not require a body/ and $g_error[0] !~ m/cannot have a body/) {
				print $g_error[0] . "\n";
				push(@newstubs, $stub);
				<STDIN>;
			}
		}
	}
	@stubs = @newstubs;
	print "\n";
}

do {
	open STDERR, ">$workdir/error";
	system("gprbuild -ws -d t:/GNAT/U500Stub.gpr");
	close STDERR;

	readerror();
	if ($g_error[$#error] =~ m/failed/) {
		print $g_error[$#error-1];
		print "\nPress ENTER to continue"; <STDIN>;
	}
} while ($g_error[$#error] =~ m/failed/);

print "\n----------------------------";
print "\n| stub compilation is done |";
print "\n----------------------------\n";