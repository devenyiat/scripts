use Cwd;
use File::Copy;
use File::Path;
use Understand;

$workdir = getcwd();

@temp;
sub scan {
	@temp = ();
	scandirs($_[0]);
	chdir($workdir);
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
				push(@temp, $string);
			}
		}
		if (-d $file) {
			scandirs($dir, $file);
		}
	}
}

sub dottohyphen {
	my $result = $_[0];
	$result =~ tr/./-/;
	$result = lc $result;
	return $result;
}

sub ptuname {
	# $temp = $package;
	# $temp =~ tr/./_/;
	$result = "$test_type\_" . $packageu;
	return $result;
}

sub header {
	$result = ptuname();
	$result =~ m/$test_type\_(.*)/;
	$result = $1;
	return $result;
}

sub sourcestotest {

	$result = "";
	# @s = $p[0]->refs("Ada Declare Stub");

	# my @files_to_copy = ();

	# $result = "COMMENT ****      - " . lc dottohyphen($p[0]->longname()) . ".ads";
	# $result = $result . "\nCOMMENT ****      - " . lc dottohyphen($p[0]->longname()) . ".adb";

	# foreach (@s) {
	# 	$result = $result . "\nCOMMENT ****      - " . lc dottohyphen($package) . "-" . $_->ent()->name() . ".adb";
	# }

	# $result = $result . "\nCOMMENT ****";

	foreach $file (@files_to_copy) {
		$result = $result . "COMMENT ****      - " . $file . "\n";
	}
	$result = $result . "COMMENT ****";

	return $result;
}

sub withs {
	@ withs = ();
	$result = "";
	foreach $act_p (@packages) {
		@p = $db->lookup($act_p, "Ada Package");
		@w = $p[0]->ents("Ada With Body, Ada With Spec");
		foreach (@w) {
			if (not $_->longname() ~~ @withs) {
				push(@withs, $_->longname());
			}
		}
	}
	foreach (@withs) {
		$result = $result . "# with " . $_ . ";\n";
	}
	if (not $packages[0] ~~ @withs) {
		$result = $result . "# with $packages[0];\n# with Rtrt_Test_Package;";
	}
	return $result;
}

sub rec_func {
	@cfs = $_[0]->ent->refs("Ada Call");
	foreach $cf (@cfs) {
		$called_package = $cf->ent->parent->longname();
		if ($called_package ~~ @packages and $called_package ne $packages[0]) {
			return 1;
		}
		else {
			if ($called_package eq $packages[0]) {
				return rec_func($cf);
			}
		}
	}
	return 0;
}

sub subprogram_entities {
	@result = ();
	@p = $db->lookup($packages[0], "Ada Package");
	if ($test_type eq "MT"){
		@s = $p[0]->ents("Ada Declare", "Ada Procedure, Ada Function");
		@result = @s;
	}
	else {
		@s = $p[0]->ents("Ada Declare Spec", "Ada Procedure -Local, Ada Function -Local");
		MAIN_FOR: {
			foreach $s (@s) {
				@called_functions = $s->refs("Ada Call");
				foreach $cf (@called_functions) {
					$called_package = $cf->ent->parent->longname();
					if ($called_package ~~ @packages and $called_package ne $packages[0]) {
						push(@result, $s);
						last MAIN_FOR;
					}
					if (rec_func($cf) == 1) {
						push(@result, $s);
						last MAIN_FOR;
					}
				}
			}
		}
	}
	return @result;
}

sub getStubs {
	@stubs = ();
	$result = "\n";
	@called_functions = $_[0]->refs("Ada Call");
	foreach $cf (@called_functions) {
		$called_package = $cf->ent->parent->longname();
		if (not $called_package ~~ @packages) {
			push(@stubs, $cf);
		}
		# else {
		# 	push(@result, getStubs($cf->ent));
		# }
	}
	foreach $s (@stubs) {
		$result = $result . "                -- STUB " . signature($s->ent) . "\n\n";
	}

	return $result;
}

sub getGlobals  {
	@globals = ();
	@globals = $_[0]->ents("Ada Use", "Ada Object");
	$result = "";
	foreach $g (@globals) {
		if ($g->name() =~ m/g_/) {
			$g->type() =~ m/(in )?(out )?(.*)/;
			$type = $3;
			if ($type =~ /(.*)( :=)/){
				$type = $1;
			}
			$result = $result . "\n                -- VAR " . $g->name() . ",\n                -- & init = " .
			$type . "\'First,\n                -- & ev ==\n";

		}
	}
	return $result;
}

sub subprograms {
	@subs = subprogram_entities();
	$result = "COMMENT ****";
	foreach $s (@subs) {
		$result = $result . "\nCOMMENT ****         " . uc $s->name();
	}
	return $result;
}

sub parameters {

	@params = $_[0]->ents("Ada Declare", "Ada Parameter");

	$result = "";

	foreach $param (@params) {
		$param->type() =~ m/(in )?(out )?(.*)/;
		$type = $3;
		$result = $result . "        # " . $param->name() . " : " . $type . ";\n";
	}

	return $result;
}

sub parameters_to_test {
	@params = $_[0]->ents("Ada Declare", "Ada Parameter");

	$result = "";

	foreach $param (@params) {
		$param->type() =~ m/(in )?(out )?(.*)/;
		$type = $3;
		if ($type =~ /(.*)( :=)/){
			$type = $1;
		}
		$result = $result . "\n                -- VAR " . $param->name() . ",\n                -- & init = " .
		$type . "\'First,\n                -- & ev ==\n";
	}

	if (@params == ()) {
		$result = "                COMMENT None\n";
	}

	return $result;
}

sub returnvar {
	$result = "";
	if ($_[0]->type() ne "") {		
		$result = "        # Ret_" . $_[0]->name() . " : " . $_[0]->type() . ";\n";
	}
}

sub returnvar_to_test {
	$result = "";
	if ($_[0]->type() ne "") {		
		$result = "\n                -- VAR " . $_[0]->name() . ",\n                -- & init =,\n                -- & ev =\n";
	}
	else {
		$result = "                COMMENT None\n";
	}
}

sub functioncall {
	$result = "        # ";
	if ($_[0]->type() ne "") {		
		$result = $result . "Ret_" . $_[0]->name() . " := ";
	}
	$result = $result . $_[0]->longname();
	@params = $_[0]->ents("Ada Declare", "Ada Parameter");
	if (@params != ()) {
		$result = $result . "( ";
	}
	foreach $param (@params) {
		$param->type() =~ m/(in )?(out )?(.*)/;
		$type = $3;
		$result = $result . $param->name() . ", ";
	}
	if ($result !~ s/, $/ );/) {
		$result = $result . ";"
	}
	return $result;
}

sub signature {
	$result = $_[0]->longname() . "( " . $_[0]->parameters() . " )";
	if ($_[0]->type() ne "") {		
		$result = $result . " return " . $_[0]->type();
	}
	return $result; 
}

sub ptumaker {
	open FH, "<$workdir/minta.ptu" or die "error";
	@lines = <FH>;
	close FH;

	@part_one = ();
	@part_two = ();
	@final = ();

	$idx = -1;
	do {
		$idx++;
		push(@part_one, $lines[$idx]);
	} while ($lines[$idx] !~ m/-- Declaration of stubbed packages/);
	$idx = $idx + 2;

	while ($idx <= $#lines) {
		push(@part_two, $lines[$idx]);
		$idx++;
	}

	$componentname = "";
	if ($test_type eq "MT") {
		$componentname = $packages[0];
	}
	else {
		$componentname = $itp_number;
	}
	$ptuname = ptuname();
	$header = header();
	$sourcestotest = sourcestotest();
	$subprograms = subprograms();
	$withs = withs();
	foreach $line (@part_one) {
		$line =~ s/COMMENT \*\*\*\*  PTUNAME.ptu/COMMENT \*\*\*\*  $ptuname.ptu/;
		$line =~ s/COMMENT \*\*\*\*      - SOURCES_TO_TEST/$sourcestotest/;
		$line =~ s/COMMENT \*\*\*\*         SUBPROGRAMS/$subprograms/;
		$line =~ s/HEADER PTUNAME, ,/HEADER $header, ,/;
		$line =~ s/COMPONENTNAME/$componentname/;
		if ($test_type eq "MT") {
			$line =~ s/BEGIN PACKAGENAME, Attol_Test/BEGIN $packages[0], Attol_Test/;
		}
		else {
			$line =~ s/BEGIN PACKAGENAME, Attol_Test/BEGIN/;
		}
		$line =~ s/WITH PART/$withs/;
		$line =~ s/MONOGRAM/$initials/;
		$line =~ s/PRODDATE/$date/;
		$line =~ s/RELEASE/$release/;
		$line =~ s/VERSION/$environmentversion/;
	}

	push(@final, @part_one);

	# foreach $sub ($p[0]->ents("Ada Declare", "Ada Procedure ~Local, Ada Function ~Local")) {
	@p = $db->lookup($packages[0], "Ada Package");
	# foreach $sub ($p[0]->ents("Ada Declare", "Ada Procedure, Ada Function")) {
	foreach $sub (subprogram_entities()) {
		@act = @part_two;
		$name = uc $sub->name();
		$fullname = $sub->longname();
		$parameters = parameters($sub);
		$return = returnvar($sub);
		$functioncall = functioncall($sub);
		$signature = signature($sub);
		$var_signs = parameters_to_test($sub);
		$var_ret = returnvar_to_test($sub);
		$var_globals = getGlobals($sub);
		$stubs = getStubs($sub);
		foreach $line (@act) {
			$line =~ s/SUBPROGRAM1/$name/;
			$line =~ s/SUBPROGRAMFULL1/$fullname/;
			$line =~ s/        SIGNATURE VARIABLES/$parameters/;
			$line =~ s/        RETURN VARIABLE/$return/;
			$line =~ s/        FUNCTION CALL/$functioncall/;
			$line =~ s/SIGNATURE/$signature/;
			$line =~ s/MONOGRAM/$initials/;
			$line =~ s/PRODDATE/$date/;
			$line =~ s/RELEASE/$release/;
			$line =~ s/                VAR_SIGNS/$var_signs/;
			$line =~ s/                VAR_RET/$var_ret/;
			$line =~ s/                VAR_GLOB/$var_globals/;
			$line =~ s/                STUBS/$stubs/;

		}
		push(@final, @act);

		getGlobals($sub);
	}

	open FH, ">t:/Test_Environments/$test_type\_$packageu/$test_type\_$packageu.ptu";
	print FH @final;
	close FH;

}

sub rtpmaker {
	$id = 434727470;

	open FH, "<$workdir/minta.rtp" or die "error";
	@lines = <FH>;
	close FH;

	@part_one = ();
	@part_two = ();
	@part_three = ();
	@final = ();

	$idx = -1;
	do {
		$idx++;
		push(@part_one, $lines[$idx]);
	} while ($lines[$idx] !~ m/<test_child>/);
	do {
		$idx++;
		push(@part_two, $lines[$idx]);
	} while ($lines[$idx] !~ m/<\/source>/);
	do {
		$idx++;
		push(@part_three, $lines[$idx]);
	} while ($idx < $#lines);

	$name = ptuname();
	foreach $line (@part_one) {
		$line =~ s/NAME/$name/;
		$line =~ s/LOCATION/t:\\Test_Environments\\$test_type\_$packageu\\/;
	}
	push(@final, @part_one);

	print @files_to_copy;

	foreach $file (@files_to_copy) {
		print $file;
		@act = @part_two;
		foreach $line (@act) {
			$line =~ s/SOURCE/$file/;
			$line =~ s/QUID/$id/;
			if ($file =~ m/ads/) {
				$line =~ s/INTEGRATED/true/;
			}
			else {
				$line =~ s/INTEGRATED/false/;
			}
			
		}
		$id++;
		push(@final, @act);
	}

	foreach $line (@part_three) {
		$line =~ s/NAME/$name/;
	}
	push(@final, @part_three);

	open FH, ">t:/Test_Environments/$test_type\_$packageu/$test_type\_$packageu.rtp";
	print FH @final;
	close FH;
	
}

sub modify_source {

	$package = $p[0]->longname();

	open FH, "<t:/Test_Environments/$test_type\_$packageu/Source/" . dottohyphen($package) . ".ads" or die "error";
	@lines = <FH>;
	close FH;

	$content = "";
	foreach $l (@lines) {
		$content = $content . $l;
	}

	open FH, ">t:/Test_Environments/$test_type\_$packageu/Source/" . dottohyphen($package) . ".ads" or die "error";

	# if ($content =~ m/g_CTD_Reference/) {
	# 	$content =~ s/end $package/--HOST_TEST_BEGIN\n   procedure Elab;\n   procedure Attol_Test;\n--HOST_TEST_END\n\nend $package/i;
	# }
	# else {
		$content =~ s/end $package/--HOST_TEST_BEGIN\n   procedure Attol_Test;\n--HOST_TEST_END\n\nend $package/i;
	# }


	print FH $content;

	close FH;

	open FH, "<t:/Test_Environments/$test_type\_$packageu/Source/" . dottohyphen($package) . ".adb" or die "error";
	@lines = <FH>;
	close FH;

	$content = "";
	foreach $l (@lines) {
		$content = $content . $l;
	}

	open FH, ">t:/Test_Environments/$test_type\_$packageu/Source/" . dottohyphen($package) . ".adb" or die "error";

	# if ($content =~ m/g_CTD_Reference/) {
	# 	$content =~ s/\nbegin/\n--HOST_TEST_BEGIN\nprocedure Elab is\nbegin\n--HOST_TEST_END/s;
	# 	$content =~ s/end $package/\n--HOST_TEST_BEGIN\nend Elab;\n\n\n   procedure Attol_Test is separate;\n--HOST_TEST_END\n\nend $package/i;
	# }
	# else {
		$content =~ s/end $package/\n--HOST_TEST_BEGIN\n   procedure Attol_Test is separate;\n--HOST_TEST_END\n\nend $package/i;
	# }

	print FH $content;

	close FH;

}

open FH, "<environment.cfg";
@lines = <FH>;
close FH;

$lines[0] =~ m/TEST_TYPE:\s*(.*)/;
$test_type = $1;
$lines[1] =~ m/ITP:\s*(.*)/;
$itp_number = $1;

$temporary_line = $lines[2];
$number_of_packages = 0;
while ($temporary_line =~ m/MODULES_TO_TEST:\s*(.*?),(.*)/) {
	@packages[$number_of_packages] = $1;
	$number_of_packages++;
	$temporary_line = "MODULES_TO_TEST:$2";
}
$temporary_line =~ m/MODULES_TO_TEST:\s*(.*)/;
@packages[$number_of_packages] = $1;
$number_of_packages++;

$packageu = "";
if ($test_type eq "MT") {
	$packageu = $packages[0];
	$packageu =~ tr/./_/;
}
else {
	$packageu = $itp_number;
}

$lines[3] =~ m/INITIALS:\s*(.*)/;
$initials = $1;
$lines[4] =~ m/DATE:\s(.*)/;
$date = $1;
$lines[5] =~ m/RELEASE:\s(.*)/;
$release = $1;
$lines[6] =~ m/ENVIRONMENT:\s(.*)/;
$environmentversion = $1;

mkpath("t:/Test_Environments/$test_type\_$packageu/Source/");
mkpath("t:/Test_Environments/$test_type\_$packageu/$test_type\_$packageu/");

system("und -db t:/U500.udb analyze -rescan");

$db = Understand::open("T:/U500.udb");

@files_to_copy = ();

foreach $package (@packages) {

	print $package;

	@p = $db->lookup($package, "Ada Package");
	@s = $p[0]->refs("Ada Declare Stub");

	push(@files_to_copy, lc dottohyphen($p[0]->longname()) . ".ads");
	push(@files_to_copy, lc dottohyphen($p[0]->longname()) . ".adb");

	foreach (@s) {
		$temp = lc dottohyphen($package) . "-" . $_->ent()->name() . ".adb";
		push(@files_to_copy, $temp);
	}

}

%filesloc;

scan("t:/Source/");
foreach $f (@files_to_copy) {
	$idx = 0;
	while ($temp[$idx] !~ m/$f/ and $idx <= $#temp) {
		$idx++;
	}
	print $temp[$idx]. "\n";
	$temp[$idx] =~ m/#dir: (.*)\/\/(.*) #file: (.*)/;
	print "$1/$2$f". "\n";
	copy("$1/$2$f", "t:/Test_Environments/$test_type\_$packageu/Source/$f");
	$loc = "$1/$2";
	$loc =~ tr/\//\\/;
	$filesloc{$f} = $loc;
}

system("\"c:/Program Files/Rational/TestRealTime/bin/intel/win32/attolalk.exe\" t:/Test_Environments/$test_type\_$packageu/$test_type\_$packageu.alk t:/Stubs");

open FH, "<t:/Test_Environments/$test_type\_$packageu/$test_type\_$packageu.alk";
@lines = <FH>;
close FH;

open FH, ">t:/Test_Environments/$test_type\_$packageu/$test_type\_$packageu.alk";

@mod = ();
foreach $l (@lines) {
	foreach $f (@files_to_copy) {
		if ($l =~ m/$f/) {
			$temp = $l;
			$loc = $filesloc{$f};
			$temp =~ s/t:\\Stubs\\/t:\\Test_Environments\\$test_type\_$packageu\\Source\\/;
			push(@mod, $temp);
			$l =~ s/(.*)/--$1/;
			last;
		}
	}
	print FH $l;
}

print FH "\n\n";
print FH @mod;

close FH;

ptumaker();

rtpmaker();

if ($test_type eq "MT") {
	modify_source();
}