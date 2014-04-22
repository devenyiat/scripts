use File::stat;
use Time::localtime;

$stat = (stat("c:/Users/Attila/Documents/GitHub/scripts/temp.pl"));
print "Last modify date: " . $stat->mtime