#!/usr/bin/perl
# 
#
# 

use strict; use warnings;
use lib qw(../);
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use DateTime::Format::Duration;
use Loghandler;
use Mobiusutil;
use Data::Dumper;
use XML::Simple;
use DBhandler;
use File::Grep qw(fgrep);


our $e;
our $script;
our %conf;
our $dbHandler;
our $log;

# Delete the lock file
system('rm /tmp/container_health_monitor-LOCK');

my $xmlconf = "/openils/conf/opensrf.xml";
my $configFile = shift;
if(!$configFile)
{
    print "Please specify a config file\n";
    exit;
}

my $mobUtil = new Mobiusutil(); 
my $conf = $mobUtil->readConfFile($configFile);

if($conf)
{
    %conf = %{$conf};
    if ($conf{"logfile"})
    {
        $log = new Loghandler($conf->{"logfile"});
        $log->addLogLine(" ---------------- Script Starting ---------------- ");
        my @grepOpensrfPhrases = () if !$conf{'osrfsys_log_grep'};
        @grepOpensrfPhrases = split(/,/,$conf{'osrfsys_log_grep'}) if $conf{'osrfsys_log_grep'};
        my @grepSecondFilePhrases = () if !$conf{'second_file_log_grep'};
        @grepSecondFilePhrases = split(/,/,$conf{'second_file_log_grep'}) if $conf{'second_file_log_grep'};
        my $deathOutputFolder = $conf{'death_output_folder'} || '/mnt/evergreen';

       
        # Setup timestamp
        my $dt = DateTime->now(time_zone => "local");
        # setup workstation and login
        # -------------
        # All OpenSRF checks are DISABLED NOW Because it's not really working right.
        # -------------
        # setupLogin( 1 ); # 1 = Call the create user function
        $|++;
        while(1)
        {
            # Begin basic testing interacting with storage
            # Find a bib without parts
            # -------------
            # my $sdestbib = $e->search_biblio_record_entry([
            # {
            # id =>
                # {
                    # 'not in' =>
                        # { "from" => 'bmp',
                            # 'select' =>  { "bmp" => [ 'record' ] }
                        # }
                # },
            # deleted => 'f' },
            # { limit => 3 }

            # ]);
           
           
            # my $destbib;
            # foreach(@{$sdestbib}) {
                # if ($_->id > -1) {
                    # $destbib = $_;
                    # last;
                # }
            # }
            
            # if(!$destbib)
            # {
                # $log->addLogLine("Couldn't find a bib\n Test is officially fail");
                # exit 1;
            # }
            
            # $log->addLogLine("Got bib ". $destbib->id);
            
            # # Load the holds shelf so that we interact with OpenSRF
            # # -------------
            
            # # First, we need an OU ID number, best to get a branch instead of a system or consortium
            # my @test_ou = @{$e->search_actor_org_unit([
            # { 
                # ou_type => 3,
                # opac_visible => 't'
            # }
            # ])};
            # # @test_ou = @{@test_ou[0]};
            # print "Max array ".$#test_ou."\n";
            # my $random_number = int(rand($#test_ou));
            # print "Random - $random_number\n";            
            # my $test_ou = @test_ou[$random_number];
            
            # print $test_ou->id." ".$test_ou->shortname ."\n";
            # my $storage = $script->session('open-ils.circ');
            # my $req = $storage->request(
                # 'open-ils.circ.holds.id_list.retrieve_by_pickup_lib', 0, $test_ou->id )->gather(1);
            # $log->addLine(Dumper($req));
            
            # Grep the logs for key phrases (in the config file)
            # -------------
            if($conf{'osrfsys_log_path'} && (-e $conf{'osrfsys_log_path'}) )
            {
                foreach(@grepOpensrfPhrases)
                {
                    my $thisPhrase = $_;
                    my $found = 0;
                    $thisPhrase =~ s/^\s+|\s+$//g;
                    # print "grepping ".$conf{'osrfsys_log_path'}." for $thisPhrase\n";
                    $found = 1 if ( fgrep { /$thisPhrase/ } $conf{'osrfsys_log_path'} );
                    if( $found )
                    {
                        print "exiting due to presence of $thisPhrase in ".$conf{'osrfsys_log_path'}.".\n";
                        system( "machinename=`uname -a | awk '{print \$2}'` && /bin/grep -C 10000 '$thisPhrase' ".$conf{'osrfsys_log_path'}." > $deathOutputFolder/os_`echo \$machinename`_badlogbrick_osrfsys.log" );
                        system( "machinename=`uname -a | awk '{print \$2}'` && /bin/cat /var/log/ejabberd/ejabberd.log /var/log/ejabberd/error.log > $deathOutputFolder/os_`echo \$machinename`_ejabberd.log" );
                        exit 1;
                    }
                    undef $found;
                }
            }
            
            if($conf{'second_file_log_path'} && (-e $conf{'second_file_log_path'}) )
            {
                foreach(@grepSecondFilePhrases)
                {
                    my $thisPhrase = $_;
                    my $found = 0;
                    $thisPhrase =~ s/^\s+|\s+$//g;
                    # print "grepping ".$conf{'second_file_log_path'}." for $thisPhrase\n";
                    $found = 1 if ( fgrep { /$thisPhrase/ } $conf{'second_file_log_path'} );
                    if( $found )
                    {
                        print "exiting due to presence of $thisPhrase in ".$conf{'second_file_log_path'}.".\n";
                        system( "machinename=`uname -a | awk '{print \$2}'` && /bin/grep -C 100 '$thisPhrase' ".$conf{'second_file_log_path'}." > $deathOutputFolder/os_`echo \$machinename`_badlogbrick_second_file.log" );
                        system( "machinename=`uname -a | awk '{print \$2}'` && /bin/cat /var/log/ejabberd/ejabberd.log /var/log/ejabberd/error.log > $deathOutputFolder/os_`echo \$machinename`_ejabberd.log" );
                        exit 1;
                    }
                    undef $found;
                }
            }
            if($conf{'check_websocketd'} && ($conf{'check_websocketd'} ne 'no') && ($conf{'check_websocketd'} ne 'false') )
            {
            
                if(`ps -aef | grep -v grep | grep websocketd`) 
                {
                    print "websocketd is running!\n";
                }
                else
                {
                    print "websocketd is NOT running!\n";
                    system( "machinename=`uname -a | awk '{print \$2}'` && echo websocketd died > $deathOutputFolder/os_`echo \$machinename`_websocketd_died.log" );
                    exit 1;
                }
            }
            # Clean memory            
            # -------------
            
            # undef $sdestbib;
            # undef $destbib;
            # undef @test_ou;
            # undef $test_ou;
            
            my $afterProcess = DateTime->now(time_zone => "local");
            my $difference = $afterProcess - $dt;
            my $format = DateTime::Format::Duration->new(pattern => '%M');
            my $duration =  $format->format_duration($difference);
            print "\rIt's been $duration minutes\n";
            # refresh login every 5 minutes
            # if($duration > 5 )
            # {
                # undef $e;
                # undef $dbHandler;
                # $dt = DateTime->now(time_zone => "local");
                # $script->logout();
                # undef $script;
                # setupLogin( 0 ); # 0 = Don't bother calling the create user function
            # }
            
            # Sleep for awhile and let's do it again
            # Make sure that more than 1 app server isn't running these exact checks at the exact time
            # introduce some randomness
            # -------------
            my $random_number = int(rand(50));
            sleep ( $conf{'sleep_interval'} + $random_number );
            undef $random_number;
        } # end while loop

         
        $log->addLogLine(" ---------------- Script Ending ---------------- ");
    }
    else
    {
        print "Config file does not define 'logfile' and 'marcoutdir'\n";
    }
}
 
 
sub setupLogin
{
    my $attempt_create_usr = shift;
    
    # print "Received '$attempt_create_usr' from setupLogin call\n";
    my %dbconf = %{getDBconnects($xmlconf)};
    eval{$dbHandler = new DBhandler($dbconf{"db"},$dbconf{"dbhost"},$dbconf{"dbuser"},$dbconf{"dbpass"},$dbconf{"port"});};
    if ($@)
    {
        $log->addLogLine("Could not establish a connection to the database");
        print "Could not establish a connection to the database";
        exit 1;
    }
    
    if($attempt_create_usr)
    {
         # Make sure the user exists, if not, create it!
        createDBUser($dbHandler, $mobUtil, $conf{'workstation_lib'}, $conf{'usrname'}, 
            $conf{'workstation'}, $conf{'passwd'}, $conf{'profile'}, $conf{'ident'},
            $conf{'first'}, $conf{'last'});
    }
        
    # Setup the vars for everyone
    # -------------
    undef $script if $script;
    $e->reset() if $e;
    $script = OpenILS::Utils::TestUtils->new();
    $script->bootstrap;
    $e = new_editor(xact => 1);
    $e->init;
    
    my $workstation = $e->search_actor_workstation([ {name => $conf{'workstation'}, owning_lib => $conf{'workstation_lib'} } ])->[0];

    if( !$workstation )
    {
        $script->authenticate({
            username => $conf{'usrname'},
            password => $conf{'passwd'},
            type => 'staff'});
        my $ws = $script->register_workstation($conf{'workstation'},$conf{'workstation_lib'});
        $script->logout();
    }

    $script->authenticate({
        username => $conf{'usrname'},
        password => $conf{'passwd'},
        workstation => $conf{'workstation'}
    });
}


sub createDBUser
{
	my $dbHandler = shift;
	my $mobiusUtil = shift;
	my $org_unit_id = shift;
	my $usr = shift;
	my $workstation = shift;
	my $pass = shift;
    my $profile = shift;
    my $ident = shift;
    my $first = shift;
    my $last = shift;
    
    print "Creating User\n";
	
	my $query = "select id from actor.usr where upper(usrname) = upper('$usr')";
	my @results = @{$dbHandler->query($query)};
	my $result = 1;
	if($#results==-1)
	{
		#print "inserting user\n";
		$query = "INSERT INTO actor.usr (profile, usrname, passwd, ident_type, first_given_name, family_name, home_ou) VALUES (\$\$$profile\$\$, \$\$$usr\$\$, \$\$$pass\$\$, \$\$$ident\$\$, \$\$$first\$\$, \$\$S$last\$\$, \$\$$org_unit_id\$\$)";
		$result = $dbHandler->update($query);
	}
	else
	{
		#print "updating user\n";
        my @row = @{@results[0]};
        my $usrid = @row[0];
        $query = "select * from actor.create_salt('main')";
        my @results = @{$dbHandler->query($query)};
        @row = @{@results[0]};
        my $salt = @row[0];
        $query = "select * from actor.set_passwd($usrid,'main',
        md5(\$salt\$$salt\$salt\$||md5(\$pass\$$pass\$pass\$)),
        \$\$$salt\$\$
        )";
        $result = $dbHandler->update($query);
		$query = "UPDATE actor.usr SET home_ou=\$\$$org_unit_id\$\$,ident_type=\$\$$ident\$\$,profile=\$\$$profile\$\$,active='t',super_user='t',deleted='f' where id=$usrid";
		$result = $dbHandler->update($query);
	}
	if($result)
	{
		$query = "select id from actor.workstation where upper(name) = upper('$workstation')";
		my @results = @{$dbHandler->query($query)};
		if($#results==-1)
		{
		#print "inserting workstation\n";
			$query = "INSERT INTO actor.workstation (name, owning_lib) VALUES (\$\$$workstation\$\$, \$\$$org_unit_id\$\$)";
			$result = $dbHandler->update($query);
		}
		else
		{
		#print "updating workstation\n";
			my @row = @{@results[0]};
			$query = "UPDATE actor.workstation SET name=\$\$$workstation\$\$, owning_lib= \$\$$org_unit_id\$\$ WHERE ID=".@row[0];
			$result = $dbHandler->update($query);
		}
	}
	#print "User: $usr\npass: $pass\nWorkstation: $workstation";
	
	my @ret = ($usr, $pass, $workstation, $result);
	return \@ret;
}

 sub getDBconnects
{

    my $openilsfile = shift;
    my $xml = new XML::Simple;
    my $data = $xml->XMLin($openilsfile);
    my %dbconf;
    $dbconf{"dbhost"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{host};
    $dbconf{"db"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{db};
    $dbconf{"dbuser"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{user};
    $dbconf{"dbpass"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{pw};
    $dbconf{"port"}=$data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{port};
    ##print Dumper(\%dbconf);
    return \%dbconf;
}

 exit;