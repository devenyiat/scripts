use Cwd;
use File::Copy;
use File::Path;
use File::stat;
use Understand;
use threads;
use threads::shared;
use Thread::Semaphore;
use strict;

use Data::Dumper;

# ****************************
# GLOBAL VARIABLES
# ****************************

our %availableAdditinalSources;
our %locations;
our %fileList;
our $db;
our @packagesNotToStub;

our %settings; share(%settings);



# our $semaphore = Thread::Semaphore->new();


# ****************************
# scandirs
#	$_[0] : folder
#	$_[1] : relative path to $_[0]
#	$_[2] : list of found files /reference/
# ****************************
sub scandirs {
	my $base = $_[0];
	my $reldir = $_[1];
	my $dir = $base . $reldir;
	
	my $ref = $_[2];
	
	chdir($dir);
	my @files = <*>;
	foreach my $file (@files) {
		chdir($dir);
		if (-f $file) {
			my $regExpForFileName = "(.*)(" . $settings{"source_spec_ext"} . "|" . $settings{"source_body_ext"} . ")\$";
			if ($file =~ /$regExpForFileName/) { 
				push(@{$ref->{lc getKey($file, "source")}}, {"abs" => $dir, "rel" => $reldir});
			}
		}
		if (-d $file) {
			scandirs($base, $reldir . "/" . $file, $ref);
		}
	}
}

# ****************************
# copyFile
# 	$_[0] : key
#	$_[1] : source dir
#	$_[2] : destination dir
#	$_[3] : fromtype (source / stub)
#	$_[4] : totype (source / stub)
# ****************************
sub copyFile {

	my $package = substr($_[0], 0, -5);
    my $type = substr($_[0], -4);
	
	# my $specRegExp = "(.*)" . $settings{$_[3] . "_spec_ext"};
	# my $bodyRegExp = "(.*)" . $settings{$_[3] . "_body_ext"};
	# my $sepRegExp1 = "\\" . $settings{$_[3] . "_dot_repl"};
	# my $sepRegExp2 = $settings{$_[4] . "_dot_repl"};
	
	# my $type;
	# if ($_[0] =~ m/$specRegExp/) {
		# $type = "spec";
	# }
	# if ($_[0] =~ m/$bodyRegExp/) {
		# $type = "body";
	# }
	# my $fileWithoutExt = $1;
	
	# $fileWithoutExt =~ s/$sepRegExp1/$sepRegExp2/g;
	# $fileWithoutExt .= $settings{$_[4] . "_dot_repl"};
	
	# my $mixedCaseRegexp1 = "(.*?)([\\" . $settings{$_[4] . "_dot_repl"} . "|_])";
	# # my $mixedCaseRegexp2 = $settings{$_[4] . "_dot_repl"};
	
	# if ($settings{$_[4] . "_casing"} eq "MixedCase") {
		# $fileWithoutExt =~ s/$mixedCaseRegexp1/\u$1$2/g;
	# }
	# if ($settings{$_[4] . "_casing"} eq "lowercase") {
		# $fileWithoutExt = lc $fileWithoutExt;
	# }
    
    my $oldFileName = convertKeyToFileName($_[0], $_[3]);
    my $newFileName = convertKeyToFileName($_[0], $_[4]);
	
	# my $newFileName = substr($fileWithoutExt, 0, -1) . $settings{$_[4] . "_" . $type . "_ext"};
	
	my $from = $_[1] . "/" . $oldFileName;
	my $to = $_[2] . "/" . $newFileName;

	copy($from, $to) or die "died at copying from $from to $to";
    
	$fileList{$_[4]}{lc $_[0]} = {"abs" => $_[2], "rel" => ""};
	if ($_[2] eq "n:/Additional_Files") {
		$fileList{"additional"}{lc $_[0]} = {"abs" => $_[2], "rel" => ""};
	}

	chmod 0777, $to;
}

# ****************************
# copydir
# 	$_[0] : Source directory
#	$_[1] : Destination directory
#	$_[2] : Type of files to be copied
#	$_[3] : Keep directory structure (0 - yes / 1 - no)
#	$_[4] : source dir's naming convention (source / stub)
#	$_[5] : dest dir's naming convention
# 
# ****************************
sub copydir {
	my %files;
	scandirs($_[0], "", \%files);
	foreach my $key (keys %files) {
		if ($_[2] eq "all" or $key =~ m/$_[2]$/) {
			my $toCopy = 0;
			if ($#{$files{$key}} != 0) {
				print "There is more than one $key\n";
				# TODO 1.3.0 choose 
			}
			my $fromDir = $files{$key}[$toCopy]{"abs"};
			my $toDir;
			if ($_[3] == 0) {
				$toDir = $_[1] . $files{$key}[$toCopy]{"rel"};
				mkpath($toDir);
			}
			else {
				$toDir = $_[1];
			}
			copyFile($key, $fromDir, $toDir, $_[4], $_[5]);
		}
	}
}

# ****************************
# readFile
#	$_[0] : file
# ****************************
sub readFile {
	my $wholefile = "";
	my @fileByLines;
	open FH, "<$_[0]" or die "error reading $_[0]";
	@fileByLines = <FH>;
	close FH;
	foreach my $line (@fileByLines) {
		$wholefile = $wholefile . $line;
	}
	return ($wholefile, @fileByLines);
}

# ****************************
# readExceptions
# ****************************
sub readExceptions {
	(my $temp, my @lines) = readFile("n:/" . $settings{"exceptions_file"});
	
	foreach my $ex (@lines) {
		$ex =~ m/(.*)\n/;
		push(@packagesNotToStub, lc $1);
	}
}

# ****************************
# getKey
#	$_[0] : filename
#	$_[1] : source / stub
#	return : key
# ****************************
sub getKey {
    
    my $specRegExp = "(.*)" . $settings{$_[1] . "_spec_ext"};
	my $bodyRegExp = "(.*)" . $settings{$_[1] . "_body_ext"};
	my $sepRegExp = "\\" . $settings{$_[1] . "_dot_repl"};
	
    my $type;
	if ($_[0] =~ m/$specRegExp/) {
        $type = ".spec";
    }
    
    if ($_[0] =~ m/$bodyRegExp/) {
        $type = ".body";
    }
	
	my $result = $1;
    $result =~ s/$sepRegExp/./g;
	
	return lc $result . $type;
    
}

# ****************************
# getPackageName
#	$_[0] : filename
#	$_[1] : source / stub
#	return : package name
# ****************************
sub getPackageName {
	
	return substr(getKey($_[0], $_[1]), 0, -5);
    
}

# ****************************
# getType
#	$_[0] : filename
#	$_[1] : source / stub
#	return : spec / body
# ****************************
sub getType {

	return substr(getKey($_[0], $_[1]), -4);

}

# ****************************
# convertKeyToFileName
#	$_[0] : key
#	$_[1] : source / stub
#	return : file name
# ****************************
sub convertKeyToFileName {
	
    my $package = substr($_[0], 0, -5);
    my $type = substr($_[0], -4);
    
	my $regExp = $settings{$_[1] . "_dot_repl"};
	my $mixedCaseRegexp = "(.*?)([\\.|_])";
	
	my $result = $package;
	$result .= ".";
	
	if ($settings{$_[1] . "_casing"} eq "lowercase") {
		$result = lc $result;
	}
	
	if ($settings{$_[1] . "_casing"} eq "MixedCase") {
		$result =~ s/$mixedCaseRegexp/\u$1$2/g;
	}
	
	$result = substr($result, 0, -1);
	
	$result =~ s/\./$regExp/g;
	$result .= $settings{$_[1] . "_" . $type . "_ext"};
	
	return $result;
	
}

# ****************************
# readProgress
# ****************************
sub readProgress {

	my $workdir = $settings{"work_dir"};
	(my $temp, my @stat) = readFile("$workdir/stat");
	
	if ($stat[$#stat-1] =~ m/\((.*)\%\)/) {
		if ($settings{"progress_bar_value"} < $1) {
			$settings{"progress_bar_value"} = $1;
			return 1;
		}
	}

	return 0;
}

sub writeProgress {
	my $workdir = $settings{"work_dir"};
	open STAT, ">$workdir/stat";
	print STAT "$_[0]\%";
	close STAT;
}

sub showProgress {
	while ($settings{"build_phase"} < 4) {
		my $changed ;
		if ($settings{"is_running"} == 1) {
			if ($settings{"build_phase"} != 2) {
				$changed = readProgress();
			}
			system("cls");
			my $text = $settings{"progress_text_" . $settings{"build_phase"}};
			print "$text\n";
			print "0%                                            100%\n";
			$text = $settings{"progress_bar_value"};
			print "$text\n";
			for (my $i = 0; $i < int($settings{"progress_bar_value"} / 2); $i++) {
				print "\333";
			}
		}
		if ($changed == 1 or $settings{"is_running"} == 0) {
			sleep(2);
		}
		else {
			sleep(5);
		}
	}
}

# ****************************
# openDatabase
# ****************************
sub openDatabase {
	($db, my $status) = Understand::open("n:/U500.udb") or die "failed to open database";
}

# ****************************
# updateDatabase
# ****************************
sub updateDatabase {
	if ($db != ()) {
		$db->close();
	}
	print "\n";
	my $workdir = $settings{"work_dir"};
	system("und -db n:/U500.udb analyze -rescan 2>$workdir/error");
	system("und -db n:/U500.udb analyze -changed 1>$workdir/understand 2>$workdir/error");
	(my $temp, my @udbFile) = readFile("$workdir/understand");
	print @udbFile[$#udbFile];
}

# ****************************
# selectFile
# 	$_[0] : key
# 	return selected file
# ****************************
sub selectFile {

	# checkPoint("called selectFile with $_[0].$_[1]");

	my $counter = 0;
	my $result;
	my $package = $_[0];

	my @matches;
	if (not $availableAdditinalSources{lc $_[0]}) {
		print LOG "$package not found\n";
		$result = "nullPointerException";
	}
	else {
		@matches = @{$availableAdditinalSources{lc $_[0]}};
		$counter = $#matches + 1;

		my $num = 0;	

		if ($counter == 1) {
			print LOG "\n" . $_[0] . " has been automatically selected..\n\n";
			$result = $matches[0]{"abs"};
		}
		else {
			my $pr = $settings{"is_running"};
			$settings{"is_running"} = 0;
			print "\nPlease choose the most appropriate location to continue for $_[0]:\n\n";
			foreach my $match (@matches) {
				my %m = %{$match};
				print $num++ . " - " . $m{"abs"} . "\n\n";
			}
			print "-----------------------\n";
			print "\nfile to copy: ";
			my $in = <STDIN>;
			$result = $matches[$in]{"abs"};
			print "\n\n";
			$settings{"is_running"} = $pr;
		}
	}

	return $result;
}

# ****************************
# addFile
#  	$_[0] : key
#	$_[1] : location
#   $_[2] : stubs too (0 - no, 1 - yes)
#	spec / body
# ****************************
sub addFile {
    my $package = substr($_[0], 0, -5);
	my $filename = convertKeyToFileName($_[0], "source");
	if (not $fileList{$locations{$_[1]}}{lc $_[0]}) {
		
		my $locOfFileToCopy = selectFile($_[0]);
		
		if ($locOfFileToCopy ne "nullPointerException") {
			copyFile($_[0], $locOfFileToCopy, $_[1], "source", $locations{$_[1]});
			if ($_[1] eq "n:/Additional_Files" and $_[2] == 1) {
				copyFile($_[0], $locOfFileToCopy, "n:/Stubs", "source", "stub");
			}
			
			# addFileToList("n:/Additional_Files/", $_[0], $_[1], \@g_unmodified_sources);
			# push(@packagesList, "$_[0].$_[1]");
			return "$filename";
		}
		else {
			return "no match";
		}
	}
	return "existing file";
}

# ****************************
# addSpecFile
#  	$_[0] : package
# ****************************
sub addSpecFile {
	my $result = addFile($_[0] . ".spec", "n:/Additional_Files", 1);
	if ($result ne "no match" && $result ne "existing file") {
		gatherPackages($result);
	}
}

# ****************************
# createBodyForPackage
#	$_[0] : package
#	$_[1] : where to put the stub
# ****************************
sub createBodyForPackage
{
	
	# checkPoint("called createBodyForPackage with $_[0] $_[1]");

	my $specfile = "n:/Stubs/" . convertKeyToFileName($_[0] . ".spec", "stub");

	_generateBody($specfile);

	my $bodyfile = "n:/Stubs/" . convertKeyToFileName($_[0] . ".body", "stub");

	if (-e $bodyfile) {
		# _updateBody($bodyfile);
		
		$fileList{"stub"}{$_[0] . ".body"} = {"abs" => "n:/Stubs", "rel" => ""};
		
		if ($_[1] eq "n:/Additional_Files") {
			copyFile($_[0] . ".body", "n:/Stubs", "n:/Additional_Files", "stub", "source");
		}
	}
	else {
		# checkPoint("$bodyfile is not created");
		my @errors = readerror();
		if ($errors[0] !~ m/does not require a body/ 
				and $errors[0] !~ m/cannot have a body/ 
				and $errors[0] !~ m/this instantiation requires/) {

			error_handler(\@errors, "n:/Stubs");
		}
		if ($errors[0] =~ m/this instantiation requires \"(.*) \(body\)/) {
			createBodyForPackage($1, "n:/Stubs");
		}
	}
}

sub _generateBody
{

	print LOG "gnatstub -f -t -In:/Stubs/ $_[0] n:/Stubs/ \n";
	my $workdir = $settings{"work_dir"};
	system("gnatstub -f -t -In:/Stubs/ $_[0] n:/Stubs/ 2>$workdir/error");

}

# sub _updateBody
# {

# 	my $filename = shift;

# 	readfile($filename);

# 	my $string = "";
# 	my $package;
# 	my $return_type;
# 	my $infunc = 0;

# 	my @functions = ();

# 	open FH, ">$filename";

# 	foreach (@g_lines) {

# 		if (m/(\s+)end (\S*);$/) {
# 			# $temp = $1;
# 			$string =~ m/(.*)\.(.*)/;
# 			$string = $1;
# 		}

# 		if (m/body (\S*)/ or m/procedure (\S*)/ or m/function (\S*)/ or m/entry (\S*)/) {
# 			if ($string ne "") {
# 				$sp = $1;
# 				$string = $string . "." . $1;
# 			}
# 			else {
# 				$string = $1;
# 				$package = $1;
# 			}

# 			$newstring = $string;

# 			# print $newstring . "\n";

# 			# $tempStr = $newstring;
# 			# $tempStr =~ tr/\"//;

# 			# print $tempStr . "\n";

# 			# @spEntityArray = $db->lookup($tempStr);
# 			# $spEntity = @spEntityArray[0];
# 			$paramString = "";
# 			# if (@spEntityArray != ()) {
# 			# 	@spEntityParamArray = $spEntity->refs("Ada Declare", "Ada Parameter");
# 			# 	foreach (@spEntityParamArray) {
# 			# 		if ($_->ent->type =~ /out /) {
# 			# 			print "out\n";
# 			# 			$paramString = "Ada.Text_IO.Put_Line \(\"WARNING: out parameter\"\);\n";
# 			# 		}
# 			# 	}
# 			# 	if ($spEntity->type() ne "") {
# 			# 		$paramString = "Ada.Text_IO.Put_Line \(\"WARNING: ret value\"\);\n";
# 			# 	}
# 			# }

# 			$newstring =~ tr/\"/'/;
#             $newstring_for_understand = $string;
#             $newstring_for_understand =~ tr/\"//;
# 			$newstring_nometa = quotemeta($newstring);

# 			push(@functions, $newstring);
# 			@list = grep(/$newstring_nometa/, @functions);
# 			$counter = $#list + 1;
# 		}

# 		if (m/return (\S*)( is)?\n/ and $1 !~ m/;/) {
# 			$return_type = $1;
# 			# print $return_type . "\n";
# 			if (hasDiscriminant($return_type) or hasDiscriminant("?*" . $return_type)) {
# 				$return_type = $return_type . "(1)";
# 			}
# 			# if (isArray($return_type) or isArray("?*" . $return_type)) {
# 			# 	$return_type = $return_type . "(1..1)";
# 			# }
# 		}


#         # TODO        
#         # my $type_entitiy;
#         # my $init_value = "";
#         # @p = $db->lookup($newstring_for_understand, "Ada Procedure, Ada Function");
#         # if (@p != ()) {
#         #     # print $p[0]->longname();
#         #     $type_entitiy = $p[0]->refs("Ada Typed");
#         #     if ($type_entitiy != ()) {
#         #         $type_entitiy = $p[0]->refs("Ada Typed")->ent;
#         #         getSubItems(\$init_value, $type_entitiy, 1, 0);
#         #     }
#         # }

# 		if ($return_type ne "") {
# 			# if (s/(\s*)?(.*)?(\s+)is/$1$2$3is\n$1  Result : $return_type := $init_value;/) {
# 			if (s/(\s*)?(.*)?(\s+)is/$1$2$3is\n$1  Result : $return_type;/) {
# 				$return_type = "";
# 			}
# 		}

# 		s/(\s*)pragma Compile_Time_Warning \(Standard.True,(.*)/$1Ada.Text_IO.Put_Line \(\"$newstring \#$counter is called\"\);/;

# 		s/package body $package is/with Ada.Text_IO;\npackage body $package is/;

# 		s/end $package;/begin\n\tAda.Text_IO.Put_Line \(\"$package is elaborated\"\);\nend $package;/;

# 		if ($paramString eq "") {
# 			s/(\s*)raise Program_Error;\n//;
# 		}
# 		else {
# 			s/(\s*)raise Program_Error;\n/$1$paramString/;
# 		}

# 		s/return (.*);/return Result;/;

# 		print FH;
# 	}	

# 	close FH;
# }

# ****************************
# getSubunits
#	$_[0] : package
# ****************************
sub getSubunits {
	my @result = ();
	my @p = $db->lookup($_[0], "Ada Package");
    if (@p != ()) {
        my @s = $p[0]->refs("Ada Declare Stub");
        foreach my $su (@s) {
            push(@result, $su->ent->longname());
        }
    }
	return @result;
}

# ****************************
# addBodyFile
#	$_[0] : package
#	$_[1] : dir
# ****************************
sub addBodyFile {

	# checkPoint("called addBodyFile with $_[0]\n");

	if ($_[1] eq "n:/Stubs" and $fileList{"additional"}{$_[0] . ".body"}) {
		copyFile($_[0] . ".body", "n:/Additional_Files", "n:/Stubs", "source", "stub");
	}
	else {
		my $toStub = 0;
		
		# if selected mode is auto
		if (($settings{"stub_mode"} eq "auto" 
			and not lc $_[0] ~~ @packagesNotToStub) 
			or $settings{"stub_mode"} eq "stub everything"
			or $_[1] eq "n:/Stubs") {
			$toStub = 1;
		}
		if ($settings{"stub_mode"} eq "manual") {
			print "Would you like to stub the package $_[0]? (Y/N) ";
			my $in = <STDIN>;
			if ($in eq "Y\n") {
				$toStub = 1;
			}
		}

		if ($toStub == 1) {
			createBodyForPackage($_[0], $_[1]);
		}
		else {
			my $result = addFile($_[0] . ".body", $_[1], 1);
			if ($result ne "no match" and $result ne "existing file") {
				gatherPackages($result);
				(my $file, my @temp) = readFile($result);
				if ($file =~ m/separate/) {
					updateDatabase();
					openDatabase();
					my @subunits = getSubunits($_[0]);
					foreach my $s (@subunits) {
						# my $sufileToAdd = convertPackageToFileName($s, "body", $locations{$_[1]});
						addFile($s . ".body", $_[1], 1);
					}
				}
				
				# checkPoint($_[0]);
			}
		}
	}
}

# ****************************
# getImports
#	$_[0] : file
# ****************************
sub getImports {

	# checkPoint("called getImports with $_[0].$_[1]\n");

	my @imports = ();
	# $file = getAbsolutePathFromRegistryValue(getRegistryValueFromPackageName($_[0], $_[1], \@g_unmodified_sources)) . getFileNameFromPackageName($_[0], $_[1]);
	my $key = getKey($_[0], "source");
	my $file = $fileList{"source"}{$key}{"abs"} . "/" . $_[0];

	# open FH, "<$file";
	# my @lines = ();
	# @lines = <FH>;
	# close FH;

	(my $whole, my @lines) = readFile($file);

	my $idx = 0;

	while ($lines[$idx] !~ m/^package/i and $idx<=$#lines) {
		if ($lines[$idx] =~ m/^with\s*(.*?)\s*;/) {
			my $packageToAdd = $1;
			if (not $fileList{"source"}{lc $packageToAdd . ".spec"}) {
				# my $sepRegExp1 = "\\.";
				# my $sepRegExp2 = $settings{"source_spec_ext"};
				# $packageToAdd =~ s/$sepRegExp1/$sepRegExp2/g;
				# $fileToAdd = $packageToAdd . $settings{"source_spec_ext"};
				push(@imports, $packageToAdd);
			}
			else {
				# print " is not new\n";
			}
		}
		$idx++;
	}

	return @imports;
}

# ****************************
# gatherPackages
#	$_[0] : file
# ****************************
sub gatherPackages {

	my $package = getPackageName($_[0], "source");
	my @listToGather = ();

	if ($package =~ m/\./) {
		$package =~ m/(.*)\.(.*)/;
		my $parent_package = $1;
		push(@listToGather, $parent_package);
	}

	@listToGather = (@listToGather, getImports($_[0]));

	foreach my $packageToAdd (@listToGather) {
		if (not $fileList{"source"}{lc $packageToAdd . ".spec"}) {
			addSpecFile($packageToAdd);
		}
		if (not $fileList{"source"}{lc $packageToAdd . ".body"}) {
			addBodyFile($packageToAdd, "n:/Additional_Files");
		}
	}

}

# ****************************
# generateStubBodies
# ****************************
sub generateStubBodies {
	
	my $idx = 0;
	$settings{"is_running"} = 1;
	
	my @stubs;
	foreach my $key (keys %{$fileList{"stub"}}) {
		push(@stubs, $key);
	}

	my $c = $#stubs + 1;
	
	while (@stubs != ()) {
		my @newstubs = ();
		foreach my $stub (@stubs) {

			$settings{"progress_bar_value"} = int($idx / $c * 100);

			my $body = "n:/Stubs/" . convertKeyToFileName(substr($stub, 0, -5) . ".body", "stub");
			# $spec = "n:/Stubs/" . getFileNameFromRegistryValue($stub);

			if (!(-e $body)) {

				my $package = substr($stub, 0, -5);
				addBodyFile($package, "n:/Stubs");
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
	$settings{"is_running"} = 0;
}


sub readerror {
	# $semaphore->down();
	my @result = ();
	my $workdir = $settings{"work_dir"};
	open FH, "<$workdir/error";
	@result = <FH>;
	close FH;
	# $semaphore->up();
	return @result;
}

sub printerror {
	my $state = $settings{"is_running"};
	$settings{"is_running"} = 0;
	my @errors = readerror();
	print "\n-----------------------\n\nError occurred during operation, which cannot be automatically fixed:\n\n";
	foreach my $e (@errors) {
		print $e;
	}
	print "\n-----------------------\n\n";
	print "\nWaiting for user interaction...\nPress ENTER when error is eliminated..."; <STDIN>;
	$settings{"is_running"} = $state;
}

our @neededFiles;
sub error_handler {

	my @errors = readerror();
	
	my $status = 0;
	my $dir = $_[1];

	foreach my $e (@errors) {
	
		if ($e =~ m/file \"(.*)\" not found/) {
			if (not $1 ~~ @neededFiles) {
				push (@neededFiles, $1);
				addSpecFile(getPackageName($1, $locations{$dir}));
			}
			else {
				print "Missing file in ClearCase: $1 cannot be found, but needed\n" . 
					"Please remove the references in the source, then press ENTER";
				<STDIN>;
			}
			$status = 1;
		}
		
		my $regExp1 = "cannot generate code for file (\\S*)";
		my $regExp2 = "but file \"(.*)\" was not found";
		if ($e =~ m/$regExp1/ or $e =~ m/$regExp2/) {
			my $packageToAdd = getPackageName($1, $locations{$dir});
			addBodyFile($packageToAdd, $dir);
			$status = 1;
		}
		
		if ($e =~ m/(.*?):(.*)body of generic unit \"(.*)\" not found/) {

			my $file = $fileList{$locations{$dir}}{getKey($1, $locations{$dir})}{"abs"} . "/" . $1;
			my $generic_unit = $3;
			
			(my $temp, my @lines) = readFile($file);
			my $idx = 0;
			while ($lines[$idx] !~ m/with\s*(.*)$generic_unit;/ and $idx <= $#lines) {
				$idx++;
			}
			$lines[$idx] =~ m/with\s*(.*)$generic_unit;/; # print @g_lines; <STDIN>;
			my $packageToAdd = $1 . $generic_unit;

			addBodyFile($packageToAdd, $dir);
			$status = 1;

		}

		if ($e =~ m/(.*):(.*):(.*): unconstrained subtype not allowed \(need initialization\)/) {

			my $file = $fileList{$locations{$dir}}{getKey($1, $locations{$dir})}{"abs"} . "/" . $1;

			open FH, "<$file";
			my @lines = ();
			@lines = <FH>;
			close FH;

			open FH, ">$file";
			my $lineNumber = $2-1;
			$lines[$lineNumber] =~ s/Result : (.*);/Result : $1\(1..1\);/;
			foreach (@lines) {
				print FH $_;
			}
			close FH;
			$status = 1;

			# TODO 1.3.0
			# if ($absolutePath ne "n:/Stubs/") {
				# copyFile($registryValue, "n:/Stubs/", 0)
			# }

		}

		if ($e =~ m/cannot generate code for file (.*) \(missing subunits\)/) {
			# print "finding subunits"; <STDIN>;
			my @subunits = getSubunits(getPackageNameFrom($1, $locations{$dir}));
			foreach my $s (@subunits) {
				# my $fileToAdd = convertPackageToFileName($s, "body", $locations{$dir});
				addFile($s, $dir, 0);
			}
			$status = 1;
		}
	}

	return $status;
}

# ****************************
# createInstances
# ****************************
sub createInstances {

	my $dr = '-';

	# openStdError();
	
	my @counters = (0, 0, 0);

	foreach my $stub (keys %{$fileList{"stub"}}) {

		my $file = $fileList{"stub"}{$stub}{"abs"} . "/" . convertKeyToFileName($stub, "stub");

		open my $fh, '<', $file or die "error opening $file: $!";
		my $content = do { local $/; <$fh> };
		close $fh;

		my $package_name;
		my $dt_package_name;
		my $original_package_name;
		my $new_package_name;
		my $type_prefix;
		my @withs = ();
		my @uses = ();
		my @dt_package_names = ();

		my $modded = 0;

		$content =~ m/package (Manager\.)?(.*) is/;
		$original_package_name_manager = $1;
		$original_package_name = $2;

		# TODO ez igy nem az igazi, elég lenne a use-okat kigyűjteni
		while ($content =~ /with (.*);\n(.*\n)?use (.*);/g) {
			push @uses, "with $1;\n$2use $3;\n";
		}

		# DATA_TYPE BEGIN

		# if file has not been modified yet
		if ($content !~ m/-- The file has been modified for testing/) {
        
            # if file contains Data_Type instantiation
            if ($content =~ m/is.*?new.*?Data_Type/m){

                while ($content =~ m/package\s+(\S*)\s+is\s+new\s+Data_Type(.*?)\);/gm) {
				
					$counters[0]++;
				
                    # get package name
                    $package_name = $1;
					my $dataTypeInstanceParameters = $2;

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
					
					$dataTypeInstanceParameters =~ /G_Value_Type\s*=>\s*(\S+)\s*,/i;
					my $gValueType = $1;
					
					my $typePrefix = "";
					if ($gValueType =~ /(.*)\./) {
						$typePrefix = "with $1;";
					}
					
					$dataTypeInstanceParameters =~ /G_Default_Value\s*=>\s*(\S+)\s*(\)|,)/i;
					my $gDefaultValue = $1;
					
					my $gUnitOfMeasure = "Types.None";
					if ($dataTypeInstanceParameters =~ /G_Unit_Of_Measure\s*=>\s*(\S+)\s*,/i) {
						$gUnitOfMeasure = $1;
					}

                    # editing the new ada spec file
                    open(DT, "<n:/Stubs/$new_file.ads") or die "error opening n:/Stubs/$new_file.ads";
                    @g_lines = <DT>;
                    close DT;
                    open (DT, ">n:/Stubs/$new_file.ads");
                    for (@g_lines){
                        s/Manager.Data_Type_Gen.ads/$new_file.ads/;
                        s/with TYPE_PREFIX;/with $type_prefix;/
                        s/INSTANCE_NAME/$new_package_name/;
                        s/G_VALUE_TYPE_PARAMATER/$value_type/;
                        s/G_DEFAULT_VALUE_PARAMATER/$default_value/;
                        s/G_UNIT_OF_MEASURE_PARAMETER/$unit_of_measure/;
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
                    push(@withs, $new_package_name);
                }

                $modded = 1;

            }

            # DATA_TYPE END

            # PORT_TYPE BEGIN

            if ($content =~ m/package\s+(\S*)\s+is\s+new\s+Port_Type(.*?);/m) {
			
				$counters[1]++;

                my $portTypeInstanceParameters = $2;
				
				$portTypeInstanceParameters =~ /g_Data_Package\s*=>\s*([^\)|^\s]+)/i;
				my $gDataPackage = $1;
				
				$portTypeInstanceParameters =~ /g_Name\s*=>\s*\"(.*?)\"/i;
				my $gName = $1;
				
				$portTypeInstanceParameters =~ /g_Identifier\s*=>\s*\"(.*?)\"/i;
				my $gIdentifier = $1;
				
				if ($gDataPackage =~ /(.*)\.(.*)/) {
					$type_prefix = "Manager." . $1 . "_";
				}
				else {
					print LOG "WARNING: circular dependency in $original_package_name";
				}


				$new_pt_package_name = $original_package_name . "_PT";

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
					s/with DATA_TYPE_INSTANCE;/with $type_prefix$dt_package_name;\n/;
					s/renames DATA_TYPE_INSTANCE/renames $type_prefix$dt_package_name/;
					s/G_NAME_PARAMETERS/"$PTC"/;
					s/G_IDENTIFIER_PARAMETERS/"$Ident"/;
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

				push(@withs, $new_pt_package_name);

                $modded = 1;
            }

            # PORT_TYPE END

            # Generic_Operator BEGIN

            if ($content =~ m/is new Generic_Operator([\(|\s]*)/) {
			
				$counters[2]++;

                my $comp_ident;
                my $comp_name;
                my $OUtput_pt_ident;
                my $g_PT_Package;
                my $constant_value;

                while ($content =~ m/package\s+(\S+)\s+is\s+new\s+Generic_Operator(.*?);/gm){

                    my $genericOperatorInstanceParameters = $1;

                    $genericOperatorInstanceParameters =~ /Component_Identifier\s*=>\s*(.*?)\s*,/i;
                    my $componentIdentifier = $1;

                    $genericOperatorInstanceParameters =~ /Component_Name\s*=>\s*(.*?)\s*,/i;
                    my $componentName = $1;

                    $genericOperatorInstanceParameters =~ /Output_PT_Identifier\s*=>\s*(.*?)\s*,/i;
                    my $outputPTIdentifier = $1;

                    $genericOperatorInstanceParameters =~ /g_PT_Package\s*=>\s*(.*?)\.PT\s*,/i;
                    my $gPTPackage = $1;

                    $genericOperatorInstanceParameters =~ /Constant_Value\s*=>\s*(.*?)\s*\)/i;
                    my $constantValue = $1;
					
					$type_prefix = "";
                    if ($constantValue =~ /(.*)\.(.*)/) {
						$type_prefix = "with $1;";
					}

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
                        s/with TYPE_PREFIX;/$type_prefix/;
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

                    push(@withs, $new_package_name);
                }

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
				$content =~ s/( *)package $dt is(.*)/--HOST_TEST_BEGIN\n$1package $dt renames Manager\.$original_package_name\_$dt;\n$1package $dt\_Original is$2\n--HOST_TEST_END/;
			}

			$content =~ s/\n( *)package (.*) is new Attribute\.(.*)Data_Package => (\w*)(.*)/\n--HOST_TEST_BEGIN\n$1package $2 is new Attribute\.$3Data_Package => $4\_Original$5\n--HOST_TEST_END/g;

			$content =~	s/( *)package (.*) is new Port_Type(.*),/--HOST_TEST_BEGIN\n$1package $2 renames Manager.$new_pt_package_name;\n$1package $2\_Original is new Port_Type$3,\n--HOST_TEST_END/;
			$content =~	s/( *)g_Data_Package => ([\w|\.]*)( *)\);/--HOST_TEST_BEGIN\n$1g_Data_Package => $2\_Original$3\);\n--HOST_TEST_END/;

			$content =~ s/package (.*) is new Generic_Operator(.*)/--HOST_TEST_BEGIN\npackage $1 renames Manager\.$new_package_name;\n--package $1 is new Generic_Operator$2/;

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
	}
	
	return ($counters[0], $counters[1], $counters[2]);
}

# ****************************
# insertElab
# ****************************
sub insertElab {

	my $result = 0;
	my %sources;
	scandirs("n:/Source", "", \%sources);

	foreach my $key (keys %sources) {

		my $filename = $sources{$key}[0]{"abs"} . "/" . convertKeyToFileName($key, "source");

		if (getType($key, "source") eq "body") {

			(my $content, my @lines) = readFile($filename);
            
            if ($content =~ m/g_CTD_Reference/ and $content !~ m/procedure Elab is/) {

            	$result += 1;

                $content =~ m/package body (.*) is/;
                my $package = $1;
    
                open FH, ">$filename" or die "error";
                
                my $count = 0;
                my $index = $#lines-2;
                while ($index > 0 and $count != -1) {
                
                    if ($lines[$index] =~ m/begin\n/) {
                        $count -= 1;
                    }
                    if ($lines[$index] =~ m/end\s?(.*);/) {
                        my $str = quotemeta($1);
                        if ($content =~ m/(procedure|function|package)\s*$str/i) {
                            $count += 1;
                        }
                    }
                    $index -= 1;
                }
                
                if ($index+1 > 0) {
                    $lines[$index+1] =~ s/\s*begin/-- HOST_TEST_BEGIN\nprocedure Elab is\nbegin\n-- HOST_TEST_END/;
                }
                
                foreach my $line (@lines) {
                    $line =~ s/end $package;/\n-- HOST_TEST_BEGIN\nend Elab;\n-- HOST_TEST_END\n\nend $package;/i;
                    print FH $line;
                }
    
                close FH;
            
            }

		}

	}

	return $result;

}

# ****************************
# compile_routine
#	$_[0] : gpr file
# ****************************
sub compile_routine {

	my $dir;
	if ($_[0] eq "n:/GNAT/U500.gpr") {
		$dir = "n:/Additional_Files";
	}
	else {
		$dir = "n:/Stubs";
	}

	# my $file;
	# my $exit = 0;
	my $status = 0;
	my $workdir = $settings{"work_dir"};

	$settings{"is_running"} = 1;
	# TDOD 1.3.0 check GNAT's location
	system("\"c:\\GNAT\\2013\\bin\\gprbuild.exe\" -q -d $_[0] 1>$workdir/stat 2>$workdir/error");
	$settings{"is_running"} = 0;

	my @errors = readerror();

	if ($errors[$#errors] !~ m/failed/) {
		$status = 2;
		system("cls");
		print "\n-----------------------";
		print "\n| compilation is done |";
		print "\n-----------------------\n";
	}

	if ($status == 0) {
		$status = error_handler(\@errors, $dir);
	}

	if ($status == 0) {
		printerror();
		# copyDiff("n:/temp/", "n:/Source/", "spec", 1);
	}

	if ($status != 2) {
		compile_routine($_[0]);
	}
}

sub processConfigurationFile {

	(my $temp, my @lines) = readFile("config.txt");
	
	my @values;
	foreach my $line (@lines) {
		if ($line =~ m/<(.*)>/) {
			push(@values, $1);
		}
	}

	$settings{"stub_mode"} = $values[0];
	$settings{"build_mode"} = $values[1];
	$settings{"purpose"} = $values[2];
	$settings{"source_spec_ext"} = "." . $values[3];
	$settings{"source_body_ext"} = "." . $values[4];
	$settings{"source_dot_repl"} = $values[5];

	if (substr($values[6], -1, 1) eq "\\" or substr($values[6], -1, 1) eq "/") {
		$values[6] = substr($values[6], 0, -1);
	}
	$values[6] =~ s/\\/\//g;
	$settings{"clearcase_path"} = $values[6];
	$settings{"exceptions_file"} = $values[7];

}

sub init {

	processConfigurationFile();
	
	my $gprbuildFile = 
	
"project U500 is

   for Source_Dirs use (\".\", \"..\\Source\\**\", \"..\\Additional_Files\\**\");
   for Object_Dir use \"Build\";

   package Compiler is
	  for Default_Switches (\"ada\") use (\"-w\", \"-gnat95\");
   end Compiler;

   package Naming is
	  for Spec_Suffix (\"ada\") use \"" . $settings{"source_spec_ext"} .  "\";
	  for Body_Suffix (\"ada\") use \"" . $settings{"source_body_ext"} .  "\";
	  for Separate_Suffix use \"" . $settings{"source_body_ext"} . "\";
	  for Casing use \"MixedCase\";
	  for Dot_Replacement use \"" . $settings{"source_dot_repl"} . "\";
   end Naming;

end U500;";
	
	open GPRFILE, ">n:/GNAT/U500.gpr";
	print GPRFILE $gprbuildFile;
	close GPRFILE;
	
	$settings{"source_casing"} = "MixedCase";
	
	$settings{"stub_spec_ext"} = ".ads";
	$settings{"stub_body_ext"} = ".adb";
	$settings{"stub_dot_repl"} = "-";
	$settings{"stub_casing"} = "lowercase";

	$settings{"work_dir"} = cwd();
	$settings{"debug_mode_on"} = 0;
	$settings{"progress_text_1"} = "Source compilation in progress";
	$settings{"progress_text_2"} = "Generating bodies for stubs";
	$settings{"progress_text_3"} = "Stub compilation in progress";
	$settings{"is_running"} = 0;
	$settings{"progress_bar_value"} = 0;
	$settings{"build_phase"} = 0;
	
	$locations{"n:/Additional_Files"} = "source";
	$locations{"n:/Source"} = "source";
	$locations{"n:/Stubs"} = "stub";
    
   	my $workdir = $settings{"work_dir"};

	# clean stat
	open STAT, ">$workdir/stat";
	close STAT;

	# open log files
	open LOG, ">$workdir/log";

	# maybe someday..
    # open PACKAGELIST, ">$workdir/packageslist";

}


# ****************************
# MAIN
# ****************************

sub main {

	system("cls");
	print "Environment Creator 1.x.x\n\n";

	init();

	# read available sources from clearcase
	print "Reading ClearCase directory... ";
	scandirs($settings{"clearcase_path"}, "", \%availableAdditinalSources);
	print "Done.\n";
	
	readExceptions();

	# copy sources to compile
	print "Copying sources... ";
	if ($settings{"build_mode"} eq "new") {
        # copy all ada files
		# TODO 1.3.0 check for multiple files
		copydir("n:/temp", "n:/Source", "all", 0, "source", "source");
	}
	else {
        # replace the old ones with the newer ones
		print "copyDiff";
		# TODO 1.3.0 rewrite it
		# copyDiff("n:/temp/", "n:/Source/", "all", 0);
	}
	print "Done.\n";

	my %prevAddedSourceFiles;
	scandirs("n:/Source", "", \%prevAddedSourceFiles);
	foreach my $key (keys %prevAddedSourceFiles) {
		if (not $fileList{"source"}{$key}) {
			$fileList{"source"}{$key} = $prevAddedSourceFiles{$key}[0];
		}
	}

	my %prevAddedAdditionalFiles;
	scandirs("n:/Additional_Files", "", \%prevAddedAdditionalFiles);
	foreach my $key (keys %prevAddedAdditionalFiles) {
		if (not $fileList{"source"}{$key}) {
			$fileList{"source"}{$key} = $prevAddedAdditionalFiles{$key}[0];
			$fileList{"additional"}{$key} = $prevAddedAdditionalFiles{$key}[0];
		}
	}
	
	# TODO 1.3.0 insert elab SCV / MT
	print "Modifying sources... ";
	my $number_of_emcs = insertElab();
	print "Done. ($number_of_emcs)\n";
	
	# copy all ads to stubs
	copydir("n:/Source", "n:/Stubs", "spec", 1, "source", "stub");
	copydir("n:/Additional_Files", "n:/Stubs", "all", 1, "source", "stub");

	# check for dependencies
	print "Gathering additional packages\n";
	# my @temporalListOfSources = @g_unmodified_sources;
	foreach my $source (keys %{$fileList{"source"}}) {
		gatherPackages(convertKeyToFileName($source, "source"));
	}

	print "Updating database\n";
	updateDatabase();
	openDatabase();

	my %list = %{$fileList{"source"}};
	foreach my $source (keys %list) {

		my $regExp = $settings{"source_body_ext"};
		if ($source =~ m/$regExp/) {
            
			my @subunits = getSubunits(getPackageName($source, "source"));
			foreach my $s (@subunits) {
				# my $fileToAdd = convertKeyToFileName($s, "body", "source");
                if (not $fileList{"source"}{lc $s . ".body"}) {
                    addFile($s, "n:/Additional_Files", 0);
                }
			}
		}
	}

	$settings{"build_phase"} = 1;
	print "Starting compile routine for sources\n";
	compile_routine("n:/GNAT/U500.gpr");

	# -------------------------------------------

	print "Generating instances... ";
	(my $dataTypeCount, my $portTypeCount, my $genericOperatorCount) = createInstances();
	print "Done. (DT: $dataTypeCount; PT: $portTypeCount; GO: $genericOperatorCount)\n";

	# # $mode = 0;
	
	# # TODO do it automatically 1.3.0
	print "Copy custom modifications to the stubs folder! Press ENTER when done"; <STDIN>;

	$settings{"build_phase"} = 2;
	print "Generating bodies for stubs\n";
	generateStubBodies();

	$settings{"build_phase"} = 3;
	$settings{"progress_bar_value"} = 0;
	
	print "\n\nStarting compile routine for stubs\n";
	compile_routine("n:/GNAT/U500Stub.gpr");

	system("cls");
	print "\n-------------------------------------------------------";
	print "\n| your test environment has been successfully created |";
	print "\n-------------------------------------------------------\n";

	$settings{"build_phase"} = 4;

	close LOG;
}

my $thr = threads->create('showProgress');
main();
$thr->join();