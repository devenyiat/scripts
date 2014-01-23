use Cwd;
use Class::Struct;
use File::Copy;
use File::Path;
use Understand;

my @CC_list = ();

my %filehash;
my %packages;
my $workdir = cwd();

my $mode = 0;

if ($ARGV[0] eq "-auto") {
	$mode = 0;
} 
if ($ARGV[0] eq "-stub") {
	$mode = 3;
} 
if ($ARGV[0] eq "-nostub") {
	$mode = 1;
} 
if ($ARGV[0] eq "-manual") {
	$mode = 2;
}

print $mode . "\n";


# --------------
# globals for reading files
@g_lines = ();
@g_error = ();

# globals for storing file lists
@g_temp = ();
@packagesList = ();
@g_additional_sources = ();
@g_original_sources = ();
@g_all_sources = ();
@g_exceptions = ();
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

sub copyFile {

	$type = getTypeFromRegistryValue($_[0]);
	$absolutePath = getAbsolutePathFromRegistryValue($_[0]);
	$fileName = getFileNameFromRegistryValue($_[0]);
	$from = $absolutePath . $fileName;

	if ($_[2] == 0) {
		$to = $_[1] . getRelativePathFromRegistryValue($_[0]) . getFileNameFromPackageName(getPackageNameFromRegistryValue($_[0]), $type);
		mkpath($_[1] . getRelativePathFromRegistryValue($_[0]));
	}
	else {
		$to = $_[1] . getFileNameFromPackageName(getPackageNameFromRegistryValue($_[0]), $type);
	}

	copy($from, $to) or die "died at copying $from (original input: $_[0])";
	chmod 0777, $to;
}

sub copydir {
	scan($_[0]);
	foreach $file (@g_temp) {
		if ($_[2] eq "all" or $file =~ m/\.$_[2]$/) {
			copyFile($file, $_[1], $_[3]);
		}
	}
}

sub copyAdsFiles {
	copydir("t:/Source/", "t:/Stubs/", "ads", 1);
	copydir("t:/Additional_Files/", "t:/Stubs/", "ads", 1);
	@stubs = scan("t:/Stubs/");
}

sub readfile {
	@g_lines = ();
	open FH, "<$_[0]" or die "error reading $_[0]";
	@g_lines = <FH>;
	close FH;
}

sub readerror {
	@g_error = ();
	open FH, "<$workdir/error";
	@g_error = <FH>;
	close FH;
}

sub printerror {
	readerror();
	foreach $e (@g_error) {
		print $e;
	}
}

sub hasDiscriminant {

	# checkPoint($_[0]);

	@p = $db->lookup($_[0], "Ada Type");
	if (@p != ()) {
		@d = $p[0]->ents("Ada Declare", "Ada Discriminant Component");
		if ($d[0] != "") {
			return 1;
		}
	}
	return 0;
}

sub isArray {

	# checkPoint($_[0]);

	@p = $db->lookup($_[0], "Ada Type");
	if (@p != ()) {
		if ($p[0]->kindname() eq "Type Array" and $p[0]->type !~ m/\((.*)\d(.*)\)/) {
			return 1;
		}
	}
	return 0;
}

# parameters: packageName, where to put the stub

sub createBodyForPackage
{
	
	# checkPoint("called createBodyForPackage with $_[0]");

	$specfile = getAbsolutePathFromRegistryValue(getRegistryValueFromPackageName($_[0], "spec")) . getFileNameFromPackageName($_[0], "spec");

	_generateBody($specfile, $_[1]);

	$bodyfile = "$_[1]" . getFileNameFromPackageName($_[0], "body");

	if (-e $bodyfile) {
		_updateBody($bodyfile);
		addFileToList($_[1], $_[0], "body");
		# TODO copy stub to t:/Stubs/
		# copyFile()
	}
	else {
		# checkPoint("$bodyfile is not created");
		if ($g_error[0] !~ m/does not require a body/ and $g_error[0] !~ m/cannot have a body/) {
			print "Cannot continue due to the following error(s):\n";
			printerror();
			print "\nType \"command\" to execute a command, press ENTER anyway: ";
			$in = <STDIN>;
			if ($in eq "command\n") {
				$in = <STDIN>;
				open STDERR, ">$workdir/error";
				system("$in");
				close STDERR;
				printerror();
				<STDIN>;
			}
		}
	}
}

sub _generateBody
{
	open STDERR, ">$workdir/error";
	print "gnatstub -f -t -It:/Stubs/ $_[0] $_[1]\n";
	system("gnatstub -f -t -It:/Stubs/ $_[0] $_[1]");
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
			# print $return_type . "\n";
			if (hasDiscriminant($return_type) or hasDiscriminant("?*" . $return_type)) {
				$return_type = $return_type . "(1)";
			}
			# if (isArray($return_type) or isArray("?*" . $return_type)) {
			# 	$return_type = $return_type . "(1..1)";
			# }
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

sub compile_routine {

	my $file;
	my $status = 0;
	my $exit = 0;

	# @g_additional_sources = scan("t:/Additional_Files/");
	# @g_all_sources = (@g_additional_sources, @g_original_sources);

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
			# if ($e =~ m/file "(.*)" not found/) {
			# 	$file = $1;
			# 	list_matches(hyphentodot($file));
			# 	$status = 1;
			# }
			if ($e =~ m/cannot generate code for file (.*)\.ads/ or $e =~ m/but file \"(.*)\.adb\" was not found/) {
				$file = lc $1 . ".adb";
				$p = getPackageNameFromFileName($file);
				addBodyFile($p);
				$status = 1;
			}
			if ($e =~ m/(.*?):(.*)body of generic unit \"(.*)\" not found/) {

				$absolutePath = getAbsolutePathFromRegistryValue(getRegistryValueFromPackageName(getPackageNameFromFileName($1), "spec"));
				$fileName = getFileNameFromPackageName(getPackageNameFromFileName($1), "spec");
				$file = $absolutePath . $fileName;
				$generic_unit = $3;
				
				readfile($file);
				$idx = 0;
				while ($g_lines[$idx] !~ m/with\s*(.*)$generic_unit;/ and $idx <= $#g_lines) {
					$idx++;
				}
				$g_lines[$idx] =~ m/with\s*(.*)$generic_unit;/; # print $1; <STDIN>;
				$packageToAdd = lc $1 . $generic_unit;

				addBodyFile($packageToAdd);
				$status = 1;

			}

			if ($e =~ m/(.*)\.adb:(.*):(.*): unconstrained subtype not allowed \(need initialization\)/) {
				$file = getAbsolutePathFromRegistryValue(getRegistryValueFromPackageName($1, "body")) . $1 . ".adb";

				open FH, "<$file";
				my @lines = ();
				@lines = <FH>;
				close FH;

				open FH, ">$file";
				$lineNumber = $2-1;
				$lines[$lineNumber] =~ s/Result : (.*);/Result : $1\(1..1\);/;
				foreach (@lines) {
					print FH $_;
				}
				close FH;
				$status = 1;

				# checkPoint($file);

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
		copyAdsFiles;
	}

	if ($status != 2) {
		compile_routine($_[0]);
	}
}

sub checkPoint {
	print "checkPoint: ";
	print $_[0] . "\n";
	print "press ENTER to continue";
	<STDIN>;
}

sub listFiles {

	# checkPoint("called listFiles with $_[0].$_[1]");

	my @matches = ();
	my $counter = 0;
	my $result;
	my $package = $_[0];

	if ($_[1] eq "spec") {
		@matches = (grep(/#file: $package.1.ada/i, @CC_list), grep(/#file: $package.ads/i, @CC_list));
	}
	else {
		@matches = (grep(/#file: $package.2.ada/i, @CC_list), grep(/#file: $package.adb/i, @CC_list));
	}

	$counter = $#matches + 1;

	# print "Please choose the most appropriate one to continue:\n\n";
	# foreach $element (@CC_list) {
	# 	if ($_[1] eq "spec") {
	# 		if ($element =~ m/#file: $package.1.ada/i or $element =~ m/#file: $package.ads/i) {
	# 			push(@matches, $element);
	# 			print $counter . " - $element \n\n";
	# 			$counter = $counter + 1;
	# 		}
	# 	}
	# 	else {
	# 		if ($element =~ m/#file: $package.2.ada/i or $element =~ m/#file: $package.adb/i) {
	# 			push(@matches, $element);
	# 			print $counter . " - $element \n\n";
	# 			$counter = $counter + 1;
	# 		}
	# 	}
	# }
	# print "-----------------------\n";

	$num = 0;

	if ($counter > 0) {
		if ($counter == 1) {
			print "\nautomatically selected..\n\n";
			$result = $matches[0];
		}
		else {
			print "Please choose the most appropriate one to continue:\n\n";
			foreach $match (@matches) {
				print $num++ . " - $match \n\n";
			}
			print "-----------------------\n";
			print "\nfile to copy: ";
			my $in = <STDIN>;
			$result = $matches[$in];
			print "\n\n";
		}
	}
	else {
		print "no file found\n";
		$result = "nullPointerException";
	}

	return $result;
}

sub getImports {

	# checkPoint("called getImports with $_[0].$_[1]\n");

	my @imports = ();
	$file = getAbsolutePathFromRegistryValue(getRegistryValueFromPackageName($_[0], $_[1])) . getFileNameFromPackageName($_[0], $_[1]);

	open FH, "<$file";
	my @lines = ();
	@lines = <FH>;
	close FH;

	my $idx = 0;

	while ($lines[$idx] !~ m/^package/i and $idx<=$#lines) {
		if ($lines[$idx] =~ m/^with\s*(.*?)\s*;/) {
			# print $1;
			if (not lc "$1.spec" ~~ @packagesList) {
				# print " is new\n";
				push(@imports, lc $1);
			}
			else {
				# print " is not new\n";
			}
		}
		$idx++;
	}

	return @imports;
}

sub gatherSpecFiles {

	# checkPoint("called gatherSpecFiles with $_[0].$_[1]\n");

	my $package = $_[0];
	my @listToGather = ();

	if ($package =~ m/\./) {
		$package =~ m/(.*)\.(.*)/;
		$parent_package = $1;
		if (not "$parent_package.spec" ~~ @packagesList) {
			push(@listToGather, $parent_package);
		}
	}

	@listToGather = (@listToGather, getImports($package, $_[1]));

	foreach $packageToAdd (@listToGather) {
		# print "$packageToAdd.spec shall be added\n";
		if (not "$packageToAdd.spec" ~~ @packagesList) {
			addSpecFile($packageToAdd);
		}
	}
}

sub addFileToList {
	$registry = "#dir: $_[0]/ #file: " . getFileNameFromPackageName($_[1], $_[2]);
	push(@g_all_sources, $registry);
}

sub addFile {
	$fileToCopy = listFiles($_[0], $_[1]);
	if ($fileToCopy ne "nullPointerException") {
		copyFile($fileToCopy, "t:/Additional_Files/", 1);
		copyFile($fileToCopy, "t:/Stubs/", 1);
		addFileToList("t:/Additional_Files/", $_[0], $_[1]);
		return "file added";
	}
	else {
		return "file not added";
	}
}

sub addSpecFile {
	if (addFile($_[0], "spec") eq "file added") {
		push(@packagesList, "$_[0].spec");
		gatherSpecFiles($_[0], "spec");
	}
}

sub addBodyFile {

	# checkPoint("called addBodyFile with $_[0]\n");

	my $toStub = 0;
	# if selected mode is auto
	if (($mode == 0 and not $_[0] ~~ @g_exceptions) or $mode == 3) {
		$toStub = 1;
	}
	if ($mode == 2) {
		print "Would you like to stub the package $_[0]? (Y/N) ";
		$in = <STDIN>;
		if ($in eq "Y\n") {
			$toStub = 1;
		}
	}

	if ($toStub == 1) {
		createBodyForPackage($_[0], "t:/Additional_Files/");
	}
	else {
		if (addFile($_[0], "body") eq "file added") {
			gatherSpecFiles($_[0], "body");
			updateDatabase();
			openDatabase();
			checkPoint($_[0]);
		}
	}
}

sub emc_modifier {
	my @ads_files = ();
	my @adb_files = ();
	$modded = 0;

	foreach $line (@g_original_sources){

		my $new_file = getAbsolutePathFromRegistryValue($line) . getFileNameFromRegistryValue($line);
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

		if ($file =~ m/vital\-/) {
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

		$file = getAbsolutePathFromRegistryValue($stub) . getFileNameFromRegistryValue($stub);

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

			$file =~ m/t:\/Stubs\/(.*?)\.ads/;
			$original_package_name = $1;

			while ($content =~ m/\n( *)package (.*) is new Data_Type( *)(\n?)( *)\((.*)(\n.*)(\n.*)?;/g) {
				# get package name
				$package_name = $2;

				# creating new files
				$new_package_name = $original_package_name . "_" . $package_name;
				print $new_package_name;
				my $new_file = lc "Manager" . $dr . $new_package_name;
				mkdir "Data_Type_Instances";
				copy("Manager.Data_Type_Gen.ads", "t:/Stubs/" . $new_file . ".ads") or die "Copy failed: $!";

				addFileToList("t:/Stubs/", "manager$dr$new_package_name", "spec");

				# copy("Vital.EMC_Manager.Data_Type.adb","Data_Type_Instances/" . $new_file . ".adb") or die "Copy failed: $!";
				push(@new_files, $new_file . ".ads");
				push(@new_files, $new_file . ".adb");

				# get g_value_type and g_default_value lines
				$g_value_type = $6;
				$g_default_value = $7;
				$g_unit_of_measure = $8;

				# get g_value_type
				$g_value_type =~ /G_Value_Type( *)=> (.*),/i;
				$value_type = $2;
				
				# get type_prefix (what we should include)
				$value_type =~ /(.*)\./;
				$type_prefix = $1;
				# $type_prefix = $value_type;

				# get g_dafault_value
				$g_default_value =~ /G_Default_Value( *)=> (.*)(\)|,)/i;
				$default_value = $2;

				# get g_unit_of_measure if exists
				if ($g_unit_of_measure =~ /( *)G_Unit_Of_Measure( *)=> (.*)\)/i) {
					$unit_of_measure = $3;
				}

				# editing the new ada spec file
				open(DT, "<t:/Stubs/$new_file.ads") or die "error opening $workdir/Data_Type_Instances/$new_file.ads";
				@g_lines = <DT>;
				close DT;
				open (DT, ">t:/Stubs/$new_file.ads");
				for (@g_lines){
					s/Manager.Data_Type_Gen.ads/$new_file.ads/;
					if ($type_prefix =~ /(\w+)/) {
						s/with Types;/with Types;\nwith $type_prefix;/;
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
				open(DT, "<$file") or die "error opening $file";
				@g_lines = <DT>;
				close DT;
				open (DT, ">$file");
				foreach (@g_lines) {
					s/^([^-])*pragma Elaborate_All\s*\(Data_Type\)/$1--pragma Elaborate_All(Data_Type)/;
					s/^( *)package $package_name is new Data_Type(.*)/--HOST_TEST_BEGIN\npackage $package_name renames Manager.$new_package_name;\n--package $package_name is new Data_Type$2/;
					s/^( *)\((.*),/--\($2,/;
					s/ G_Default_Value( *)=> (.*),/--G_Default_Value$1=> $2,/i;
					s/ G_Default_Value( *)=> (.*)\);/--G_Default_Value$1=> $2\);\n--HOST_TEST_END/i;
					s/ G_Unit_Of_Measure( *)=> (.*)\);/--G_Unit_Of_Measure$1=> $2\);\n--HOST_TEST_END/i;
					print DT;
				}
				# close DT;

				close DT;

				push(@withs, $new_package_name);
			}

			open(DT, "<$file") or die "error opening $file";
			@g_lines = <DT>;
			close DT;
			open (DT, ">$file");
			foreach (@g_lines) {
				foreach $with (@withs) {
					s/with (.*);/with $1;\nwith Manager.$with;/;
				}
				s/with Data_Type;/--with Data_Type;/;
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
				if ($Type_line =~ /g_Data_Package => DT\)/i){
					push(@wrong_files, $file);
				}
				else {
					$Type_line =~ /g_Data_Package => (.*?)( ?)\)/i;
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

					$content =~ m/package (.*) is/;
					$package_name = $1;

					$new_package_name = $package_name . "_PT";

					# if (!($new_file ~~ @new_files)){

						# creating new files

						my $new_file = lc "Manager" . $dr . $new_package_name;
						mkdir "Port_Type_Instances";
						copy("Manager.Port_Type_Gen.ads","t:/Stubs/" . $new_file . ".ads") or die "Copy failed: $!";

						addFileToList("t:/Stubs/", "manager$dr$new_package_name", "spec");

						# copy("Vital.EMC_Manager.Port_Type.adb","Port_Type_Instances/" . $new_file . ".adb") or die "Copy failed: $!";
						push(@new_files, $new_file . ".ads");
						push(@new_files, $new_file . ".adb");

						# editing the new ada spec file

						open(DT, "<t:/Stubs/$new_file.ads") or die "error opening $workdir/Port_Type_Instances/$new_file.ads";
						@g_lines = <DT>;
						close DT;
						open (DT, ">t:/Stubs/$new_file.ads");
						foreach (@g_lines) {
							s/Manager.Port_Type_Gen.ads/$new_file.ads/;
							s/INSTANCE_NAME/$new_package_name/;

							s/with DATA_TYPE_INSTANCE;/with Manager.$type_prefix\_$dt_package_name;\nwith Types;/;
							# s/with DATA_TYPE_INSTANCE;/with $Type;\nwith Types;/;

							s/renames DATA_TYPE_INSTANCE/renames Manager.$type_prefix\_$dt_package_name/;
							# s/renames DATA_TYPE_INSTANCE/renames $Type/;

							s/G_NAME_PARAMETERS/new Types.T_PTC_Name'\("$PTC"\)/;
							s/G_IDENTIFIER_PARAMETERS/new Types.T_Identifier'\("$Ident"\)/;
							print DT;
						}
						close DT;
					# }
				# }

				# editing the original file
				open(DT, "<$file") or die "error opening $file";
				@g_lines = <DT>;
				close DT;
				open (DT, ">$file");
				foreach (@g_lines) {
					s/^([^-])*pragma Elaborate_All\s*\(Port_Type\)/$1--pragma Elaborate_All(Port_Type)/;
					s/^( *)package (.*) is new Port_Type(.*),/--HOST_TEST_BEGIN\npackage $2 renames Manager.$new_package_name;\n--package $2 is new Port_Type$3,/;
					s/ g_Identifier/--g_Identifier/;
					s/ g_Data_Package => (.*)\);/--g_Data_Package => $1\);\n--HOST_TEST_END/;
					print DT;
				}

				close DT;

				push(@withs, $new_package_name);
			}
			open(DT, "<$file") or die "error opening $file";
			@g_lines = <DT>;
			close DT;
			open (DT, ">$file");
			foreach (@g_lines) {
				foreach $with (@withs) {
					s/with (.*);/with $1;\nwith Manager.$with;/;
				}
				s/with Port_Type;/--with Port_Type;/;
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

				open(DT, "<t:/Stubs/$new_file.ads") or die "error opening $new_file in stubs";
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
				open(DT, "<$file") or die "error opening $file";
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

			open(DT, "<$file") or die "error opening $file";
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

sub readExceptions {
	open FH, "<t:/exceptions.txt";
	@exs = <FH>;
	close FH;

	foreach $ex (@exs) {
		$ex =~ m/(.*)\n/;
		push(@g_exceptions, lc $1);
	}
}

sub openDatabase {
	($db, $status) = Understand::open("t:/U500.udb") or die "failed to open database";
}

sub updateDatabase {
	if ($db != ()) {
		$db->close();
	}
	open STDERR, ">$workdir/error";
	system("und -db t:/U500.udb analyze -rescan");
	system("und -db t:/U500.udb analyze -changed");
	close STDERR;
	# ($db, $status) = Understand::open("t:/U500.udb") or die "failed to open database";
}

sub getTypeFromRegistryValue {
	my $result;
	$_[0] =~ m/#dir: (.*)\/\/(.*) #file: (.*?)\.(\d\.)?ad(.)/;
	if ($4 eq "1." or $5 eq "s") {
		$result = "spec";
	}
	else {
		$result = "body";
	}
	return $result;
}

sub getAbsolutePathFromRegistryValue {
	$_[0] =~ m/#dir: (.*)\/\/(.*) #file: (.*?)\.(\d\.)?ad(.)/;
	return $1 . "/" . $2;
}

sub getRelativePathFromRegistryValue {
	$_[0] =~ m/#dir: (.*)\/\/(.*) #file: (.*?)\.(\d\.)?ad(.)/;
	return $2;
}

sub getPackageNameFromRegistryValue {
	$_[0] =~ m/#dir: (.*)\/\/(.*) #file: (.*?)\.(\d\.)?ad(.)/;
	my $result = $3;
	$result =~ tr/-/./;
	$result = lc $result;
	return $result;
}

sub getFileNameFromRegistryValue {
	$_[0] =~ m/#dir: (.*)\/\/(.*) #file: (.*?)\.(\d\.)?ad(.)/;
	$result = $3 . "." . $4 . "ad" . $5;
	return $result;
}

sub getFileNameFromPackageName {
	$result = lc $_[0];
	$result =~ tr/./-/;
	$result = $result . ".ad" . substr($_[1], 0, 1);
	return $result;
}

sub getRegistryValueFromPackageName {
	my $ext;
	if ($_[1] eq "spec") {
		$ext = "s";
	}
	else {
		$ext = "b";
	}
	@result = grep {/#file: $_[0].ad$ext/} @g_all_sources;
	if (@result == ()) {
		return "nullPointerException";
	}
	else {
		return $result[0];
	}
}

sub getPackageNameFromFileName {
	$_[0] =~ m/(.*)\.ad./;
	$result = $1;
	$result =~ tr/-/./;
	return $result;
}

# **
# create a list of all the files on CC
# TODO
# **

@stubs = ();

sub main {
	print "Reading q:\n";
	if ($ARGV[1] ne "") {
		@CC_list = (scan("q:/"), scan($ARGV[1]));
	}
	else {
		@CC_list = scan("q:/");
	}
	readExceptions();

	print "Copying sources\n";
	copydir("t:/temp/", "t:/Source/", "all", 0);

	@g_original_sources = scan("t:/Source/");
	@g_additional_sources = scan("t:/Additional_Files/");
	@g_all_sources = (@g_additional_sources, @g_original_sources);

	foreach $source (@g_all_sources) {
		$packageName = getPackageNameFromRegistryValue($source);
		$type = getTypeFromRegistryValue($source);
		if (not "$packageName.$type" ~~ @packagesList){
			push(@packagesList, "$packageName.$type");
		}
	}

	print "Modifying EMCs\n";
	emc_modifier();

	print "Gathering spec files\n";
	foreach $source (@g_all_sources) {
		gatherSpecFiles(getPackageNameFromRegistryValue($source), getTypeFromRegistryValue($source));
	}

	copydir("t:/Source/", "t:/Stubs/", "ads", 1);
	copydir("t:/Additional_Files/", "t:/Stubs/", "ads", 1);
	@stubs = scan("t:/Stubs/");

	print "Updating database\n";
	updateDatabase();
	openDatabase();

	print "Starting compile routine for sources\n";

	compile_routine("t:/GNAT/U500.gpr");

	print "Generating instances\n";

	instance_maker();

	print "Starting compile routine for stubs\n";

	# $mode = 0;
	# compile_routine("t:/GNAT/U500Stub.gpr");
}

main();

# # copydir("t:/known_errors/", "t:/Stubs/", "all", 1);
# @stubs = scan("t:/Stubs/");

# print "instances were successfully created\n";

openDatabase();

@stubs = scan("t:/Stubs/");
# @g_all_sources = scan("t:/Stubs/");

# open STDERR, ">$workdir/error";

while (@stubs != ()) {
	my @newstubs = ();
	foreach $stub (@stubs) {

		$body = "t:/Stubs/" . getFileNameFromPackageName(getPackageNameFromRegistryValue($stub) , "body");
		$spec = "t:/Stubs/" . getFileNameFromRegistryValue($stub);

		# checkPoint($body);
		# checkPoint($spec);

		# if (getPackageNameFromRegistryValue($stub) ~~ @g_exceptions) {
		# 	$package = getPackageNameFromRegistryValue($stub);			
		# 	$registry = getRegistryValueFromPackageName($package, "body");
		# 	copyFile($registry, "t:/Stubs/", 1);
		# }
		if (!(-e $body)) {
			createBodyForPackage(getPackageNameFromRegistryValue($stub), "t:/Stubs/");
		}
		if (!(-e $body)) {
			readerror();
			if ($g_error[0] !~ m/does not require a body/ and $g_error[0] !~ m/cannot have a body/) {
				# print $g_error[0] . "\n";
				push(@newstubs, $stub);
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

# close STDERR;