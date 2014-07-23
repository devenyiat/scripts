use Cwd;
use File::Copy;
use File::Path;
use Understand;

use strict;


my $workdir = getcwd();

# our @temp;
our @definestubs = ();
our @g_exceptions = ();
our $debug = 0;

sub readExceptions {
	open FH, "<$workdir/exceptions.cfg";
	my @exs = <FH>;
	close FH;


	foreach my $ex (@exs) {
		$ex =~ m/(.*)\n/;
		push(@g_exceptions, $1);
	}
}

sub scan {
	my @temp = ();
	scandirs(\@temp, $_[0]);
	chdir($workdir);
	return @temp;
}

sub scandirs {
	my $dir;
	my $reference = $_[0];
	if ($_[2] =~ /(\w+)/){
		$dir = $_[1] . "/" . $_[2];
	}
	else {
		$dir = $_[1];
	}
	chdir($dir);
	my @files = <*>;
	foreach my $file (@files) {
		chdir($dir);
		if (-f $file) {
			if (($file =~ /\.ads$/) or ($file =~ /\.adb$/) or ($file =~ /\.ada$/)) {	
				# $number_of_files = $number_of_files + 1;
				my $string = "#dir: " . $dir . "/ #file: " . $file;
				push(@$reference, $string);
			}
		}
		if (-d $file) {
			scandirs($reference, $dir, $file);
		}
	}
}

sub convertDotToHyphen {
	my $result = $_[0];
	$result =~ tr/./-/;
	$result = lc $result;
	return $result;
}

sub getPtuName {
	# $temp = $package;
	# $temp =~ tr/./_/;
	my $result = "$main::test_type\_" . $main::packageu;
	return $result;
}

sub header {
	my @p = $main::db->lookup($main::packages[0], "Ada Package");
	my $result = $p[0]->longname();
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
		if ($_[3] != $_[2]) {
			addString($reference, " (\n");
			printIndentation($reference, $_[2]+1);
			addString($reference, "others =>");
		}
		if ($entity->refs("Ada Typed") == ()) {
			getSubItems($reference, $entity->ref("Ada Derivefrom")->ent, $_[2], $_[2]);
		}
		else {
			my $element = $entity->ref("Ada Typed")->ent;
			# check array elemets
			getSubItems($reference, $element, $_[2]+1, $_[2]);
		}
		if ($_[3] != $_[2]) {
			addString($reference, " )");
		}
	}

	# if we have record type
	if ($entity->kindname() =~ /Type Record/) {
		if ($_[3] != $_[2]) {
			addString($reference, " (");
		}
		# get record elements
		my @components = $entity->ents("Ada Declare", "Ada Component");
		if (@components == ()) {
			if ($entity->refs("Ada Derivefrom") != ()){
				getSubItems($reference, $entity->ref("Ada Derivefrom")->ent, $_[2], $_[2]);
			}
			else {
				getSubItems($reference, $entity->ref("Ada Typed")->ent, $_[2], $_[2]);
			}
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
				getSubItems($reference, $comp->ref("Ada Typed")->ent, $_[2]+1, $_[2]);
			}
		}
		if ($_[3] != $_[2]) {
			addString($reference, " )");
		}
	}

	# if we have abstract type
	if ($entity->kindname() =~ /Abstract Type/ or $entity->kindname() =~ /Tagged Type/) {
		if ($_[3] != $_[2]) {
			addString($reference, " (");
		}
		# check ancient type
		if ($entity->refs("Ada Derivefrom") != ()) {
			getSubItems($reference, $entity->ref("Ada Derivefrom")->ent, $_[2], $_[2]);
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
			getSubItems($reference, $comp->ref("Ada Typed")->ent, $_[2]+1, $_[2]);
		}
		# close opening (
		if ($_[3] != $_[2]) {
			addString($reference, " )");
		}
	}
}

sub getSourceFileList {

	my $result = "";

	foreach my $file (@main::files_to_copy) {
        if (-e $main::filesloc{$file} . "/" . $file) {
            $result = $result . "COMMENT ****      - " . $file . "\n";
        }
	}
	$result = $result . "COMMENT ****";

	return $result;
}

sub getWithList {
	my @withList = ();
	my $result = "";
	foreach my $act_p (@main::packages) {
		my @p = $main::db->lookup($act_p, "Ada Package");
		my @w = $p[0]->ents("Ada With Body, Ada With Spec");
		foreach (@w) {
			if (not $_->longname() ~~ @withList) {
				push(@withList, $_->longname());
			}
		}
	}
	foreach (@withList) {
		$result = $result . "# with " . $_ . ";\n";
	}
	if (not $main::packages[0] ~~ @withList) {
		$result = $result . "# with $main::packages[0];\n# with Rtrt_Test_Package;";
	}
	return $result;
}

# return 1 if there is an undiscovered call to server package

sub rec_func {
	my $result = 0;
    
	my @cfs = $_[0]->refs("Ada Call ~Access");
	print "\t\t" . $_[0]->longname() . "\n";
	
    
    # foreach my $cf (@cfs) {
		# print "\t\t\t" . $cf->ent->longname() . "\n";
		# my $called_package = $cf->ent->parent->longname();
		# if ($called_package ~~ @main::packages and $called_package ne $main::packages[0]) {
			# return 1;
		# }
		# else {
			# if ($called_package eq $main::packages[0]) {
				# $result = rec_func($cf);
			# }
		# }
	# }
    
    my $refseen = $_[1];
    
    foreach my $cf (@cfs) {
    
        my $called_package = $cf->ent->parent->longname();
        # if there is a call to server --> yeeeyy, store it
        if ($called_package ~~ @main::packages and $called_package ne $main::packages[0]) {
            return 1;
        }
        else {
            # if we stayed in client follow the trace
            if ($called_package eq $main::packages[0] and not $cf->ent->longname() ~~ @$refseen) {
            
                # mark client subprogram visited
                push(@$refseen, $cf->ent->longname());
                $result = rec_func($cf, $refseen);
            }
        }
    }
    
    return $result;
}

# case of MT: list all the subprograms
# case of IT: list subprograms which contains calls to server packages

sub subprogram_entities {
	my @result = ();
    my @visited_subprograms = ();
	my @p = $main::db->lookup($main::packages[0], "Ada Package");
	if ($main::test_type eq "MT"){
		my @s = $p[0]->ents("Ada Declare Body", "Ada Procedure, Ada Function");
		@result = @s;
	}
	else {
        # my @s = $p[0]->ents("Ada Declare Spec", "Ada Procedure ~Local, Ada Function ~Local");
		my @s = $p[0]->ents("Ada Declare Body", "Ada Procedure, Ada Function");
		foreach my $s (@s) {
			print $s->longname() . "\n";
			# my @called_functions = $s->refs("Ada Call ~Access");
			# foreach my $cf (@called_functions) {
				# my $called_package = $cf->ent->parent->longname();
				# print "\t" . $called_package . "\n";
				# if ($called_package ~~ @main::packages and $called_package ne $main::packages[0]) {
					# push(@result, $s);
					# last;
				# }
				# if ($called_package eq $main::packages[0]) {
					if (rec_func($s, \@visited_subprograms) == 1) {
						push(@result, $s);
						# last;
					}
				# }
			# }
		}
	}
	return @result;
}

sub getStubs_rec {
	my @result = ();
	my @called_functions = $_[0]->refs("Ada Call ~Access");
	foreach my $cf (@called_functions) {
		my $called_package = $cf->ent->parent->longname();
		if (not $called_package ~~ @main::packages and not $called_package ~~ @g_exceptions) {
			push(@result, $cf);
			if (not $called_package ~~ @definestubs) {
				push(@definestubs, $called_package);
			}
		}
		else {
			if (not $cf->ent->longname() ~~ @getStubs::seensubs) {
				push(@getStubs::seensubs, $cf->ent->longname());
				push(@result, getStubs_rec($cf->ent));
			}
		}
	}
	return @result;
}

sub getUniqueStubs {
	my @result = ();
	my @stubs = ();
	@stubs = getStubs_rec($_[0]);
	my @uniqueStubs = ();
	foreach my $s (@stubs) {
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

	our @seensubs = ();

	my $result = "";
	my $reference = $_[1];
	my @uniqueStubs = getUniqueStubs($_[0]);
	foreach my $s (@uniqueStubs) {
		$result = $result . "\n                -- STUB " . $s->ent->longname() . " (";
		my @params = $s->ent->ents("Ada Declare", "Ada Parameter");
		foreach my $p (@params) {
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
		if (not $result =~ s/(.*),/$1\)/s) {
            $result = $result . " )";
        }
		if ($s->ent->type() ne "") {
			$result = $result . " Stub_" . $s->ent->name();
			push(@$reference, $s->ent);
		}
		$result = $result . "\n";
	}
	return $result;
}

sub generateStubDeclaration {
	my $result = "";
	my $reference = $_[0];

	foreach my $stub (@$reference) {
		addString(\$result, "        # " . getStubVariableName($stub) . " : " . $stub->ref("Ada Typed")->ent->longname() . ";\n");
	}

	return $result;
}

# @param1 : reference of out parameter entities
sub setStubVars {
	my $reference = $_[0];
	my $result = "";
	foreach my $param (@$reference) {
		my $typeEnt = $param->ref("Ada Typed")->ent;
		my $keyword = getKeyWord($typeEnt);
		addString(\$result, "\n                -- $keyword " . getStubVariableName($param) . ",\n                -- &   init =");
		getSubItems(\$result, $typeEnt, 1, 0);
		addString(\$result, ",\n                -- &   ev   ==\n");
	}

	if (@$reference == ()) {
		$result = "                COMMENT None\n";
	}

	return $result;
}

sub getDefineSection {

	my $result = "";

	foreach my $d (@definestubs) {
		$result = $result . "\nDEFINE STUB $d\nEND DEFINE\n";
	}

	return $result;
}

sub getKeyWord {
	my $typeEnt = $_[0];
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
	my @globals = ();
	my @globals_set = $_[0]->ents("Ada Set", "Ada Object");
	my @globals_use = $_[0]->ents("Ada Use", "Ada Object");
	my $result = "";
	foreach my $g (@globals_set) {
		if ($g->name() =~ m/^g_/i) {
			my $typeEnt = $g->ref("Ada Typed")->ent;
			my $keyword = getKeyWord($typeEnt);
			
			addString(\$result, "\n                -- $keyword " . $g->name() . ",\n                -- &   init ==,\n                -- &   ev   =");
			getSubItems(\$result, $g->ref("Ada Typed")->ent, 1, 0);
			addString(\$result, "\n");

		}
	}
	foreach my $g (@globals_use) {
		my $g_name = $g->name();
		if ($g->name() =~ m/^g_/i and $result !~ m/$g_name/) {
			my $typeEnt = $g->ref("Ada Typed")->ent;
			my $keyword = getKeyWord($typeEnt);
			
			addString(\$result, "\n                -- $keyword " . $g->name() . ",\n                -- &   init =");
			getSubItems(\$result, $g->ref("Ada Typed")->ent, 1, 0);
			addString(\$result, ",\n                -- &   ev   = init\n");

		}
	}
	if ($result eq "") {
		$result = "                COMMENT None\n";
	}
	return $result;
}

sub getSubprogramList {
	my @subs = subprogram_entities();
	my $result = "COMMENT ****";
	foreach my $s (@subs) {
		$result = $result . "\nCOMMENT ****         " . uc $s->name();
	}
	return $result;
}

sub parameters {

	my @params = $_[0]->ents("Ada Declare", "Ada Parameter");

	my $result = "";

	foreach my $param (@params) {
		# $param->type() =~ m/(in )?(out )?(.*)/;
		# $type = $3;
		$result = $result . "        # " . $param->name() . " : " . $param->ref("Ada Typed")->ent->longname() . ";\n";
	}

	return $result;
}

sub setSignVars {
	my @params = $_[0]->ents("Ada Declare", "Ada Parameter");

	my $result = "";

	foreach my $param (@params) {
		$param->type() =~ m/(in )?(out )?(.*)/;
		my $mode = $1 . $2;
		my $typeEnt = $param->ref("Ada Typed")->ent;
		my $keyword = getKeyWord($typeEnt);
		if ($mode eq "in ") {
			# print "IN\n";
			# print $param->ref("Ada Typed")->ent->name() . "\n";
			addString(\$result, "\n                -- $keyword " . $param->name() . ",\n                -- &   init =");
			getSubItems(\$result, $typeEnt, 1, 0);
			addString(\$result, ",\n                -- &   ev   ==\n");
		}
		if ($mode eq "out ") {
			# print "OUT\n";
			addString(\$result, "\n                -- $keyword " . $param->name() . ",\n                -- &   init ==");
			addString(\$result, ",\n                -- &   ev   = ");
			getSubItems(\$result, $typeEnt, 1, 0);
			addString(\$result, "\n");
		}
		if ($mode eq "in out ") {
			# print "INOUT\n";
			addString(\$result, "\n                -- $keyword " . $param->name() . ",\n                -- &   init =");
			getSubItems(\$result, $typeEnt, 1, 0);
			addString(\$result, ",\n                -- &   ev   = \n");
		}
	}

	if (@params == ()) {
		$result = "                COMMENT None\n";
	}

	return $result;
}

sub returnvar {
	my $result = "";
	if ($_[0]->type() ne "") {		
		$result = "        # Ret_" . $_[0]->name() . " : " . $_[0]->ref("Ada Typed")->ent->longname() . ";\n";
	}
	return $result;
}

sub setRetVar {
	my $result = "";
	my $keyword = getKeyWord($_[0]);
	if ($_[0]->type() ne "") {		
		$result = "\n                -- $keyword Ret_" . $_[0]->name() . ",\n                -- &    init ==,\n                -- &    ev   =";
		getSubItems(\$result, $_[0]->ref("Ada Typed")->ent, 1, 0);
		addString(\$result, "\n");
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
	my $result = "        # ";
	if ($_[0]->type() ne "") {		
		$result = $result . "Ret_" . $_[0]->name() . " := ";
	}
	$result = $result . $_[0]->longname();
	my @params = $_[0]->ents("Ada Declare", "Ada Parameter");
	if (@params != ()) {
		$result = $result . "( ";
	}
	foreach my $param (@params) {
		# $param->type() =~ m/(in )?(out )?(.*)/;
		# $type = $3;
		$result = $result . $param->name() . ", ";
	}
	if ($result !~ s/, $/ );/) {
		$result = $result . ";"
	}
	return $result;
}

sub signature {
	my $result = $_[0]->longname() . "( " . $_[0]->parameters() . " )";
	if ($_[0]->type() ne "") {		
		$result = $result . " return " . $_[0]->type();
	}
	return $result; 
}

sub ptumaker {
	open FH, "<$workdir/minta.ptu" or die "error";
	my @lines = <FH>;
	close FH;

	my @part_one = ();
	my @part_two = ();
	my @final = ();

	# divide PTU to 2 parts
	# first ends at DEFINESTUBS line
	my $idx = -1;
	do {
		$idx++;
		push(@part_one, $lines[$idx]);
	} while ($lines[$idx] !~ m/DEFINESTUBS/);
	$idx = $idx + 1;

	# second goes to the end
	while ($idx <= $#lines) {
		push(@part_two, $lines[$idx]);
		$idx++;
	}

	# create the first part of PTU
	my $componentName = "";
	if ($main::test_type eq "MT") {
		$componentName = $main::packages[0];
	}
	else {
		$componentName = $main::itp_number;
	}
	my $ptuName = getPtuName();
	my $header = header();
	my $sourceFileList = getSourceFileList();
	my $subprogramList = getSubprogramList();
	my $withList = getWithList();

	foreach my $line (@part_one) {
		$line =~ s/COMMENT \*\*\*\*  PTUNAME.ptu/COMMENT \*\*\*\*  $ptuName.ptu/;
		$line =~ s/COMMENT \*\*\*\*      - SOURCES_TO_TEST/$sourceFileList/;
		$line =~ s/COMMENT \*\*\*\*         SUBPROGRAMS/$subprogramList/;
		$line =~ s/HEADER PTUNAME, ,/HEADER $header, ,/;
		$line =~ s/COMPONENTNAME/$componentName/;
		if ($main::test_type eq "MT") {
			$line =~ s/BEGIN PACKAGENAME, Attol_Test/BEGIN $header, Attol_Test/;
		}
		else {
			$line =~ s/BEGIN PACKAGENAME, Attol_Test/BEGIN/;
		}
		$line =~ s/WITH PART/$withList/;
		$line =~ s/MONOGRAM/$main::initials/;
		$line =~ s/PRODDATE/$main::date/;
		$line =~ s/RELEASE/$main::release/;
		$line =~ s/VERSION/$main::environmentversion/;
	}

	push(@final, @part_one);

	# foreach $sub ($p[0]->ents("Ada Declare", "Ada Procedure ~Local, Ada Function ~Local")) {
	my @p = $main::db->lookup($main::packages[0], "Ada Package");
	# foreach $sub ($p[0]->ents("Ada Declare", "Ada Procedure, Ada Function")) {
	foreach my $sub (subprogram_entities()) {
		my @act = @part_two;
		my $name = uc $sub->name();
		my $fullname = $sub->longname();
		my $parameters = parameters($sub);
		my $return = returnvar($sub);
		my $functioncall = functioncall($sub);
		my $signature = signature($sub);
		my $var_signs = setSignVars($sub);
		my $var_ret = setRetVar($sub);
		my $var_globals = setGlobals($sub);
		my @stubVariables = ();
		my $stubs_str = getStubs($sub, \@stubVariables);
		my $stubVariablesStr = generateStubDeclaration(\@stubVariables);
		my $stubVarsSetter = setStubVars(\@stubVariables);
		foreach my $line (@act) {
			$line =~ s/SUBPROGRAM1/$name/;
			$line =~ s/SUBPROGRAMFULL1/$fullname/;
			$line =~ s/        SIGNATURE VARIABLES/$parameters/;
			$line =~ s/        RETURN VARIABLE/$return/;
			$line =~ s/        STUB VARIABLES/$stubVariablesStr/;
			$line =~ s/        FUNCTION CALL/$functioncall/;
			$line =~ s/SIGNATURE/$signature/;
			$line =~ s/MONOGRAM/$main::initials/;
			$line =~ s/PRODDATE/$main::date/;
			$line =~ s/RELEASE/$main::release/;
			$line =~ s/                VAR_SIGNS/$var_signs/;
			$line =~ s/                VAR_RET/$var_ret/;
			$line =~ s/                VAR_GLOB/$var_globals/;
			$line =~ s/                VAR_STUBS/$stubVarsSetter/;
			$line =~ s/                STUBS/$stubs_str/;
		}
		push(@final, @act);
	}

	my $stubdefs = getDefineSection();
	foreach (@final) {
		if (s/DEFINESTUBS/$stubdefs/) {
			last;
		}
	}

	open FH, ">t:/Test_Environments/$main::test_type\_$main::packageu/$main::test_type\_$main::packageu.ptu";
	print FH @final;
	close FH;

}

sub rtpmaker {
	my $id = 434727470;

	open FH, "<$workdir/minta.rtp" or die "error";
	my @lines = <FH>;
	close FH;

	my @part_one = ();
	my @part_two = ();
	my @part_three = ();
	my @final = ();

	my $idx = -1;
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

	my $name = getPtuName();
	foreach my $line (@part_one) {
		$line =~ s/NAME/$name/;
		$line =~ s/LOCATION/t:\\Test_Environments\\$main::test_type\_$main::packageu\\/;
	}
	push(@final, @part_one);

	print "Adding files to RTRT project:\n";
	foreach my $file (@main::files_to_copy) {
        if (-e $main::filesloc{$file} . "/" . $file) {
            print "\t$file\n";
            my @act = @part_two;
            foreach my $line (@act) {
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
	}

	foreach my $line (@part_three) {
		$line =~ s/NAME/$name/;
	}
	push(@final, @part_three);

	open FH, ">t:/Test_Environments/$main::test_type\_$main::packageu/$main::test_type\_$main::packageu.rtp";
	print FH @final;
	close FH;
	
}

sub modify_source {

	my $package = $main::packages[0];

	open FH, "<t:/Test_Environments/$main::test_type\_$main::packageu/Source/" . convertDotToHyphen($package) . ".ads" or die "error";
	my @lines = <FH>;
	close FH;

	my $content = "";
	foreach my $l (@lines) {
		$content = $content . $l;
	}

	open FH, ">t:/Test_Environments/$main::test_type\_$main::packageu/Source/" . convertDotToHyphen($package) . ".ads" or die "error";

	# if ($content =~ m/g_CTD_Reference/) {
	# 	$content =~ s/end $package/--HOST_TEST_BEGIN\n   procedure Elab;\n   procedure Attol_Test;\n--HOST_TEST_END\n\nend $package/i;
	# }
	# else {
	if ($content =~ s/end $package/--HOST_TEST_BEGIN\n   procedure Attol_Test;\n--HOST_TEST_END\n\nend $package/i) {
		print "Attol_Test inserted into spec\n";
	}
	else {
		print "something went wrong at instering Attol_Test into spec\n";
	}
		
	# }


	print FH $content;

	close FH;

	open FH, "<t:/Test_Environments/$main::test_type\_$main::packageu/Source/" . convertDotToHyphen($package) . ".adb" or die "error";
	@lines = <FH>;
	close FH;

	my $content = "";
	foreach my $l (@lines) {
		$content = $content . $l;
	}

	open FH, ">t:/Test_Environments/$main::test_type\_$main::packageu/Source/" . convertDotToHyphen($package) . ".adb" or die "error";

	# if ($content =~ m/g_CTD_Reference/) {
	# 	$content =~ s/\nbegin/\n--HOST_TEST_BEGIN\nprocedure Elab is\nbegin\n--HOST_TEST_END/s;
	# 	$content =~ s/end $package/\n--HOST_TEST_BEGIN\nend Elab;\n\n\n   procedure Attol_Test is separate;\n--HOST_TEST_END\n\nend $package/i;
	# }
	# else {
	if ($content =~ s/end $package/\n--HOST_TEST_BEGIN\n   procedure Attol_Test is separate;\n--HOST_TEST_END\n\nend $package/i) {
		print "Attol_Test inserted into body\n";
	}
	else {
		print "something went wrong at instering Attol_Test into body\n";
	}
	# }

	print FH $content;

	close FH;

}

sub getRegistryValueForFile {
    my $to_find = $_[0];
    my @list = grep(/#file: $to_find/i, @main::sources);
    return $list[0];
}

sub update {
    # renaming all the previous sources to .bak and copying the new ones
    my @list_of_old_files = scan("t:/Test_Environments/$main::test_type\_$main::packageu/Source/");
    foreach my $old_file (@list_of_old_files) {
        $old_file =~ m/#dir: (.*)\/\/(.*) #file: (.*)/;
        rename "$1/$2/$3", "$1/$2/$3.bak";
        
        my $reg_value = getRegistryValueForFile($3);
        $reg_value =~ m/#dir: (.*)\/\/(.*) #file: (.*)/;
        copy("$1/$2/$3", "t:/Test_Environments/$main::test_type\_$main::packageu/Source/$3");
        
        push(@main::files_to_copy, $3);
    }
    
    # editing the .ptu file
	open FH, "<t:/Test_Environments/$main::test_type\_$main::packageu/$main::test_type\_$main::packageu.ptu" or die "error";
	my @lines = <FH>;
	close FH;
    
    my $result = "";
    
    foreach my $line (@lines) {
        $line =~ s/Author \(.*\)/Author ($main::initials)/;
        $line =~ s/PTU last run on software release \(.*\)/PTU last run on software release ($main::release)/;
        $line =~ s/PTU last mod.* \(.*\)/PTU last modification date ($main::date)/;
        $line =~ s/PTU testing environment version: .*/PTU testing environment version: $main::environmentversion/;
        $result = $result . $line;
    }
    
    open FH, ">t:/Test_Environments/$main::test_type\_$main::packageu/$main::test_type\_$main::packageu.ptu" or die "error";
    print FH $result;
    close FH;
}

open FH, "<environment.cfg";
my @lines = <FH>;
close FH;

$lines[0] =~ m/TEST_TYPE:\s*(.*)/;
our $test_type = $1;
$lines[1] =~ m/ITP:\s*(.*)/;
our $itp_number = $1;

my $temporary_line = $lines[2];
my $number_of_packages = 0;
our @packages;
while ($temporary_line =~ m/MODULES_TO_TEST:\s*(.*?),(.*)/) {
	$packages[$number_of_packages] = $1;
	$number_of_packages++;
	$temporary_line = "MODULES_TO_TEST:$2";
}
$temporary_line =~ m/MODULES_TO_TEST:\s*(.*)/;
$packages[$number_of_packages] = $1;
$number_of_packages++;

our $packageu = "";
if ($test_type eq "MT") {
	$packageu = $packages[0];
	$packageu =~ tr/./_/;
}
else {
	$packageu = $itp_number;
}

$lines[3] =~ m/INITIALS:\s*(.*)/;
our $initials = $1;
$lines[4] =~ m/DATE:\s(.*)/;
our $date = $1;
$lines[5] =~ m/RELEASE:\s(.*)/;
our $release = $1;
$lines[6] =~ m/ENVIRONMENT:\s(.*)/;
our $environmentversion = $1;

mkpath("t:/Test_Environments/$test_type\_$packageu/Source/");
mkpath("t:/Test_Environments/$test_type\_$packageu/$test_type\_$packageu/");

system("und -db t:/U500.udb analyze -rescan");
system("und -db t:/U500.udb analyze -changed");

our $db = Understand::open("T:/U500.udb");

our @files_to_copy = ();

print "Checking dependencies for package:\n";
foreach my $package (@packages) {

	print "\t$package\n";;
	my @p = $db->lookup($package, "Ada Package");
	my @s = $p[0]->refs("Ada Declare Stub");

	push(@files_to_copy, lc convertDotToHyphen($p[0]->longname()) . ".ads");
	push(@files_to_copy, lc convertDotToHyphen($p[0]->longname()) . ".adb");

	foreach (@s) {
		my $temp = lc convertDotToHyphen($package) . "-" . $_->ent()->name() . ".adb";
		push(@files_to_copy, $temp);
	}

}

our @sources = (scan("t:/Source/"), scan("t:/Additional_Files/"));

my $update = $ARGV[0];

if ($update == 1) {
    update();
}

# ---------------------
# creating and modifying .alk file
system("\"c:/Program Files (x86)/Rational/TestRealTime/bin/intel/win32/attolalk.exe\" t:/Test_Environments/$test_type\_$packageu/$test_type\_$packageu.alk t:/Stubs");

open FH, "<t:/Test_Environments/$test_type\_$packageu/$test_type\_$packageu.alk";
@lines = <FH>;
close FH;

open FH, ">t:/Test_Environments/$test_type\_$packageu/$test_type\_$packageu.alk";

print "Modifying alk file\n";

my @mod = ();
foreach my $l (@lines) {
	foreach my $file (@files_to_copy) {
		if ($l =~ m/\\$file/) {
			my $temp = $l;
			my $loc = $main::filesloc{$file};
			$temp =~ s/t:\\Stubs\\/t:\\Test_Environments\\$test_type\_$packageu\\Source\\/;
			print "\t$l\n";
			push(@mod, $temp);
			$l =~ s/(.*)\n/\n/;
			last;
		}
	}
	print FH $l;
}

print FH "\n\n";
print FH @mod;

close FH;
# ---------------------

if ($update != 1) {

    # -------------------
    # copy source files under Source
    our %filesloc;

    readExceptions();

    foreach my $f (@files_to_copy) {
        my $idx = 0;
        while ($sources[$idx] !~ m/$f/ and $idx <= $#sources) {
            $idx++;
        }
        print $sources[$idx]. "\n";
        $sources[$idx] =~ m/#dir: (.*)\/\/(.*) #file: (.*)/;
        print "$1/$2$f". "\n";
        copy("$1/$2$f", "t:/Test_Environments/$test_type\_$packageu/Source/$f");
        my $loc = "$1/$2";
        $loc =~ tr/\//\\/;
        $main::filesloc{$f} = $loc;
    }
    # ---------------------

    ptumaker();

    rtpmaker();

}

if ($test_type eq "MT") {
	modify_source();
}

print "Press ENTER to exit.."; <STDIN>;
