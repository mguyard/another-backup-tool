#!/usr/bin/perl -w

# ----------------------------------------------------------------------------
# Copyright (C) 2012-2014  GUYARD Marc (m.guyard@orange.com)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>
# ----------------------------------------------------------------------------

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/libs";
use ABT::Global;
use Getopt::Long;
use Pod::Usage;
use Switch;
use feature qw(switch);
use File::Find::Rule;
use POSIX;
use MIME::Lite;
use Config::IniFiles;
use Sys::Hostname;
use List::Util 'shuffle';
use Parallel::ForkManager; # Gestion du MultiThread

###############################
# Read Variable from INI File #
###############################

my $ini_file = $dirname.'/configuration.ini';
# If configuration.ini don't exist or not readable, we using the default configuration.ini.default
if ( ! (-e $ini_file) || ! (-r $ini_file) ) {
	$ini_file = $dirname.'/configuration.default.ini';
}
my $configvars = Config::IniFiles->new( -file => $ini_file );

# Parse the config ini file
sub parse_configvars {
	my $section = $_[0];
	my $parameter = $_[1];
	my $var = substr $configvars->val( $section, $parameter ), 1, - 1;
	$logger->debug("Variable for ".$section." / ".$parameter." with content : ".$var) if $verbose;
	return $var;
}

###################
# Script Variable #
###################

my $script_name = 'ABT - Another Backup Tool';
my $author = 'Marc GUYARD <m.guyard@orange.com>';
my $version = '0.1';
my $config_path = $dirname.'/configurations';
my $modules_path = $dirname.'/modules';
my $max_concurrent_process = &parse_configvars('multithread','multithread.max.sessions');
my $max_concurrent_process_weekly = &parse_configvars('multithread','multithread.max.sessions.weekly');
my $customer = &parse_configvars('customer','customer.name');
my $email_relay = &parse_configvars('email','email.relay.server');
my $email_src = &parse_configvars('email','email.address.src');
my $email_dst = &parse_configvars('email','email.address.dst');
my $email_cc = &parse_configvars('email','email.address.cc');
my $options_shuffle = &parse_configvars('options','options.shuffle');

#####################
# Default arguments #
#####################

my $one_configfile;
my $directory_configfile;
my $module_files;
my $Configfile;
my $reportemail;
my $show_version;
my $show_help;
my $show_man;
my $fork;
my $default_logs_retention = "5";

#############
# Functions #
#############

## Function to show the ABT version
sub show_version {
	print "*** VERSION ***\n";
	print "Version : $version\n";
}

## Function MultiThread
$fork = new Parallel::ForkManager($max_concurrent_process);
$fork -> run_on_finish (
		sub {
			my ($pid, $exit_code, $ident, $exit_signal, $core_dump, $data_structure_reference) = @_;
			$logger->debug("Configuration Filename = ".$ident." / Exit Code : ".$exit_code) if $verbose;
			given ($exit_code) {
				when(0)
					{ $email_result{$ident} .= "<td bgcolor='#008000'><font color='white'>OK</font></td>"; }
				when(255)
					{ $email_result{$ident} .= "<td bgcolor='#808080'><font color='white'>DISABLED</font></td>"; }
				default
					{ $email_result{$ident} .= "<td bgcolor='#FF0000'><font color='white'>CRITICAL</font></td>"; }
			}
		}
);

## Send report-email
sub reportemail {
	# Generation du contenu de l'email
	my $msg_html_header = "<body><u>Veuillez trouver ci-joint le rapport <b>ABT</b> du ".$today."</u><br><br><br><table align='center' border='3'>";
	my $msg_html_content="<tr><td><b><i>Fichier de configuration</i></b></td><td><b><i>Resultat</i></b></td></tr>";
	my @email_result = sort keys(%email_result);
	foreach my $configuration_files (@email_result) {
		my $result = $email_result{$configuration_files};
		print "Clef=".$configuration_files." Valeur=".$result."\n" if $verbose;
		$msg_html_content = $msg_html_content."<tr><td><b><i>".$configuration_files."</i></b></td>".$result."</tr>";
	}
	my $msg_html_footer = "</table><br><br>Pour chaques erreurs, merci de suivre la proc&eacute;dure <a href='https://wiki.drs.local/wiki/Interne/Another-Backup-Tool#Comment_le_CdS_peut_relancer_une_sauvegarde_manuelle.C2.A0.3F'>suivante</a>";
	my $message_html_full = $msg_html_header.$msg_html_content.$msg_html_footer;
	# Generation de l'email
	my $msg = MIME::Lite->build(
		From	=> 'Another Backup Tool <'.$email_src.'>',
		To		=> $email_dst,
		Cc		=> $email_cc,
		"Return-Path"	=> $email_src,
		Subject	=> '['.$customer.'] - Rapport Another Backup Tool du '.$today,
		Type	=> 'multipart/mixed'
	) or &return_code(50, "Failed to create email");
	# Attachement de la première partie MIME, le texte du message
	$msg->attach(
		Type => 'text/html',
		Encoding => 'quoted-printable',
		Data => $message_html_full
	) or &return_code(50, "Failed to write html content in email core");
	$msg->attach(
		Type		=> 'text/plain',
		Disposition => 'attachment',
		Path		=> $dirname.'/logs/'.$today.'.log',
		Filename	=> 'ABT_emailreport_'.$today.'.log'
	) or &return_code(50, "Failed to attach ABT logs in email");
	# Le message est en UTF-8
	$msg->attr("content-type.charset" => "utf-8");
	# Precision de parametres d'envoi
	MIME::Lite->send(
		'smtp',
		$email_relay,
		HELLO=> (POSIX::uname)[1],
		PORT=>'25',
		Debug => $verbose,
		Timeout => 60
	);
	# Envoi du message
	$msg->send || die "Failed to send email\n";
}

## Show all modules available with a short description
sub modules_list {
	my $error_count = '0';
	# Find all configuration file in $modules_path
	my @module_files = &list_file($modules_path, '*.module');
	# Foreach module, lauch the module with the --description argument and show the output
	foreach $module_files (@module_files) {
		$logger->debug("Module Name : ".$module_files) if $verbose;
		if ( -X $module_files ) {
			open DESCRIPTION, "$module_files --description |";
			print <DESCRIPTION>;
		} else {
			$logger->error("The module ".$module_files." isn't executable by the user.\n	Please try this command : chmod +x ".$module_files);
			$error_count += 1;
		}
	}
	if ( $error_count gt 0 ) {
		&return_code(10, "One or more modules isn't executable. Please corrected problem like indicated before");
	}
}

## Function to verify what module used by the Configuration File
sub verify_module_configuration {
	my $ConfigXML = $_[0];
	my $ConfigFile = $_[1];
	my $config_module = $ConfigXML->{'module'};
	if ( ! -f $modules_path."/".$config_module || ! -X $modules_path."/".$config_module ) {
		$logger->error("The module (".$config_module.") specify in the configuration file (".$ConfigFile.") don't exist or not executable");
		return;
	}
	return $config_module;
}

## Function to generate the Configuration File
sub generate_configfile {
	my $ConfigFile = $_[0];
	# If configuration file don't have the good extention (need .config)
	if ( $ConfigFile !~ /.*\.config$/i ) {
		&return_code(2, "The configuration file need to have a .config extention");
	}
	# If configuration file already exist
	if ( -f $ConfigFile ) {
		my $valid = '0';
		while ( $valid eq 0 ) {
			open CONFIG,"< $ConfigFile" or $logger->warn("Unable to open the configuration file ".$ConfigFile);
			$logger->info("The configuration file ".$ConfigFile." already exist.\n");
			while (my $line = <CONFIG>) {
				print "\t\t".$line;
			}
			print "\n\n";
			$logger->info("Are you sure you want to erase the configuration file ? (Y/N)");
			my $Response = <STDIN>;
			chomp($Response);
			switch ( uc($Response) ) {
				case "Y" { $valid = '1'; }
				case "N" {
					$logger->info("Generation aborted by the user. Configuration file ".$ConfigFile." already exist.");
					$valid = '1'; }
				else {
					$logger->error("The response isn't valid. Please try again.");
				}
			}
		}
	}
	my $error_choice = '1';
	while ( $error_choice eq 1  ) {
		&modules_list;
		print "\n\nWhat module do you want to use ? ";
		my $response = <STDIN>;
		chomp($response);
		if ( ! -f $modules_path."/".$response ) {
			$logger->error("The module ".$modules_path."/".$response." don't exist. Please enter another choice\n\n\n");
			$error_choice = '1';
		} else {
			$logger->debug("Response = ".$response) if $verbose;
			$error_choice = '0';
			system "$modules_path/$response --verbose --generate $ConfigFile" if $verbose;
			system "$modules_path/$response --generate $ConfigFile" if ! $verbose;
		}
	}
}

## Function to launch the backup
sub launch_backup {
	my $Backup_Type = $_[0];
	my $Config = $_[1];
	$logger->debug("Launch from : ".hostname." at ".strftime("%Y-%m-%d %H:%M", localtime)) if $verbose;
	$logger->debug("Backup Type : ".$Backup_Type) if $verbose;
	switch ($Backup_Type) {
		case "file"
			{
				$logger->debug("File : ".$Config) if $verbose;
				if ( ! -f $Config || ! -R $Config) {
					&return_code(20, "The configuration file ".$Config." isn't a file or is not readable");
				} else {
					## Read the configuration file to know the module to use (make a function)
					my $config_parsing = &parse_config($Config);
					##Verify if the configuration file is enable
					my $enable = $config_parsing->{'enable'};
					if ( $enable eq 0 ) {
						$logger->info("This configuration file is disable. If you want enable this configuration file, change the value of 'enable' to 1");
						exit 999;
					}
					my $module = &verify_module_configuration($config_parsing, $Config);
					if ( defined($module) ) {
						$logger->debug("Module : ".$module) if $verbose;
						## Launch the module with the configuration file in argument
						if ( $verbose ) {
							open BACKUP, "$modules_path/$module --verbose --config $Config|";
						} else {
							open BACKUP, "$modules_path/$module --config $Config|";
						}
						close BACKUP;
						my $returncode = $?>>8;
						$logger->debug("Output module return code ".$returncode." for configuration ".$Config) if $verbose;
						if ( $returncode ne 0 ) {
							&return_code($returncode, "Error with the backup of the configuration file ".$Config);
						}
					}
				}

			}
		case "directory"
			{
				$logger->debug("Directory : ".$Config) if $verbose;
				$logger->debug("Starting Fork...") if $verbose;
				if ( ! -d $Config ) {
					&return_code(20, "The directory ".$Config." isn't a directory");
				} else {
					## If the backup is weekly, we change the max fork child number
					if ($Config =~ m/weekly/) {
						$fork->set_max_procs( $max_concurrent_process_weekly );
					}
					my @configuration_files = &list_file($Config, '*.config');
					if ($options_shuffle eq 1) {
						@configuration_files = shuffle(@configuration_files);
					}
					foreach my $configuration_files (@configuration_files) {
						$logger->debug("               ************************************") if $verbose;
						$logger->debug("               + Configuration : ".$configuration_files) if $verbose;
						$logger->debug("               ************************************\n\n") if $verbose;
						# Start fork child and pass to the next until $max_concurrent_process
						$fork->start($configuration_files) and next;
						$logger->debug("Demarrage du fork enfant ".$configuration_files) if $verbose;
						if ( ! -R $configuration_files ) {
							$logger->error("The configuration file $configuration_files isn't readable by the user.\nConfigation file bypassed.\nPlease change the right\n\n");
						}
						## Read the configuration file to know the module to use (make a function)
						my $config_parsing = &parse_config($configuration_files);
						## Verify if the configuration file is enable
						my $enable = $config_parsing->{'enable'};
						if ( $enable eq 0 ) {
							$logger->info("This configuration file is disable. If you want enable this configuration file, change the value of 'enable' to 1");
							$fork->finish(255);
							next;
						}
						my $module = &verify_module_configuration($config_parsing, $configuration_files);
						if ( defined($module) ) {
							$logger->debug("Module : ".$module."\n") if $verbose;
							## Launch the module with the configuration file in argument
							if ( $verbose ) {
								open BACKUP, "$modules_path/$module --verbose --config $configuration_files|";
							} else {
								open BACKUP, "$modules_path/$module --config $configuration_files|";
							}
							close BACKUP;
							$logger->debug("Output module return code ".$?." for configuration ".$configuration_files) if $verbose;
							if ( $? ne 0 ) {
								my $exit_code = $?;
								$logger->fatal("***** Backup end with errors *****\n\n") if $verbose;
								$fork->finish(50);
							} else {
								$logger->info("***** Backup end successfully *****\n\n") if $verbose;
								$fork->finish(0);
							}
						}
					}
					# Wait all fork child finished
					$fork->wait_all_children;
				}
			}
		else
			{
				&return_code(3, "Backup type not available")
			}
	}
}

##########
# Script #
##########

# Check If arguments are present
if ( @ARGV > 0 ) {
	# Parse Arguments
	GetOptions(
		"c|config=s" => \$one_configfile,
		"d|directory=s" => \$directory_configfile,
		"m|modules-list" => \&modules_list,
		"g|generate=s" => \$Configfile,
		"r|reportemail" => \$reportemail,
		"version" => \&show_version,
		"v|verbose" => \$verbose,
		"q|quiet" => sub { $verbose = 0 },
		"man" => \$show_man,
		"h|help|?" => \$show_help
	)
	# Show usage if no argument match
	or pod2usage({-message => "Argument unknown\n", -exitval => 1});
} else {
	# Show usage if no argument specified
	pod2usage({-message => "No argument specify\n", -exitval => 2});
}

# Show help usage
pod2usage(1) if $show_help;
# Show man usage
pod2usage(-verbose => 2) if $show_man;

# Call functions
&purge_files($default_logs_retention, $dirname.'/logs', "^.*\.log");
&purge_files($default_logs_retention, $dirname.'/logs', "^.*\.debug");
&generate_configfile($Configfile) if $Configfile;
&launch_backup('file', $one_configfile) if $one_configfile;
&launch_backup('directory', $directory_configfile) if $directory_configfile;
&reportemail if $reportemail && $directory_configfile;

__END__

=head1 NAME

ABT - Another Backup Tool

=head1 AUTHOR

Script written by Marc GUYARD for Orange NIS <m.guyard@orange.com>.

=head1 VERSION

0.1 BETA PERL

=head1 SYNOPSIS

B<ABT.pl>

	Options:
		--config <configuration_file>
			use a configuration file specified
		--directory <directory_path>
			use all configuration files in a directory specified
		--modules-list
			use to list all modules availables
		--generate <configuration_file>
			generate a configuration file specified
		--reportemail
			Send a email report after the execution
			Can only use in directory usage.
		--version
			show script version (need to be the first option)
		--verbose
			active script verbose
		--quiet
			active script quiet mode
		--man
			full documentation
		--help
			brief help message

=head1 OPTIONS

=over 8

=item B<--config>

Backup using a configuration file specify in argument.

=item B<--directory>

Backup using all configuration file find in the directory specify in argument.

=item B<--modules-list>

List all backup modules available with a short description.

=item B<--generate>

Generate a configuration file with the path and the name specify in argument.

=item B<--reportemail>

Send a email report after the execution
Can only use in directory usage.

=item B<--version>

Print script version and exit.

=item B<--verbose>

Activate verbose mode. Should be used with another argument.

=item B<--quiet>

Activate quiet mode. Should be used with another argument.

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<This program> is use to backup multiple equipment managed by the Orange NIS NSOC.

=head1 RETURN CODE

	Return Code :
		2 => Configuration file don't have the good extention (need .config)
		3 => Backup type not available
		10 => Module not executable or not existent
		20 => File or directory don't exist or cannot be read
		50 => Module error


=cut
