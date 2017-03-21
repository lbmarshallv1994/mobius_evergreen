#!/usr/bin/perl


# Author: Blake Graham-Henderson

# ./recalc_penalties_patron_exceeds_fines_for_holds.pl log.log
#

#use strict; use warnings;

use lib qw(../);
use LWP;
use Data::Dumper;
use Loghandler;
use DBhandler;
use Mobiusutil;
use XML::Simple;

my $logfile = @ARGV[0];
my $xmlconf = "/openils/conf/opensrf.xml";
 

if(@ARGV[1])
{
	$xmlconf = @ARGV[1];
}

if(! -e $xmlconf)
{
	print "I could not find the xml config file: $xmlconf\nYou can specify the path when executing this script\n";
	exit 0;
}
 if(!$logfile)
 {
	print "Please specify a log file\n";
	print "usage: ./recalc_penalties_direct.pl /tmp/logfile.log [optional /path/to/xml/config/opensrf.xml]\n";
	exit;
 }

my $log = new Loghandler($logfile);
#$log->deleteFile();
$log->addLogLine(" ---------------- Script Starting ---------------- ");

my %conf = %{getDBconnects($xmlconf,$log)};
my @reqs = ("dbhost","db","dbuser","dbpass","port"); 
my $valid = 1;
for my $i (0..$#reqs)
{
	if(!$conf{@reqs[$i]})
	{
		$log->addLogLine("Required configuration missing from conf file");
		$log->addLogLine(@reqs[$i]." required");
		$valid = 0;
	}
}
if($valid)
{	
	my $dbHandler;
	
	eval{$dbHandler = new DBhandler($conf{"db"},$conf{"dbhost"},$conf{"dbuser"},$conf{"dbpass"},$conf{"port"});};
	if ($@) 
	{
		$log->addLogLine("Could not establish a connection to the database");
		print "Could not establish a connection to the database";
	}
	else
	{
		my $mobutil = new Mobiusutil();
		my $updatecount=0;
	# Create the penalty for those who need it (fines exceed the defined threshold)
		my $query = "
		
		insert into actor.usr_standing_penalty (org_unit,usr,standing_penalty)
select pgpt.org_unit,au.id, pgpt.penalty from actor.usr au,
config.standing_penalty csp,
permission.grp_penalty_threshold pgpt,
(select usr,sum(balance_owed) \"balance_owed\" from money.materialized_billable_xact_summary where balance_owed>0 group by usr) mmbxs
 where 
(au.home_ou = pgpt.org_unit or au.home_ou in((select id from actor.org_unit where parent_ou=pgpt.org_unit)))and
pgpt.penalty=csp.id and
csp.name='PATRON_EXCEEDS_FINES_FOR_HOLDS' and
mmbxs.balance_owed > pgpt.threshold and
mmbxs.usr=au.id and
au.id not in( select usr from actor.usr_standing_penalty where standing_penalty=csp.id and usr=au.id)";
		my $results = $dbHandler->update($query);
		$log->addLogLine("Insert results: $results");
		
	#and now delete the penalty for those who's balance has fallen below the threshold
		my $query = "		
delete from actor.usr_standing_penalty where  
usr in
(
select au.id from actor.usr au,
config.standing_penalty csp,
permission.grp_penalty_threshold pgpt,
(select usr,balance_owed \"balance_owed\" from money.usr_summary) mmbxs
 where 
(au.home_ou = pgpt.org_unit or au.home_ou in((select id from actor.org_unit where parent_ou=pgpt.org_unit)))and
pgpt.penalty=csp.id and
csp.name='PATRON_EXCEEDS_FINES_FOR_HOLDS' and
mmbxs.balance_owed < pgpt.threshold and
mmbxs.usr=au.id
)
and
standing_penalty
in
(
select csp.id from 
config.standing_penalty csp
 where 
csp.name='PATRON_EXCEEDS_FINES_FOR_HOLDS'
)";
		my $results = $dbHandler->update($query);
		$log->addLogLine("Delete results: $results");
			
		
		
	}
}


$log->addLogLine(" ---------------- Script Ending ---------------- ");

sub getDBconnects
{
	my $openilsfile = @_[0];
	my $log = @_[1];
	my $xml = new XML::Simple;
	my $data = $xml->XMLin($openilsfile);
	my %conf;
	$conf{"dbhost"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{host};
	$conf{"db"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{db};
	$conf{"dbuser"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{user};
	$conf{"dbpass"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{pw};
	$conf{"port"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{port};
	#print Dumper(\%conf);
	return \%conf;

}

sub createDBUser
{
	my $dbHandler = @_[0];
	my $mobiusUtil = @_[1];
	my $org_unit_id = @_[2];
	my $usr = "recalc-penalty";
	my $workstation = "recalc-penalty-script";
	my $pass = $mobiusUtil->generateRandomString(10);
	
	my %params = map { $_ => 1 } @results;
	
	my $query = "select id from actor.usr where upper(usrname) = upper('$usr')";
	my @results = @{$dbHandler->query($query)};
	my $result = 1;
	if($#results==-1)
	{
		$query = "INSERT INTO actor.usr (profile, usrname, passwd, ident_type, first_given_name, family_name, home_ou) VALUES ('25', E'$usr', E'$pass', '3', 'Script', 'Script User', E'$org_unit_id')";
		$result = $dbHandler->update($query);
	}
	else
	{
		my @row = @{@results[0]};
        my $usrid = @row[0];
        $query = "select * from actor.create_salt('main')";
        my @results = @{$dbHandler->query($query)};
        my @row = @{@results[0]};
        my $salt = @row[0];
        $query = "select * from actor.set_passwd($usrid,'main',
        md5(\$salt\$$salt\$salt\$||md5(\$pass\$$pass\$pass\$)),
        \$\$$salt\$\$
        )";
        $result = $dbHandler->update($query);
		$query = "UPDATE actor.usr SET home_ou=E'$org_unit_id',ident_type=3,profile=25,active='t',super_user='t',deleted='f' where id=$usrid";
		$result = $dbHandler->update($query);
	}
	if($result)
	{
		$query = "select id from actor.workstation where upper(name) = upper('$workstation')";
		my @results = @{$dbHandler->query($query)};
		if($#results==-1)
		{
			$query = "INSERT INTO actor.workstation (name, owning_lib) VALUES (E'$workstation', E'$org_unit_id')";		
			$result = $dbHandler->update($query);
		}
		else
		{
			my @row = @{@results[0]};
			$query = "UPDATE actor.workstation SET name=E'$workstation', owning_lib= E'$org_unit_id' WHERE ID=".@row[0];	
			$result = $dbHandler->update($query);
		}
	}
	#print "User: $usr\npass: $pass\nWorkstation: $workstation";
	
	my @ret = ($usr, $pass, $workstation, $result);
	return \@ret;
}

sub deleteDBUser
{
	#This code is not used. DB triggers prevents the deletion of actor.usr.
	#I left this function as informational.
	my $dbHandler = @_[0];
	my @usrcreds = @{@_[1]};
	my $query = "delete from actor.usr where usrname='".@usrcreds[0]."'";
	print $query."\n";
	$dbHandler->update($query);	
	$query = "delete from actor.workstation where name='".@usrcreds[2]."'";
	print $query."\n";
	$dbHandler->update($query);
}

sub getCountPenalty
{
	my $dbHandler = @_[0];	
	$query = "select count(*) from actor.usr_standing_penalty";
	my @count = @{$dbHandler->query($query)};
	my $before=0;
	if($#count>-1)
	{
		my @t = @{@count[0]};
		$before = @t[0];
	}
	
	return $before;
}

