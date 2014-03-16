use Cwd;
use File::Copy;
use File::Path;
use Understand;

$workdir = getcwd();

@temp;
@g_exceptions = ();
@definestubs = ();

sub readExceptions {
	open FH, "<$workdir/exceptions.cfg";
	@exs = <FH>;
	close FH;

	foreach $ex (@exs) {
		$ex =~ m/(.*)\n/;
		push(@g_exceptions, $1);
	}
}

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
	@p = $db->lookup($packages[0], "Ada Package");
	$result = $p[0]->longname();
	# $result =~ m/$test_type\_(.*)/;
	# $result = $1;
	return $result;
}

# @param1: reference of string to be written
# @param2: level
sub printIndentation {
	 my $reference = $_[0];
	 my $tabulation = $_[1];

	 $$reference = $$reference . "                -- &";

	 for (my $i = 0; $i < $tabulation; $i++) {
	 	$$reference = $$reference . "    ";
	 }
}

# param1: reference of string to be written
# param2: string to be added
sub addString {
	my $reference = $_[0];
	my $string = $_[1];

	$$reference = $$reference . $string;
}

# @param1: reference of string to be written
# @param2: understand entity
# @param3: level
# @param4: current type
sub getSubItems {
	my $reference = $_[0];
	my $entity = $_[1];

	if ($debug == 1) {
		print $entity->name() . "\n";
		print $entity->kindname() . "\n";
	}

	# if we have scalar type
	if ($entity->kindname() =~ /^(Limited )?(Private )?Type$/) {
		addString($reference, " " . $entity->longname() . "'First");
	}

	# if we have enum type
	if ($entity->kindname() =~ /Type Enumeration/) {
		addString($reference, " " . $entity->longname() . "'First");
	}

	# if we have access type
	if ($entity->kindname() =~ /Type Access/) {
		addString($reference, " null");
	}

	# if we have array type
	if ($entity->kindname() =~ /Type Array/) {
		if ($_[3] ne "array") {
			addString($reference, " (\n");
			printIndentation($reference, $_[2]+1);
			addString($reference, "others =>");
		}
		if ($entity->ref("Ada Typed") eq "") {
			getSubItems($reference, $entity->ref("Ada Derivefrom")->ent, $_[2], "array");
		}
		else {
			my $element = $entity->ref("Ada Typed")->ent;
			# check array elemets
			getSubItems($reference, $element, $_[2]+1, "array");
		}
		if ($_[3] ne "array") {
			addString($reference, " )");
		}
	}

	# if we have record type
	if ($entity->kindname() =~ /Type Record/) {
		if ($_[3] ne "record") {
			addString($reference, " (");
		}
		# get record elements
		my @components = $entity->ents("Ada Declare", "Ada Component");
		if (@components == ()) {
			getSubItems($reference, $entity->ref("Ada Typed")->ent, $_[2], "record");
		}
		else {
			foreach my $comp (@components) {
				# if prev line has ended with ( no need for ,
				if (substr($$reference,-1,1) eq "(") {
					addString($reference, "\n");
				}
				else {
					addString($reference, ",\n");
				}
				printIndentation($reference, $_[2]+1);
				addString($reference, $comp->name() . " =>");
				# check record element
				getSubItems($reference, $comp->ref("Ada Typed")->ent, $_[2]+1, "record");
			}
		}
		if ($_[3] ne "record") {
			addString($reference, " )");
		}
	}

	# if we have abstract type
	if ($entity->kindname() =~ /Abstract Type/) {
		if ($_[3] ne "abstract") {
			addString($reference, "(");
		}
		# check ancient type
		if ($entity->ref("Ada Derivefrom") != "") {
			getSubItems($reference, $entity->ref("Ada Derivefrom")->ent, $_[2], "abstract");
		}

		# get record elements
		my @components = $entity->ents("Ada Declare", "Ada Component");
		foreach my $comp (@components) {
			# if prev line has ended with ( no need for ,
			if (substr($$reference,-1,1) eq "(") {
				addString($reference, "\n");
			}
			else {
				addString($reference, ",\n");
			}
			printIndentation($reference, $_[2]+1);
			addString($reference, $comp->name() . " =>");
			# check record element
			getSubItems($reference, $comp->ref("Ada Typed")->ent, $_[2]+1, "record");
		}
		# close opening (
		if ($_[3] ne "abstract") {
			addString($reference, " )");
		}
	}
}

sub sourcestotest {

	$result = "";

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
		@s = $p[0]->ents("Ada Declare Spec", "Ada Procedure ~Local, Ada Function ~Local");
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

sub getStubs_rec {
	my @result = ();
	my @called_functions = $_[0]->refs("Ada Call ~Access");
	foreach $cf (@called_functions) {
		$called_package = $cf->ent->parent->longname();
		if (not $called_package ~~ @packages and not $called_package ~~ @g_exceptions) {
			push(@result, $cf);
			if (not $called_package ~~ @definestubs) {
				push(@definestubs, $called_package);
			}
		}
		else {
			push(@result, getStubs_rec($cf->ent));
		}
	}
	return @result;
}

sub getUniqueStubs {
	@result = ();
	@stubs = ();
	@stubs = getStubs_rec($_[0]);
	my @uniqueStubs = ();
	foreach $s (@stubs) {
		if (not $s->ent->longname() ~~ @uniqueStubs) {
			push(@uniqueStubs, $s->ent->longname());
			push(@result, $s);
		}
	}
	return @result;
}

sub getStubVariableName {
	my $stub = $_[0];
	my $result = ();

	if ($stub->kindname() =~ /(Private )?Function/) {
		$result = "Stub_" . $stub->name();
	}
	else {
		$result = "Stub_" . $stub->ref("Ada Declarein")->ent->name() . "_" . $stub->name();
	}

	return $result;
}

sub getStubs {

	$result = "";
	$reference = $_[1];
	my @uniqueStubs = getUniqueStubs($_[0]);
	foreach $s (@uniqueStubs) {
		$result = $result . "\n                -- STUB " . $s->ent->longname() . " (";
		@params = $s->ent->ents("Ada Declare", "Ada Parameter");
		foreach $p (@params) {
			$result = $result . "\n                -- &   " . $p->name() . " => ";
			if ($p->type() =~ /in out /) {
				$result = $result . "(in => , out => " . getStubVariableName($p) . "),";
				push(@$reference, $p);
			}
			else {
				if ($p->type() =~ /out /) {
					$result = $result . "(out => " . getStubVariableName($p) . "),";
					push(@$reference, $p);
				}
				else {
					$result = $result . "(in => ),";
				}
			}
		}
		$result =~ s/(.*),/$1\)/s;
		if ($s->ent->type() ne "") {
			$result = $result . " Stub_" . $s->ent->name();
			push(@$reference, $s->ent);
		}
		$result = $result . "\n";
	}
	return $result;
}

sub generateStubDeclaration {
	$result = "";
	$reference = $_[0];

	foreach my $stub (@$reference) {
		addString(\$result, "        # " . getStubVariableName($stub) . " : " . $stub->ref("Ada Typed")->ent->longname() . ";\n");
	}

	return $result;
}

# @param1 : reference of out parameter entities
sub setStubVars {
	my $reference = $_[0];
	$result = "";
	foreach my $param (@$reference) {
		my $typeEnt = $param->ref("Ada Typed")->ent;
		my $keyword = getKeyWord($typeEnt);
		addString(\$result, "\n                -- $keyword " . getStubVariableName($param) . ",\n                -- & init =");
		getSubItems(\$result, $typeEnt, 0, "root");
		addString(\$result, ",\n                -- & ev ==\n");
	}

	if (@params == ()) {
		$result = "                COMMENT None\n";
	}

	return $result;
}

sub getDefineSection {

	$result = "";

	foreach $d (@definestubs) {
		$result = $result . "\nDEFINE STUB $d\nEND DEFINE\n";
	}

	return $result;
}

sub getKeyWord {
	$typeEnt = $_[0];
	my $result;

	if ($typeEnt->kindname() =~ /(Limited )?(Private )?Abstract Type/ or $typeEnt->kindname() =~ /(Limited )?(Private )?Type Record/) {
		$result = "STR";
	}
	else {
		if ($typeEnt->kindname() =~ /(Limited )?(Private )?Type Array/) {
			$result = "ARRAY";
		}
		else {
			$result = "VAR";
		}
	}

	return $result;
}

sub setGlobals  {
	@globals = ();
	@globals = $_[0]->ents("Ada Use", "Ada Object");
	$result = "";
	foreach $g (@globals) {
		if ($g->name() =~ m/^g_/i) {
			my $typeEnt = $g->ref("Ada Typed")->ent;
			my $keyword = getKeyWord($typeEnt);
			
			addString(\$result, "\n                -- $keyword " . $g->name() . ",\n                -- & init =");
			getSubItems(\$result, $g->ref("Ada Typed")->ent, 0, "root");
			addString(\$result, ",\n                -- & ev = init\n");

		}
	}

	if ($result eq "") {
		$result = "                COMMENT None\n";
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

sub setSignVars {
	@params = $_[0]->ents("Ada Declare", "Ada Parameter");

	$result = "";

	foreach $param (@params) {
		$param->type() =~ m/(in )?(out )?(.*)/;
		$mode = $1 . $2;
		$typeEnt = $param->ref("Ada Typed")->ent;
		$keyword = getKeyWord($typeEnt);
		if ($mode eq "in ") {
			# print "IN\n";
			# print $param->ref("Ada Typed")->ent->name() . "\n";
			addString(\$result, "\n                -- $keyword " . $param->name() . ",\n                -- & init =");
			getSubItems(\$result, $typeEnt, 0, "root");
			addString(\$result, ",\n                -- & ev ==\n");
		}
		if ($mode eq "out ") {
			# print "OUT\n";
			addString(\$result, "\n                -- $keyword " . $param->name() . ",\n                -- & init ==");
			addString(\$result, ",\n                -- & ev = ");
			getSubItems(\$result, $typeEnt, 0, "root");
		}
		if ($mode eq "in out ") {
			# print "INOUT\n";
			addString(\$result, "\n                -- $keyword " . $param->name() . ",\n                -- & init =");
			getSubItems(\$result, $typeEnt, 0, "root");
			addString(\$result, ",\n                -- & ev = \n");
		}
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
	return $result;
}

sub setRetVar {
	$result = "";
	if ($_[0]->type() ne "") {		
		$result = "\n                -- VAR Ret_" . $_[0]->name() . ",\n                -- & init =";
		getSubItems(\$result, $_[0]->ref("Ada Typed")->ent, 0, "root");
		addString(\$result, ",\n                -- & ev =\n");
	}
	else {
		$result = "                COMMENT None\n";
	}
	return $result;
}

# sub declareStubVars {
# 	$result = "";
# 	my @uniqueStubs = getUniqueStubs($_[0]);
# 	if (@uniqueStubs != ()) {
# 		foreach $us (@uniqueStubs) {
# 			$result = $result . "        # Stub_" . $us->ent->name() . " : " . $us->ent->type() . ";\n";
# 		}		
# 	}
# 	else {
# 		$result = "                COMMENT None\n";
# 	}
# 	print $result; <STDIN>;
# 	return $result;
# }

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
	} while ($lines[$idx] !~ m/DEFINESTUBS/);
	$idx = $idx + 1;

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
			$line =~ s/BEGIN PACKAGENAME, Attol_Test/BEGIN $header, Attol_Test/;
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
		$var_signs = setSignVars($sub);
		$var_ret = setRetVar($sub);
		$var_globals = setGlobals($sub);
		@stubVariables = ();
		$stubs_str = getStubs($sub, \@stubVariables);
		$stubVariablesStr = generateStubDeclaration(\@stubVariables);
		$stubVarsSetter = setStubVars(\@stubVariables);
		foreach $line (@act) {
			$line =~ s/SUBPROGRAM1/$name/;
			$line =~ s/SUBPROGRAMFULL1/$fullname/;
			$line =~ s/        SIGNATURE VARIABLES/$parameters/;
			$line =~ s/        RETURN VARIABLE/$return/;
			$line =~ s/        STUB VARIABLES/$stubVariablesStr/;
			$line =~ s/        FUNCTION CALL/$functioncall/;
			$line =~ s/SIGNATURE/$signature/;
			$line =~ s/MONOGRAM/$initials/;
			$line =~ s/PRODDATE/$date/;
			$line =~ s/RELEASE/$release/;
			$line =~ s/                VAR_SIGNS/$var_signs/;
			$line =~ s/                VAR_RET/$var_ret/;
			$line =~ s/                VAR_GLOB/$var_globals/;
			$line =~ s/                VAR_STUBS/$stubVarsSetter/;
			$line =~ s/                STUBS/$stubs_str/;
		}
		push(@final, @act);
	}

	$stubdefs = getDefineSection();
	foreach (@final) {
		if (s/DEFINESTUBS/$stubdefs/) {
			last;
		}
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
system("und -db t:/U500.udb analyze -changed");

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

readExceptions();

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