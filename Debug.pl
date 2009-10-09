#!/usr/bin/env perl
#
# Debug.pl
#
# Copyright (c) 2009 Fletcher T. Penney
#	<http://fletcherpenney.net/>
#
#

# This routine is designed to create a log file that I can use to try and help 
# debug when SimplenoteSync isn't working.
# If we hit a point where we need it, I'll ask you to send me a copy of the 
# log file from your home directory
# 
# Of note, it will log the titles of files on your computer, but will not log 
# your email address or password.
#
#
# So, do the following:
#
#	First - make sure that you synchronize your iPhone app so it and web app 
#		are up to date
#
#	Make sure there is at least one note on the iPhone that is also on the web 
#
#	Synchronize iphone again if necessary
#
#	Make sure there is at least one text file in your local directory - 
#		remember that this file must have ".txt" as the file extension
#
#	Make sure that you have the latest versions of this software from my web 
#		site
#
#	Enable debug mode in SimplenoteSync.pl
#
#	Run "SimplenoteSync.pl > ~/SimplenoteSyncDebug.txt"
#
#	Run "Debug.pl"
#
#	Open SimplenoteSyncDebug.txt and SimplenoteSyncLog.txt and make sure no 
#		confidential information is included
#
#	Email me copies of those two files along with a description of the problem
#		that you're having
#

use strict;
use warnings;
use File::Basename;
use File::Path;
use Cwd;
use Cwd 'abs_path';
use MIME::Base64;
use LWP::UserAgent;
my $ua = LWP::UserAgent->new;
use Time::Local;
use File::Copy;


# Configuration
#
# Create file in your home directory named ".simplenotesyncrc"
# First line is your email address
# Second line is your Simplenote password
# Third line is the directory to be used for text files

open (CONFIG, "<$ENV{HOME}/.simplenotesyncrc") or die "Unable to load config file $ENV{HOME}/.simplenotesyncrc.\n";

my $email = <CONFIG>;
my $password = <CONFIG>;
my $rc_directory = <CONFIG>;
my $sync_directory;

close CONFIG;
chomp ($email, $password, $rc_directory);

if ($rc_directory eq "") {
	# If a valid directory isn't specified, then don't keep going
	die "A directory was not specified.\n";
};
$rc_directory =~ s/\\ / /g;
if ($sync_directory = abs_path($rc_directory)) {
} else {
	# If a valid directory isn't specified, then don't keep going
	die "$rc_directory does not appear to be a valid directory.\n";
};
$sync_directory =~ s/ /\\ /g;

open (LOG, ">$ENV{HOME}/SimplenoteSyncLog.txt");
print LOG ".simplenotesyncrc:\n";
my $temp = $email;
$temp =~ s/[A-Za-z]/\#/g;
print LOG $temp . "\npassword redacted\n";
print LOG "$sync_directory\n\n";

my $url = 'https://simple-note.appspot.com/api/';

# Document Mac OS X version
my $mac_version = readpipe ("sw_vers");

print LOG "Mac OS X:\n$mac_version\n\n";


# Document token (proof of successful login to Simplenote)
my $token = getToken();
print LOG "Token:\n$token\n\n";

# Document contents of simplenote account (keys only - no private info)
getNoteIndex();

# Document list of ".txt" files in your specified directory, along with 
#	mod/create times
print LOG "Looking for .txt files in \"$sync_directory\"\n";
checkLocalDirectory();

# Do a list of all files in the directory, in case user is forgetting about
#	.txt extension
my $filelist = readpipe("ls $sync_directory");
print LOG "Complete file listing:\n$filelist\n\n";

# append the contents of simplenotesync.db
print LOG "simplenotesync.db:\n";
close LOG;
system ("cat $sync_directory/simplenotesync.db >> $ENV{HOME}/SimplenoteSyncLog.txt");

1;

sub getToken {
	# Connect to server and get a authentication token

	my $content = encode_base64("email=$email&password=$password");
	
	my $response =  $ua->post($url . "login", Content => $content);

	if ($response->content =~ /Invalid argument/) {
		die "Problem connecting to web server.\nHave you installed Crypt:SSLeay as instructed?\n";
	}


	die "Error logging into Simplenote server:\n$response->content\n" unless $response->is_success;


	return $response->content;
}


sub getNoteIndex {
	# Get list of notes from simplenote server
	my %note = ();

	my $response = $ua->get($url . "index?auth=$token&email=$email");
	my $index = $response->content;
	
	print LOG "Index from Simplenote:\n$index\n\n";
}


sub checkLocalDirectory {
	print LOG "Local Files:\n";
	foreach my $filepath (glob("$sync_directory/*.txt")) {
		
		print LOG "$filepath:\n";
		my @d=gmtime ((stat("$filepath"))[9]);
		printf LOG "\tmodify: %4d-%02d-%02d %02d:%02d:%02d\n", $d[5]+1900,$d[4]+1,$d[3],$d[2],$d[1],$d[0];

		@d = gmtime (readpipe ("stat -f \"%B\" \"$filepath\""));
		printf LOG "\tcreate: %4d-%02d-%02d %02d:%02d:%02d\n\n", $d[5]+1900,$d[4]+1,$d[3],$d[2],$d[1],$d[0];
	}
	
}