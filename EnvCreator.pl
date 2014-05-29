use Cwd;
use Class::Struct;
use File::Copy;
use File::Path;
use File::stat;
use Understand;
use threads;
use threads::shared;
use Thread::Semaphore;

my @CC_list = ();

my $workdir = cwd();

my @switches;

sub setMode {

	@sws = @ARGV;

	if (not("-a" ~~ @sws or "-s" ~~ @sws or "-ns" ~~ @sws or "-m" ~~ @sws)) {
		print "Missing switch for setting way of stubbing; type it now (-a, -s, -ns, -m): ";
		my $sw = <STDIN>;
		$sw =~ "(.*)\n";
		push(@sws, $sw);
	}
	if (not("-n" ~~ @sws or "-u" ~~ @sws)) {
		print "Missing switch for setting way of building environment; type it now (-n, -u): ";
		my $sw = <STDIN>;
		$sw =~ "(.*)\n";
		push(@sws, $sw);
	}

	if ("-a" ~~ @sws) {
		$switches[1] = 0;
	}
	if ("-s" ~~ @sws) {
		$switches[1] = 3;
	}
	if ("-ns" ~~ @sws) {
		$switches[1] = 1;
	} 
	if ("-m" ~~ @sws) {
		$switches[1] = 2;
	}

	if ("-u" ~~ @sws) {
		$switches[0] = 0;
	}
	if ("-n" ~~ @sws) {
		$switches[0] = 1;
	}
    
    if ("-c" ~~ @sws) {
        $switches[2] = 1;
    }
}


# --------------
# globals for reading files
@g_lines = ();

# globals for storing file lists
@g_temp = ();
@packagesList = ();
@g_additional_sources = ();
@g_original_sources = ();
@g_unmodified_sources = ();
@g_generated_sources = ();
@g_exceptions = ();

# number of instances
$dataTypeCount = 0;
$portTypeCount = 0;
$genericOperatorCount = 0;

$CC_Location = "";
# --------------

sub scan {
	my @files = ();
	scandirs($_[0], "root", \@files);
	chdir($workdir);
	return @files;
}

sub scandirs {
	my $dir;
	my $ref = $_[2];
	if ($_[1] ne "root"){
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
			if (($file =~ /(.*)\.ads$/) or ($file =~ /(.*)\.adb$/) or ($file =~ /(.*)\.ada$/)) {
				$number_of_files = $number_of_files + 1;
				my $string = "#dir: " . $dir . "/ #file: " . $file;
				push(@$ref, $string);
			}
		}
		if (-d $file) {
			scandirs($dir, $file, $ref);
		}
	}
}
# **
# @params
# 	$_[0] : Source file's registry
#	$_[1] : Destination directory
#	$_[2] : Keep directory structure (0 - yes, 1 - no)
# 
# **

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

	copy($from, $to) or die "died at copying from $from to $to";
	chmod 0777, $to;
}

# **
# @params
# 	$_[0] : Source directory
#	$_[1] : Destination directory
#	$_[2] : Type of files to be copied
#	$_[3] : Keep directory structure (0 - yes, 1 - no)
# 
# **

sub copydir {
	my @files = scan($_[0]);
	foreach $file (@files) {
		if ($_[2] eq "all" or getTypeFromRegistryValue($file) eq $_[2]) {
			copyFile($file, $_[1], $_[3]);
		}
	}
}

# **
# @params
# 	$_[0] : Source directory
#	$_[1] : Destination directory
#	$_[2] : Type of files to be copied
#	$_[3] : Keep directory structure (0 - yes, 1 - no)
# 
# **

sub copyDiff {
	my @files = scan($_[0]);
	foreach my $fileEnt (@files) {
		if ($_[2] eq "all" or getTypeFromRegistryValue($file) eq $_[2]) {
			my $newFilesHandler = getAbsolutePathFromRegistryValue($fileEnt) . getFileNameFromRegistryValue($fileEnt);
			my $existingFilesEnt = getRegistryValueFromPackageName(getPackageNameFromRegistryValue($fileEnt), getTypeFromRegistryValue($fileEnt), \@g_unmodified_sources);
			if ($existingFilesEnt eq "nullPointerException") {
				copyFile($fileEnt, $_[1], $_[3]);
			}
			else {
				my $existingFilesHandler = getAbsolutePathFromRegistryValue($existingFilesEnt) . getFileNameFromRegistryValue($existingFilesEnt);
				$stat1 = stat($newFilesHandler);
				$stat2 = stat($existingFilesHandler);
				if ($stat1->mtime > $stat2->mtime) {
					copyFile($fileEnt, $_[1], $_[3]);
				}
			}
		}
	}

	foreach my $fileEnt (@g_unmodified_sources) {
		my $package = getPackageNameFromRegistryValue($fileEnt);
		my @list = grep(/$package/i, @files);
		if ($#list + 1 == 0) {
			unlink(getAbsolutePathFromRegistryValue($fileEnt) . getFileNameFromRegistryValue($fileEnt));
		}
		if ($#list + 1 == 1 and getTypeFromRegistryValue($list[0]) ne getTypeFromRegistryValue($fileEnt)) {
			unlink(getAbsolutePathFromRegistryValue($fileEnt) . getFileNameFromRegistryValue($fileEnt));
		}
	}
}
sub copyAdsFiles {
	copydir("n:/Source/", "n:/Stubs/", "spec", 1);
	copydir("n:/Additional_Files/", "n:/Stubs/", "spec", 1);
	@stubs = scan("n:/Stubs/");
}

sub readfile {
	@g_lines = ();
	open FH, "<$_[0]" or die "error reading $_[0]";
	@g_lines = <FH>;
	close FH;
}

sub readFile {
	@result = ();
	open FH, "<$_[0]" or die "error reading $_[0]";
	@result = <FH>;
	close FH;
	return @result;
}

sub readWholeFile {
	$result = "";
	open FH, "<$_[0]" or die "error reading $_[0]";
	@lines = <FH>;
	close FH;
	foreach $line (@lines) {
		$result = $result . $line;
	}
	return $result;
}

sub readerror {
	$semaphore->down();
	@result = ();
	open FH, "<$workdir/error";
	@result = <FH>;
	close FH;
	$semaphore->up();
	return @result;
}

sub printerror {
	$state = $_[0];
	if ($state == 1) {
		$running = 0;
	}
	my @errors = readerror();
	print "\n-----------------------\n\nerror occurred during operation:\n\n";
	foreach $e (@errors) {
		print $e;
	}
	print "\n-----------------------\n\n";
	print "\nwaiting for user interaction...\nPress ENTER when error is eliminated..."; <STDIN>;
	$running = $state;
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

sub readProgress {

	@stat = readFile("$workdir/stat");
	
	if ($stat[$#stat-1] =~ m/\((.*)\%\)/) {
		if ($progress < $1) {
			$progress = $1;
			$changed = 1;
		}
	}
}

sub writeProgress {
	open STAT, ">$workdir/stat";
	print STAT "$_[0]\%";
	close STAT;
}

sub showProgress {
	print "thread has been created\n";
	while ($phase < 4) {
		$changed = 0;
		if ($running == 1) {
			if ($phase != 2) {
				readProgress();
			}
			system("cls");
			print "$ProgressText{$phase}\n";
			print "0%                                            100%\n";
			print "$progress\n";
			for ($i = 0; $i < int($progress / 2); $i++) {
				print "\333";
			}
		}
		if ($changed == 1 or $running == 0) {
			sleep(2);
		}
		else {
			sleep(5);
		}
	}
}

# parameters: packageName, where to put the stub

sub createBodyForPackage
{
	
	# checkPoint("called createBodyForPackage with $_[0] $_[1]");

	$specfile = "n:/Stubs/" . getFileNameFromPackageName($_[0], "spec");

	_generateBody($specfile, $_[1]);

	$bodyfile = "$_[1]" . getFileNameFromPackageName($_[0], "body");

	if (-e $bodyfile) {
		_updateBody($bodyfile);
		$reg = addFileToList($_[1], $_[0], "body", \@g_generated_sources);
		# TODO copy stub to n:/Stubs/
		if ($_[1] eq "n:/Additional_Files/") {
			copyFile($reg, "n:/Stubs/", 0)
		}
	}
	else {
		# checkPoint("$bodyfile is not created");
		my @errors = readerror();
		if ($errors[0] !~ m/does not require a body/ 
				and $errors[0] !~ m/cannot have a body/ 
				and $errors[0] !~ m/this instantiation requires/) {

			printerror($running);
		}
		if ($errors[0] =~ m/this instantiation requires \"(.*) \(body\)/) {
			createBodyForPackage($1, "n:/Stubs/");
		}
	}
}

sub _generateBody
{

	print LOG "gnatstub -f -t -In:/Stubs/ $_[0] $_[1]\n";
	system("gnatstub -f -t -In:/Stubs/ $_[0] $_[1] 2>$workdir/error");

}

sub _updateBody
{

	$filename = shift;

	readfile($filename);

	$string = "";
	$package;
	$return_type;
	$infunc = 0;

	my @functions = ();

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

			$newstring = $string;

			# print $newstring . "\n";

			# $tempStr = $newstring;
			# $tempStr =~ tr/\"//;

			# print $tempStr . "\n";

			# @spEntityArray = $db->lookup($tempStr);
			# $spEntity = @spEntityArray[0];
			$paramString = "";
			# if (@spEntityArray != ()) {
			# 	@spEntityParamArray = $spEntity->refs("Ada Declare", "Ada Parameter");
			# 	foreach (@spEntityParamArray) {
			# 		if ($_->ent->type =~ /out /) {
			# 			print "out\n";
			# 			$paramString = "Ada.Text_IO.Put_Line \(\"WARNING: out parameter\"\);\n";
			# 		}
			# 	}
			# 	if ($spEntity->type() ne "") {
			# 		$paramString = "Ada.Text_IO.Put_Line \(\"WARNING: ret value\"\);\n";
			# 	}
			# }

			$newstring =~ tr/\"/'/;
			$newstring_nometa = quotemeta($newstring);

			push(@functions, $newstring);
			@list = grep(/$newstring_nometa/, @functions);
			$counter = $#list + 1;
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

		s/(\s*)pragma Compile_Time_Warning \(Standard.True,(.*)/$1Ada.Text_IO.Put_Line \(\"$newstring \#$counter is called\"\);/;

		s/package body $package is/with Ada.Text_IO;\npackage body $package is/;

		s/end $package;/begin\n\tAda.Text_IO.Put_Line \(\"$package is elaborated\"\);\nend $package;/;

		if ($paramString eq "") {
			s/(\s*)raise Program_Error;\n//;
		}
		else {
			s/(\s*)raise Program_Error;\n/$1$paramString/;
		}

		s/return (.*);/return Result;/;

		print FH;
	}	

	close FH;
}

sub autofix {
	$ref_array = $_[0];
	@error_list = @$ref_array;
	@checked_files = ();
	foreach my $error_line (@error_list) {
		if ($error_line =~ m/(.*)\.adb:(.*):(.*):/) {
			
		}
	}
}

sub compile_routine {

	my $dir;
	if ($_[0] eq "n:/GNAT/U500.gpr") {
		$dir = "n:/Additional_Files/";
	}
	else {
		$dir = "n:/Stubs/";
	}

	my $file;
	my $status = 0;
	my $exit = 0;

	$running = 1;
	system("\"c:\\GNAT\\2012\\bin\\gprbuild.exe\" -q -d $_[0] 1>$workdir/stat 2>$workdir/error");
	$running = 0;

	my @errors = readerror();

	if ($errors[$#error] !~ m/failed/) {
		$status = 2;
		system("cls");
		print "\n-----------------------";
		print "\n| compilation is done |";
		print "\n-----------------------\n";
	}

	if ($status == 0) {
		foreach $e (@errors) {
			if ($e =~ m/file "(.*)\.ad(.)" not found/) {
				$file = lc $1 . ".ad" . $2;
				if (not $file ~~ @backup) {
					push (@backup, $file);
					$p = getPackageNameFromFileName($file);
					# if ($debug == 1) {
					# 	checkPoint($p);
					# }
					addSpecFile($p);
				}
				else {
					print "PEOPLE DO SOMETHING!! ($file cannot be found, but really needed)\nIf you found press ENTER";
					<STDIN>;
				}
				$status = 1;
			}
			if ($e =~ m/cannot generate code for file (.*)\.ads/ or $e =~ m/but file \"(.*)\.adb\" was not found/) {
				$file = lc $1 . ".adb";
				$p = getPackageNameFromFileName($file);
				if ($debug == 1) {
					checkPoint("#1 $p");
				}
				addBodyFile($p, $dir);
				$status = 1;
			}
			if ($e =~ m/(.*?):(.*)body of generic unit \"(.*)\" not found/) {

				$type = getTypeFromFileName($1);
				$absolutePath = getAbsolutePathFromRegistryValue(getRegistryValueFromPackageName(getPackageNameFromFileName($1), $type, \@g_unmodified_sources) );
				# $fileName = getFileNameFromPackageName(getPackageNameFromFileName($1), $type);
				$fileName = $1;
				$file = $absolutePath . $fileName;
				$generic_unit = $3;
				
				readfile($file);
				$idx = 0;
				while ($g_lines[$idx] !~ m/with\s*(.*)$generic_unit;/ and $idx <= $#g_lines) {
					$idx++;
				}
				$g_lines[$idx] =~ m/with\s*(.*)$generic_unit;/; # print @g_lines; <STDIN>;
				$packageToAdd = lc $1 . $generic_unit;

				if ($debug == 1) {
					checkPoint("#2 $packageToAdd");
				}

				addBodyFile($packageToAdd, $dir);
				$status = 1;

			}

			if ($e =~ m/(.*)\.adb:(.*):(.*): unconstrained subtype not allowed \(need initialization\)/) {

				# ********
				# * TODO *
				# ********

				$p = $1;
				$registryValue = getRegistryValueFromPackageName($1, "body", \@g_generated_sources);
				$absolutePath = getAbsolutePathFromRegistryValue($registryValue);
				$file = $absolutePath . $1 . ".adb";

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

				if ($absolutePath ne "n:/Stubs/") {
					copyFile($registryValue, "n:/Stubs/", 0)
				}

				# checkPoint($registryValue);

			}

			if ($e =~ m/cannot generate code for file (.*) \(missing subunits\)/) {
				# print "finding subunits"; <STDIN>;
				@subunits = getSubunits(getPackageNameFromFileName($1));
				foreach $s (@subunits) {
					addFile($s, "body", $dir);
				}
				$status = 1;
			}
		}
	}

	if ($status == 0) {
		printerror($running);
		# if ($_[0] eq "n:/GNAT/U500.gpr"){
		# 	copyAdsFiles;
		# }
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

# **
# @params
# 	$_[0] : Package
# 	$_[1] : Type
# 
# **

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

	$num = 0;

	if ($counter > 0) {
		if ($counter == 1) {
			print LOG "\n" . getPackageNameFromRegistryValue($matches[0]) . "." . $_[1] . " has been automatically selected..\n\n";
			$result = $matches[0];
		}
		else {
			$pr = $running;
			if ($running == 1) {
				$running = 0;
			}
			print "\nPlease choose the most appropriate one to continue:\n\n";
			foreach $match (@matches) {
				print $num++ . " - $match \n\n";
			}
			print "-----------------------\n";
			print "\nfile to copy: ";
			my $in = <STDIN>;
			$result = $matches[$in];
			print "\n\n";
			$running = $pr;
		}
	}
	else {
		print LOG "$package not found\n";
		$result = "nullPointerException";
	}

	return $result;
}

sub getImports {

	# checkPoint("called getImports with $_[0].$_[1]\n");

	my @imports = ();
	$file = getAbsolutePathFromRegistryValue(getRegistryValueFromPackageName($_[0], $_[1], \@g_unmodified_sources)) . getFileNameFromPackageName($_[0], $_[1]);

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
	$ref_array = $_[3];
	$registry = "#dir: $_[0]/ #file: " . getFileNameFromPackageName($_[1], $_[2]);
	push(@$ref_array, $registry);
	return $registry;
}

# **
# @params
#  	$_[0] : Package
#	$_[1] : Type
#	$_[2] : Location
# 
# **

sub addFile {
	$fileToCopy = listFiles($_[0], $_[1]);
	if ($fileToCopy ne "nullPointerException") {
		copyFile($fileToCopy, $_[2], 1);
		if ($_[2] eq "n:/Additional_Files/") {
			copyFile($fileToCopy, "n:/Stubs/", 1);
		}
		addFileToList("n:/Additional_Files/", $_[0], $_[1], \@g_unmodified_sources);
		push(@packagesList, "$_[0].$_[1]");
		return "file added";
	}
	else {
		return "file not added";
	}
}

sub addSpecFile {
	if (addFile($_[0], "spec", "n:/Additional_Files/") eq "file added") {
		gatherSpecFiles($_[0], "spec");
	}
}

sub getSubunits {
	@result = ();
	@p = $db->lookup($_[0], "Ada Package");
    if (@p != ()) {
        @s = $p[0]->refs("Ada Declare Stub");
        foreach $su (@s) {
            push(@result, lc $su->ent->longname());
        }
    }
	return @result;
}

sub addBodyFile {

	# checkPoint("called addBodyFile with $_[0]\n");

	my $toStub = 0;
	# if selected mode is auto
	if (($switches[1] == 0 and not $_[0] ~~ @g_exceptions) or $switches[1] == 3) {
		$toStub = 1;
	}
	if ($switches[1] == 2) {
		print "Would you like to stub the package $_[0]? (Y/N) ";
		$in = <STDIN>;
		if ($in eq "Y\n") {
			$toStub = 1;
		}
	}

	if ($toStub == 1) {
		createBodyForPackage($_[0], $_[1]);
	}
	else {
		if (addFile($_[0], "body", $_[1]) eq "file added") {
			gatherSpecFiles($_[0], "body");
			updateDatabase();
			openDatabase();
			@subunits = getSubunits($_[0]);
			foreach $s (@subunits) {
				addFile($s, "body", $_[1]);
			}
			# checkPoint($_[0]);
		}
	}
}

sub instance_maker {

	my $dr = '-';

	# openStdError();

	foreach $stub (@stubs) {

		$file = getAbsolutePathFromRegistryValue($stub) . getFileNameFromRegistryValue($stub);

		open my $fh, '<', $file or die "error opening $filename: $!";
		my $content = do { local $/; <$fh> };
		close $fh;

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
		my @uses = ();
		my @dt_package_names = ();

		my $modded = 0;

		$content =~ m/package (Manager\.)?(.*) is/;
		$original_package_name_manager = $1;
		$original_package_name = $2;

		while ($content =~ /with (.*);\n(.*\n)?use (.*);/g) {
			push @uses, "with $1;\n$2use $3;\n";
		}

		# DATA_TYPE BEGIN

		# if file has not been modified yet
		if ($content !~ m/-- The file has been modified for testing/) {
        
            # if file contains Data_Type instantiation
            if ($content =~ m/\n( *)package (.*) is new Data_Type/){

                while ($content =~ m/\n( *)package (.*) is new Data_Type(_Gen)?([\s|\(]*\n)?( *)(.*)(\n.*)(\n.*)?;/g) {
                    # get package name
                    $package_name = $2;

                    # creating new files
                    $new_package_name = $original_package_name . "_" . $package_name;	
                    my $new_file = lc "Manager" . $dr . $new_package_name;
                    # mkdir "Data_Type_Instances";
                    copy("templates/manager-data_type_gen.ads", "n:/Stubs/" . $new_file . ".ads") or die "Copy failed: $!";
                    copy("templates/manager-data_type_gen.adb", "n:/Stubs/" . $new_file . ".adb") or die "Copy failed: $!";
                    addFileToList("n:/Stubs/", "manager$dr$new_package_name", "spec", \@g_generated_sources);
                    addFileToList("n:/Stubs/", "manager$dr$new_package_name", "body", \@g_generated_sources);
                    print LOG "Manager\.$new_package_name has been created\n";
                    $dataTypeCount++;

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
                    open(DT, "<n:/Stubs/$new_file.ads") or die "error opening n:/Stubs/$new_file.ads";
                    @g_lines = <DT>;
                    close DT;
                    open (DT, ">n:/Stubs/$new_file.ads");
                    for (@g_lines){
                        s/Manager.Data_Type_Gen.ads/$new_file.ads/;
                        if ($type_prefix =~ /(\w+)/) {
                            s/with TYPE_PREFIX;/with $type_prefix;/
                        }
                        else {
                            s/with TYPE_PREFIX;//;
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
                        if (@uses != ()) {
                            s/with USE/@uses/;
                        }
                        else {
                            s/with USE//;	
                        }
                        print DT;
                    }
                    close DT;

                    # editing the new ada body file
                    open(DT, "<n:/Stubs/$new_file.adb") or die "error opening n:/Stubs/$new_file.adb";
                    @g_lines = <DT>;
                    close DT;
                    open (DT, ">n:/Stubs/$new_file.adb");
                    for (@g_lines){
                        s/INSTANCE_NAME/$new_package_name/;
                        print DT;
                    }
                    close DT;
                    push @dt_package_names, $package_name;

                    # editing the original file
                    # open(DT, "<$file") or die "error opening $file";
                    # @g_lines = <DT>;
                    # close DT;
                    # open (DT, ">$file");
                    # foreach (@g_lines) {
                    # $content =~	s/^([^-])*pragma Elaborate_All\s*\(Data_Type\)/$1--pragma Elaborate_All(Data_Type)/;
                    # $content =~	s/( *)package $package_name is new Data_Type(.*)/--HOST_TEST_BEGIN\npackage $package_name renames Manager.$new_package_name;\n--package $package_name is new Data_Type$2/;
                    # $content =~	s/^( *)\((.*),/--\($2,/g;
                    # $content =~	s/ G_Default_Value( *)=> (.*),/--G_Default_Value$1=> $2,/gi;
                    # $content =~	s/ G_Default_Value( *)=> (.*)\);/--G_Default_Value$1=> $2\);\n--HOST_TEST_END/gi;
                    # $content =~	s/ G_Unit_Of_Measure( *)=> (.*)\);/--G_Unit_Of_Measure$1=> $2\);\n--HOST_TEST_END/gi;
                        # print DT;
                    # }

                    # close DT;

                    push(@withs, $new_package_name);
                }

                # open (DT, ">$file");
                # $to_insert = "";
                # foreach $w (@withs) {
                # 	$to_insert = $to_insert . "with Manager.$with;\n";
                # }
                # foreach (@g_lines) {
                # 	if (s/package (.*) is/--HOST_TEST_BEGIN\n$to_insert\n--HOST_TEST_END\n\npackage $1 is/){
                # 		print DT;
                # 		last;
                # 	}
                # }
                # $content =~ s/package (.*) is( *)\n/--HOST_TEST_BEGIN\n$to_insert\n--HOST_TEST_END\n\npackage $1 is\n/;
                # print DT, $content;
                # close DT;
                # @withs = ();

                $modded = 1;

            }

            # close $fh;

            # DATA_TYPE END

            # PORT_TYPE BEGIN

            if ($content =~ m/\n *package (.*?) is new Port_Type(\_Gen)? \((.*)\n(.*)\n(.*);/) {

                # while ($content =~ m/\n( *)package PT is new Port_Type \((.*)\n(.*)\n(.*);/g) {
                    my $PTC_line = $3;
                    my $Ident_line = $4;
                    my $Type_line = $5;

                    $PTC_line =~ /T_PTC_Name\'\(\"(.*?)\"/;
                    my $PTC = $1;

                    $Ident_line =~ /T_Identifier\'\(\"(.*?)\"/;
                    my $Ident = $1;

                    my $Type;
                    # if ($Type_line =~ /g_Data_Package => DT\)/i){
                    # 	# $new_package_name =~ /Manager\.(.*)/i;
                    # 	# $dt_package_name = $1;
                    # 	$type_prefix = original_package_name;
                    # 	$dt_package_name = $new_package_name;
                    # 	push(@withs, $new_package_name);
                    # 	# print "$dt_package_name"; <STDIN>;
                    # }
                    # else {
                        $Type_line =~ /g_Data_Package => (.*?)( ?)\)/i;
                        $Type = $1;
                        if ($Type =~ /(.*)\.(.*)\.(.*)/) {
                            $dt_package_name = $3;
                            $type_prefix = "Manager." . $2 . "_";
                        }
                        else {
                            if ($Type =~ /(.*)\.(.*)/) {
                                $dt_package_name = $2;
                                $type_prefix = "Manager." . $1 . "_";
                            }
                            else {
                                $Type =~ /(.*)/;
                                $dt_package_name = $1;
                                $type_prefix = "Manager." . $original_package_name . "_";
                            }
                        }

                    # }

                        # $content =~ m/package (Manager\.)?(.*) is/;
                        # $package_name = $2;

                        $new_pt_package_name = $original_package_name . "_PT";

                        # if (!($new_file ~~ @new_files)){

                            # creating new files

                            my $new_file = lc "Manager" . $dr . $new_pt_package_name;
                            # mkdir "Port_Type_Instances";
                            copy("templates/manager-port_type_gen.ads","n:/Stubs/" . $new_file . ".ads") or die "Copy failed: $!";
                            copy("templates/manager-port_type_gen.adb","n:/Stubs/" . $new_file . ".adb") or die "Copy failed: $!";
                            addFileToList("n:/Stubs/", "manager$dr$new_pt_package_name", "spec", \@g_generated_sources);
                            addFileToList("n:/Stubs/", "manager$dr$new_pt_package_name", "body", \@g_generated_sources);
                            print LOG "Manager\.$new_pt_package_name has been created\n";
                            $portTypeCount++;

                            # editing the new ada spec file
                            open(DT, "<n:/Stubs/$new_file.ads") or die "error opening n:/Stubs/$new_file.ads";
                            @g_lines = <DT>;
                            close DT;
                            open (DT, ">n:/Stubs/$new_file.ads");
                            foreach (@g_lines) {
                                s/Manager.Port_Type_Gen.ads/$new_file.ads/;
                                s/INSTANCE_NAME/$new_pt_package_name/;

                                s/with DATA_TYPE_INSTANCE;/with $type_prefix$dt_package_name;\nwith Types;/;
                                # s/with DATA_TYPE_INSTANCE;/with $Type;\nwith Types;/;

                                s/renames DATA_TYPE_INSTANCE/renames $type_prefix$dt_package_name/;
                                # s/renames DATA_TYPE_INSTANCE/renames $Type/;

                                s/G_NAME_PARAMETERS/new Types.T_PTC_Name'\("$PTC"\)/;
                                s/G_IDENTIFIER_PARAMETERS/new Types.T_Identifier'\("$Ident"\)/;
                                print DT;
                            }
                            close DT;
                            open(DT, "<n:/Stubs/$new_file.adb") or die "error opening n:/Stubs/$new_file.adb";
                            @g_lines = <DT>;
                            close DT;
                            open (DT, ">n:/Stubs/$new_file.adb");
                            foreach (@g_lines) {
                                s/INSTANCE_NAME/$new_pt_package_name/;
                                print DT;
                            }
                            close DT;
                        # }
                    # }

                    # editing the original file
                    # open(DT, "<$file") or die "error opening $file";
                    # @g_lines = <DT>;
                    # close DT;
                    # open (DT, ">$file");
                    # foreach (@g_lines) {
                    # $content =~	s/^([^-])*pragma Elaborate_All\s*\(Port_Type\)/$1--pragma Elaborate_All(Port_Type)/;
                    # $content =~	s/^( *)package (.*) is new Port_Type(.*),/--HOST_TEST_BEGIN\npackage $2 renames Manager.$new_package_name;\n--package $2 is new Port_Type$3,/g;
                    # $content =~	s/ g_Identifier/--g_Identifier/g;
                    # $content =~	s/ g_Data_Package => (.*)\);/--g_Data_Package => $1\);\n--HOST_TEST_END/g;
                        # print DT;
                    # }

                    # close DT;

                    push(@withs, $new_pt_package_name);
                

                # open(DT, "<$file") or die "error opening $file";
                # @g_lines = <DT>;
                # close DT;
                # open (DT, ">$file");
                # foreach (@g_lines) {
                # 	foreach $with (@withs) {
                # 		s/with (.*);/with $1;\nwith Manager.$with;/;
                # 	}
                # 	s/with Port_Type;/--with Port_Type;/;
                # 	print DT;
                # }
                # close DT;
                # @withs = ();

                $modded = 1;
            }

            # close $fh;

            # PORT_TYPE END

            # Generic_Operator BEGIN

            if ($content =~ m/is new Generic_Operator([\(|\s]*)/) {

                my $comp_ident;
                my $comp_name;
                my $OUtput_pt_ident;
                my $g_PT_Package;
                my $constant_value;

                while ($content =~ m/( *)package (.*) is new Generic_Operator([\(|\s]*)\n?(.*)\n(.*)\n(.*)\n(.*)\n(.*)\);/g){

                    my $package_name = $2;
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

                    $new_package_name = $package_name . "_GO";

                    # creating the new files

                    my $new_file = lc "Manager" . $dr . $new_package_name;
                    # mkdir "Generic_Operator_Instances";
                    copy("templates/manager-generic_operator.ads","n:/Stubs/" . $new_file . ".ads") or die "Copy failed: $!";
                    copy("templates/manager-generic_operator.adb","n:/Stubs/" . $new_file . ".adb") or die "Copy failed: $!";
                    addFileToList("n:/Stubs/", "manager$dr$new_package_name", "spec", \@g_generated_sources);
                    addFileToList("n:/Stubs/", "manager$dr$new_package_name", "body", \@g_generated_sources);
                    print LOG "Manager\.$new_package_name has been created\n";
                    $genericOperatorCount++;

                    # editing the new ada spec file

                    open(DT, "<n:/Stubs/$new_file.ads") or die "error opening $new_file in stubs";
                    @g_lines = <DT>;
                    close DT;
                    open (DT, ">n:/Stubs/$new_file.ads");
                    foreach (@g_lines) {
                        s/Vital.Generic_Operator.ads/Manager-$new_package_name\.ads/;
                        s/INSTANCE_NAME/$new_package_name/;
                        s/COMPONENT_IDENTIFIER_INSTANCE/$comp_ident/;
                        s/COMPONENT_NAME_INSTANCE/$comp_name/;
                        s/OUTPUT_PT_IDENTIFIER_INSTANCE/$OUtput_pt_ident/;
                        s/g_PT_PACKAGE_INSTANCE/Manager.$g_PT_Package\_PT/;
                        s/CONSTANT_VALUE_INSTANCE/$constant_value/;
                        if ($type_prefix =~ /(\w+)/) {
                            s/with TYPE_PREFIX;/with $type_prefix;/
                        }
                        else {
                            s/with TYPE_PREFIX;//;
                        }
                        print DT;
                    }
                    close DT;

                    # editing the new ada body file
                    open(DT, "<n:/Stubs/$new_file.adb") or die "error opening $new_file in stubs";
                    @g_lines = <DT>;
                    close DT;
                    open (DT, ">n:/Stubs/$new_file.adb");
                    foreach (@g_lines) {
                        s/INSTANCE_NAME/$new_package_name/;
                        print DT;
                    }
                    close DT;
                    # editing the original file
                    # open(DT, "<$file") or die "error opening $file";
                    # @g_lines = <DT>;
                    # close DT;
                    # open (DT, ">$file") or die "error opening $file";
                    # foreach (@g_lines) {
                    # 	# print $_ . "\n";
                    # 	if (s/package (.*) is new Generic_Operator(.*)/--HOST_TEST_BEGIN\npackage $1 renames Manager\.$new_package_name;\n--package $1 is new Generic_Operator$2/) {
                    # 		print "MATCH $file";
                    # 	}
                        
                    # 	print DT;
                    # }
                    # close DT;

                    # close DT;

                    push(@withs, $new_package_name);
                }

                # open(DT, "<$file") or die "error opening $file";
                # @g_lines = <DT>;
                # close DT;
                # open (DT, ">$file");
                # foreach (@g_lines) {
                # 	s/with Generic_Operator;/--with Generic_Operator;\nwith Manager\.$new_package_name;/;
                # 	print DT;
                # }
                # close DT;
                # @withs = ();

                $modded = 1;
            }
        }

		# close $fh;

		# Generic_Operator END

		# editing the original file

		if ($modded == 1) {

			print LOG $original_package_name . " was modified\n";
            
            $content = "-- The file has been modified for testing\n" . $content;

			foreach $dt (@dt_package_names) {
				$content =~ s/( *)package $dt is new(.*)/--HOST_TEST_BEGIN\n$1package $dt renames Manager\.$original_package_name\_$dt;\n$1package $dt\_Original is new $2\n--HOST_TEST_END/;
			}

			$content =~ s/\n( *)package (.*) is new Attribute\.(.*)Data_Package => (\w*)(.*)/\n--HOST_TEST_BEGIN\n$1package $2 is new Attribute\.$3Data_Package => $4\_Original$5\n--HOST_TEST_END/g;

			$content =~	s/( *)package (.*) is new Port_Type(.*),/--HOST_TEST_BEGIN\n$1package $2 renames Manager.$new_pt_package_name;\n$1package $2\_Original is new Port_Type$3,\n--HOST_TEST_END/;
			$content =~	s/( *)g_Data_Package => ([\w|\.]*)( *)\);/--HOST_TEST_BEGIN\n$1g_Data_Package => $2\_Original$3\);\n--HOST_TEST_END/;

			$content =~ s/package (.*) is new Generic_Operator(.*)/--HOST_TEST_BEGIN\npackage $1 renames Manager\.$new_package_name;\n--package $1 is new Generic_Operator$2/;

			# $content =~	s/(\n[^-])*pragma Elaborate_All\s*\(Data_Type\)/$1--pragma Elaborate_All(Data_Type)/s;
			# $content =~	s/( *)(\( *)?G_Value_Type( *)=> (.*),/--$1$2G_Value_Type$3=> $4,/gi;
			# $content =~	s/( *)(\( *)?G_Default_Value( *)=> (.*),/--$1$2G_Default_Value$3=> $4,/gi;
			# $content =~	s/( *)G_Default_Value( *)=> (.*)\);/--$1G_Default_Value$2=> $3\);\n--HOST_TEST_END/gi;
			# $content =~	s/( *)G_Unit_Of_Measure( *)=> (.*)\);/--$1G_Unit_Of_Measure$2=> $3\);\n--HOST_TEST_END/gi;
			# $content =~ s/with Data_Type;/--with Data_Type;/;


			# $content =~	s/(\n[^-])*pragma Elaborate_All\s*\(Port_Type\)/$1--pragma Elaborate_All(Port_Type)/s;
			# $content =~	s/( *)package (.*) is new Port_Type(.*),/--HOST_TEST_BEGIN\npackage $2 renames Manager.$new_package_name;\n--package $2 is new Port_Type$3,/g;
			# $content =~	s/ g_Identifier/--g_Identifier/g;
			# $content =~ s/with Port_Type;/--with Port_Type;/;


			$content =~ s/pragma Elaborate_All\s*\(Generic_Operator\)/--HOST_TEST_BEGIN\n--pragma Elaborate_All(Generic_Operator)\n--HOST_TEST_END/;
			$content =~ s/\n([\(|\s]*)Component_Identifier/\n--$1Component_Identifier/;
			$content =~ s/( *)Component_Name/--$1Component_Name/;
			$content =~ s/( *)Output_PT_Identifier/--$1Output_PT_Identifier/;
			$content =~ s/( *)g_PT_Package/--$1g_PT_Package/;
			$content =~ s/( *)Constant_Value(.*);/--$1Constant_Value$1;\n--HOST_TEST_END/;
			$content =~ s/with Generic_Operator;/--HOST_TEST_BEGIN\n--with Generic_Operator;\nwith Manager\.$new_package_name;\n--HOST_TEST_END/;


			open (DT, ">$file");		
			$to_insert = "";
			foreach $w (@withs) {
				$to_insert = $to_insert . "with Manager.$w;\n";
			}
			$content =~ s/package (.*) is( *)\n/--HOST_TEST_BEGIN\n$to_insert--HOST_TEST_END\n\npackage $1 is\n/;
			print DT $content;
			close DT;

		}


		# if ($modded == 1){
		# 	push(@modded_files, $file)
		# }
	}

	# closeStdError();
}

$number_of_emcs = 0;

sub modify_source {

	@sources = scan("n:/Source/");

	foreach $source (@sources) {

		$file = getAbsolutePathFromRegistryValue($source) . getFileNameFromRegistryValue($source);

		if (getTypeFromRegistryValue($source) eq "body") {

			open FH, "<$file" or die "error";
			@lines = <FH>;
			close FH;

			$content = "";
			foreach $l (@lines) {
				$content = $content . $l;
			}

			$content =~ m/package body (.*) is/;
			$package = $1;

			open FH, ">$file" or die "error";

			if ($content =~ m/g_CTD_Reference/ and $content !~ m/procedure Elab is/) {
				$content =~ s/\nbegin/\n--HOST_TEST_BEGIN\nprocedure Elab is\nbegin\n--HOST_TEST_END/s;
				$content =~ s/end $package;/\n--HOST_TEST_BEGIN\nend Elab;\n--HOST_TEST_END\n\nend $package;/i;
				$number_of_emcs++;
			}

			print FH $content;

			close FH;

		}

	}

}

sub readExceptions {
	open FH, "<n:/exceptions.txt";
	@exs = <FH>;
	close FH;

	foreach $ex (@exs) {
		$ex =~ m/(.*)\n/;
		push(@g_exceptions, lc $1);
	}
}

sub openDatabase {
	($db, $status) = Understand::open("n:/U500.udb") or die "failed to open database";
}

sub updateDatabase {
	if ($db != ()) {
		$db->close();
	}
	print "\n";
	system("und -db n:/U500.udb analyze -rescan 2>$workdir/error");
	system("und -db n:/U500.udb analyze -changed 1>$workdir/understand 2>$workdir/error");
	@udbFile = readFile("$workdir/understand");
	print @udbFile[$#udbFile];
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

sub getTypeFromFileName {
	my $result;
	$_[0] =~ m/(.*)\.ad(.)/;
	if ($2 eq "s") {
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

# **
# @params
#  	$_[0] : Package
#	$_[1] : Type
#	$_[2] : Stub / Source
# 
# **
sub getFileNameFromPackageName {
	$result = lc $_[0];
	$result =~ tr/./-/;
	$result = $result . ".ad" . substr($_[1], 0, 1);
	return $result;
}

sub getRegistryValueFromPackageName {
	my $ext;
	my $ref_array = $_[2];
	if ($_[1] eq "spec") {
		$ext = "s";
	}
	else {
		$ext = "b";
	}
	@result = grep {/#file: $_[0].ad$ext/} @$ref_array;
	if (@result == ()) {
		# print "fatal error: cannot find: $_[0].$_[1]";
		# die;
		 # <STDIN>;
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

sub generateStubBodies {
	$idx = 0;
	$running = 1;
	$c = $#stubs + 1;
	while (@stubs != ()) {
		my @newstubs = ();
		foreach $stub (@stubs) {

			$progress = int($idx / $c * 100);

			$body = "n:/Stubs/" . getFileNameFromPackageName(getPackageNameFromRegistryValue($stub) , "body");
			# $spec = "n:/Stubs/" . getFileNameFromRegistryValue($stub);

			if (!(-e $body)) {
				addBodyFile(getPackageNameFromRegistryValue($stub), "n:/Stubs/");
			}
			if (!(-e $body)) {
				my @errors = readerror();
				if ($errors[0] =~ m/this instantiation requires/) {
					push(@newstubs, $stub);
				}
				if ($errors[0] =~ m/does not require a body/ or $errors[0] =~ m/cannot have a body/) {
					$idx++;
				}
			}
			else {
				$idx++;
			}

			# if (int($idx / $c * 50) > int($progress / 2)) {
			# 	showProgress("Generating body for stubs");
			# }
		}
		@stubs = @newstubs;
	}
	$running = 0;
}

# **
# create a list of all the files on CC
# TODO
# **

@stubs = ();

sub main {

	# clean stat
	open STAT, ">$workdir/stat";
	close STAT;

	# open log files
	open LOG, ">$workdir/log";
    open PACKAGELIST, ">$workdir/packageslist";

	# read available sources from clearcase
	print "Reading CC libraries: ... ";
	@CC_list = scan($CC_Location);
	print "Done.\n";
	readExceptions();

	# create list of sources to compile
    # ???
	@g_unmodified_sources = scan("n:/Source/");

	# copy sources to compile
	print "Copying sources... ";
	if ($switches[0] == 1) {
        # copy all ada files
		copydir("n:/temp/", "n:/Source/", "all", 0);
	}
	else {
        # replace the old ones with the newer ones
		print "copyDiff";
		copyDiff("n:/temp/", "n:/Source/", "all", 0);
	}
	print "Done.\n";

	# insert elab
	print "Modifying sources... ";
	modify_source();
	print "Done. ($number_of_emcs)\n";

	# create list of sources to compile
	@g_original_sources = scan("n:/Source/");
	@g_additional_sources = scan("n:/Additional_Files/");
	@g_unmodified_sources = (@g_additional_sources, @g_original_sources);

	foreach $source (@g_unmodified_sources) {
		$packageName = getPackageNameFromRegistryValue($source);
		$type = getTypeFromRegistryValue($source);
		if (not "$packageName.$type" ~~ @packagesList){
			push(@packagesList, "$packageName.$type");
		}
	}

	# check for dependencies
	print "Gathering spec files\n";
	my @temporalListOfSources = @g_unmodified_sources;
	foreach $source (@temporalListOfSources) {
		gatherSpecFiles(getPackageNameFromRegistryValue($source), getTypeFromRegistryValue($source));
	}

	updateDatabase();
	openDatabase();

	foreach $source (@temporalListOfSources) {
		if (getTypeFromRegistryValue($source) eq "body") {
            
            # checkPoint($source);
            
			@subunits = getSubunits(getPackageNameFromRegistryValue($source));
			foreach $s (@subunits) {
                if (not "$s.body" ~~ @packagesList) {
                    checkPoint($s);
                    addFile($s, "body", "n:/Additional_Files/");
                }
			}
		}
	}

	# copy all ads to stubs
	copydir("n:/Source/", "n:/Stubs/", "spec", 1);
	copydir("n:/Additional_Files/", "n:/Stubs/", "spec", 1);
	@stubs = scan("n:/Stubs/");

	print "Updating database\n";
	updateDatabase();
	openDatabase();

	$phase = 1;
	print "Starting compile routine for sources\n";
	compile_routine("n:/GNAT/U500.gpr");

	print "Generating instances... ";
	instance_maker();
	print "Done. (DT: $dataTypeCount; PT: $portTypeCount; GO: $genericOperatorCount)\n";

	# $mode = 0;
	
	print "Copy custom modifications to the stubs folder! Press ENTER when done"; <STDIN>;

	$phase = 2;
	print "Generating bodies for stubs\n";
	# $debug = 0;
	generateStubBodies();

	$phase = 3;
	$progress = 0;
	# $debug = 0;
	print "\n\nStarting compile routine for stubs\n";
	compile_routine("n:/GNAT/U500Stub.gpr");

	system("cls");
	print "\n-------------------------------------------------------";
	print "\n| your test environment has been successfully created |";
	print "\n-------------------------------------------------------\n";

	$phase = 4;

	close LOG;
}

sub init {

	# set variables
	$ProgressText{1} = "Source compilation in progress";
	$ProgressText{2} = "Generating bodies for stubs";
	$ProgressText{3} = "Stub compilation in progress";
	$running = 0;
	$progress = 0;
	$phase = 0;
	$debug = 0;
	setMode();

	print "\nClearCase location: ";
	$CC_Location = <STDIN>;
	$CC_Location =~ m/(.*)\n/;
	$CC_Location = $1;
	if (substr($CC_Location, -1, 1) ne "\\") {
		$CC_Location = $CC_Location . "\\";
	}
	$CC_Location =~ s/\\/\//g;
    
   	# start progressbar thread
	$thr = threads->create('showProgress');
	print "\n$CC_Location";
}

# share variables between threads
$running; share($running);
%ProgressText; share(%ProgressText);
$progress; share($progress);
$phase; share($phase);
$semaphore = Thread::Semaphore->new();

init();
main();

$thr->join();