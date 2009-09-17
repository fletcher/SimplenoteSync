#!/usr/bin/env perl
#
# SimpleSync.pl
#
# Copyright (c) 2009 Fletcher T. Penney
#	<http://fletcherpenney.net/>
#
#

# Need to install Crypt::SSLeay to get https to work...


# TODO: Need to check for duplicate filenames to avoid overwriting
# TODO: Track previous files to know when something was deleted
# TODO: Need lots of error checking
# TODO: How to handle renames?
# TODO: How to handle simultaneous edits?
# TODO: Avoid overwriting existing file when downloading
# TODO: Any special characters in title to avoid?
# TODO: move configuration details to a dotfile for easy upgrading
# TODO: need to compare information between local and remote files when same title in both (e.g. simplesync.db lost, or collision)
# TODO: Windows/Linux compatibility

use strict;
use warnings;
use File::Basename;
use File::Path;
use Cwd;
use Cwd 'abs_path';
use MIME::Base64;
use LWP::UserAgent;
my $ua = LWP::UserAgent->new;

# Configuration

# Create file in your home directory named ".simplesyncrc"
# First line is your email address
# Second line is your Simplenote password
# Third line is the directory to be used for text files

open (CONFIG, "<$ENV{HOME}/.simplesyncrc") or die "Unable to load config file $ENV{HOME}/.simplesyncrc.\n";

my $email = <CONFIG>;
my $password = <CONFIG>;
my $sync_directory = <CONFIG>;
close CONFIG;
chomp ($email, $password, $sync_directory);
$sync_directory = abs_path($sync_directory);

my $url = 'https://simple-note.appspot.com/api/';
my $token;

my $debug = 1;		# enable log messages for troubleshooting


# Initialize Database of last sync information into global array
my $hash_ref = initSyncDatabase($sync_directory);
my %syncNotes = %$hash_ref;

# Initialize database of newly synchronized files
my %newNotes = ();

# Initialize database of files that were deleted this round
my %deletedFromDatabase = ();

# Get authorization token
$token = getToken();


# Do Synchronization
synchronizeNotesToFolder($sync_directory);

writeSyncDatabase($sync_directory);



sub getToken {
	# Connect to server and get a token

	my $content = encode_base64("email=$email&password=$password");
	my $response =  $ua->post($url . "login", Content => $content);

	return $response->content;	
}


sub getNoteIndex {
	# Get list of notes
	my %note = ();

	my $response = $ua->get($url . "index?auth=$token&email=$email");
	my $index = $response->content;
	
	$index =~ s{
		\{(.*?)\}
	}{
		# iterate through notes in index
		my $notedata = $1;
		
		$notedata =~ /"key":\s*"(.*?)"/;
		my $key = $1;
		
		while ($notedata =~ /"(.*?)":\s*"?(.*?)"?(,|\Z)/g) {
			# load note data into hash
			if ($1 ne "key") {
				$note{$key}{$1} = $2;
			}
		}
		
		# Trim fractions of seconds
		$note{$key}{modify} =~ s/\..*$//;
	}egx;
	
	return \%note;
}

sub titleToFilename {
	my $title = shift;
	
	$title .= ".txt";
	
	
	return $title;
}

sub filenameToTitle {
	my $filename = shift;
	
	$filename = basename ($filename);
	$filename =~ s/\.txt$//;
	
	return $filename;
}
sub uploadFileToNote {
	my $filepath = shift;
	my $key = shift;
	
	
	my $title = filenameToTitle($filepath);		# The title for new note

	my $content = "\n";
	open (INPUT, "<$filepath");
	local $/;
	$content .= <INPUT>;					# The content for new note
	close(INPUT);

	my @d=gmtime ((stat("$filepath"))[9]);
	my $modified = sprintf "%4d-%02d-%02d %02d:%02d:%02d", $d[5]+1900,$d[4]+1,$d[3],$d[2],$d[1],$d[0];

	@d = gmtime (readpipe ("stat -f \"%B\" \"$filepath\""));
	my $created = sprintf "%4d-%02d-%02d %02d:%02d:%02d", $d[5]+1900,$d[4]+1,$d[3],$d[2],$d[1],$d[0];

	if (defined($key)) {
		# We are updating an old note
		my $modifyString = $modified ? "&modify=$modified" : "";

		my $response = $ua->post($url . "note?key=$key&auth=$token&email=$email$modifyString", Content => encode_base64($title ."\n" . $content));

	} else {
		# We are creating a new note
		my $modifyString = $modified ? "&modify=$modified" : "";
		my $createString = $created ? "&create=$created" : "";

		my $response = $ua->post($url . "note?auth=$token&email=$email$modifyString$createString", Content => encode_base64($title ."\n" . $content));
		
		# Return the key of the newly created note
		$key = $response->content;
	}
	# Add this note to the sync'ed list
	$newNotes{$key}{modify} = $modified;
	$newNotes{$key}{create} = $created;
	$newNotes{$key}{title} = $title;
	$newNotes{$key}{file} = titleToFilename($title);
	
	return $key;
}

sub downloadNoteToFile {
	my $key = shift;
	my $directory = shift;
	
	# retrieve note
	my $response = $ua->get($url . "note?key=$key&auth=$token&email=$email&encode=base64");
	my $content = decode_base64($response->content);

	if ($content eq "") {
		warn "$key no longer exists on server\n";
		$deletedFromDatabase{$key} = 1;
		return;
	}
	# If note is marked for deletion on the server, don't download
	print "deleted? " . $response->header('note-deleted') . "\n" if $debug;
	if ($response->header('note-deleted') eq "True" ){
		warn "note $key was flagged for deletion\n";
		$deletedFromDatabase{$key} = 1;
		return;
	}
	
	$content =~ s/^(.*?)(\n{1,2}|\Z)//s;		# First line is title
	my $title = $1;
	my $filename = titleToFilename($title);
	
	my $create = my $createStr = $response->header('note-createdate');
	$create =~ /(\d\d\d\d)-(\d\d)-(\d\d)\s*(\d\d):(\d\d):(\d\d)/;
	$create = timegm($6,$5,$4,$3,$2-1,$1);
	$createStr =~ s/\..*$//;
	
	my $modify = my $modifyStr = $response->header('note-modifydate');
	$modify =~ /(\d\d\d\d)-(\d\d)-(\d\d)\s*(\d\d):(\d\d):(\d\d)/;
	$modify = timegm($6,$5,$4,$3,$2-1,$1);
	$modifyStr =~ s/\..*$//;
	
	# Create new file (no overwrite protection!!!!!)
	open (FILE, ">$directory/$filename");
	print FILE $content;
	close FILE;
	
	# Set created and modified time
	# Not sure why this has to be done twice, but it seems to
	utime $create, $create, "$directory/$filename";
	utime $create, $modify, "$directory/$filename";
	
	# Add this note to the sync'ed list
	$newNotes{$key}{modify} = $modifyStr;
	$newNotes{$key}{create} = $createStr;
	$newNotes{$key}{file} = $filename;
	$newNotes{$key}{title} = $title;
	
}


sub deleteNoteOnline {
	my $key = shift;
	
	my $response = $ua->get($url . "delete?key=$key&auth=$token&email=$email");
	
	return $response->content;
}

sub synchronizeNotesToFolder {
	my $directory = shift;
	$directory = abs_path($directory);		# Clean up path

	if (! -d $directory) {
		# Target directory doesn't exist
		die "Destination directory $directory does not exist\n";
	}
	
	# get list of existing notes from server with mod date and delete status
	my $note_ref = getNoteIndex();
	my %note = %$note_ref;
	
	# get list of existing local text files with mod/creation date
	my %file = ();
	
	foreach my $filepath (glob("\"$directory/*.txt\"")) {
		
		my @d=gmtime ((stat("$filepath"))[9]);
		$file{$filepath}{modify} = sprintf "%4d-%02d-%02d %02d:%02d:%02d", $d[5]+1900,$d[4]+1,$d[3],$d[2],$d[1],$d[0];

		@d = gmtime (readpipe ("stat -f \"%B\" \"$filepath\""));
		$file{$filepath}{create} = sprintf "%4d-%02d-%02d %02d:%02d:%02d", $d[5]+1900,$d[4]+1,$d[3],$d[2],$d[1],$d[0];
	}
	
	# Iterate through sync database and assess current state of those files
	
	foreach my $key (keys %syncNotes) {
		# Cycle through each prior note from last sync
		my $last_mod_date = $syncNotes{$key}{modify};
		my $filename = $syncNotes{$key}{file};
		
		if (defined ($file{"$directory/$filename"})) {
			# the current item appears to exist as a local file
			print "$filename exists\n" if $debug;
			if ($file{"$directory/$filename"}{modify} eq $last_mod_date) {
				# file appears unchanged
				print "\tlocal copy unchanged\n" if $debug;
				
				if (defined ($note{$key}{modify})) {
					# Remote copy also exists
					print "\tremote copy exists\n" if $debug;
					
					if ($note{$key}{modify} eq $last_mod_date) {
						# note on server also appears unchanged

						# Nothing more to do
					} else {
						# note on server has changed, but local file hasn't
						print "\tremote file is changed\n\n" if $debug;

						# update local file
						downloadNoteToFile($key,$directory);
					}

					# Remove this file from other queues
					delete($note{$key});
					delete($file{"$directory/$filename"});
				} else {
					# remote file is gone, delete local
					print "\tdelete $filename\n" if $debug;
					File::Path::rmtree("$directory/$filename");
					$deletedFromDatabase{$key} = 1;
					delete($note{$key});
					delete($file{"$directory/$filename"});
				}
			} else {
				# local file appears changed
				print "local file has changed\n" if $debug;

				if ($note{$key}{modify} eq $last_mod_date) {
					# but note on server is old
					print "but server copy is unchanged\n" if $debug;

					# update note on server
					uploadFileToNote("$directory/$filename",$key);

					# Remove this file from other queues
					delete($note{$key});
					delete($file{"$directory/$filename"});
				} else {
					# note on server has also changed

					# Need to merge the two files TODO ****

					print "Collision with $filename\n"; # if $debug;

					# Remove this file from other queues
					delete($note{$key});
					delete($file{"$directory/$filename"});
				}
			}
		} else {
			# no file exists - it must have been deleted locally

			if ($note{$key}{modify} eq $last_mod_date) {
				# note on server also appears unchanged

				# so we delete this file
				print "kill $filename\n" if $debug;
				deleteNoteOnline($key);
				
				
				# Remove this file from other queues
				delete($note{$key});
				delete($file{"$directory/$filename"});
				$deletedFromDatabase{$key} = 1;
				
			} else {
				# note on server has also changed
				warn "Collision with $filename\n"; # if $debug;

				# So, download from the server to resync, and
				#	user must then re-delete if desired
				downloadNoteToFile($key,$directory);
				
				# Remove this file from other queues
				delete($note{$key});
				delete($file{"$directory/$filename"});
			}
		}
	}
	
	# Now, we need to look at new notes on server
	
	foreach my $key (sort keys %note) {
		downloadNoteToFile($key, $directory);
	}
	
	# Finally, we need to look at new files locally
	
	foreach my $new_file (sort keys %file) {
		print "new local file $new_file\n" if $debug;
		uploadFileToNote($new_file);
	}
}


sub initSyncDatabase{
	# from <http://docstore.mik.ua/orelly/perl/cookbook/ch11_11.htm>
	
	my $directory = shift;
	my %synchronizedNotes = ();
	
	if (open (DB, "<$directory/simplesync.db")) {
	
		$/ = "";                # paragraph read mode
		while (<DB>) {
			my @array = ();

			my @fields = split /^([^:]+):\s*/m;
			shift @fields;      # for leading null field
			push(@array, { map /(.*)/, @fields });

			for my $record (@array) {
				for my $key (sort keys %$record) {
					$synchronizedNotes{$record->{key}}{$key} = $record->{$key};
				}
			}
		}

		close DB;
	}
	
	return \%synchronizedNotes;
}

sub writeSyncDatabase{
	# from <http://docstore.mik.ua/orelly/perl/cookbook/ch11_11.htm>
	
	my ($directory) = @_;

	open (DB, ">$directory/simplesync.db");
	
	foreach my $record (sort keys %newNotes) {
		for my $key (sort keys %{$newNotes{$record}}) {
			$syncNotes{$record}{$key} = ${$newNotes{$record}}{$key};
		}
	}
	
	foreach my $key (sort keys %deletedFromDatabase) {
		delete($syncNotes{$key});
	}
	
	foreach my $record (sort keys %syncNotes) { 
		print DB "key: $record\n";
		for my $key (sort keys %{$syncNotes{$record}}) {
			print DB "$key: ${$syncNotes{$record}}{$key}\n";
		}
		print DB "\n";
	}

	
	close DB;
}


=head1 NAME

SimpleSync.pl - synchronize a folder of text files with Simplenote.

=head1 CONFIGURATION

1 Create file in your home directory named ".simplesyncrc"

2 First line is your email address

3 Second line is your Simplenote password

4 Third line is the directory to be used for text files

Unfortunately, you have to install Crypt::SSLeay to get https to work. You can
do this by running the following command as an administrator:

sudo perl -MCPAN -e "install Crypt::SSLeay"

=head1 DESCRIPTION

After specifying a folder to store local text files, and the email address and
password associated with your Simplenote account, SimpleSync will attempt to
synchronize the information in both places.

Sync information is stored in "simplesync.db". If this file is lost,
SimpleSync will have to attempt to look for "collisions" between local files
and existing notes. When performing the first synchronization, it's best to
start with an empty local folder (or an empty collection of notes on
Simplenote), and then start adding files (or notes) afterwards.

=head1 WARNING

Please note that this software is still in development stages - I STRONGLY
urge you to backup all of your data before running to ensure nothing is lost.
If you run SimpleSync on an empty local folder without a "simplesync.db" file,
the net result will be to copy the remote notes to the local folder,
effectively performing a backup.

=head1 KNOWN ISSUES

* No protection against overwriting files that have the same title

* No merging when both local and remote file are changed between syncs

* the code is really ugly

* it's probably not very efficient and might really bog down with large
  numbers of notes

* renaming notes or text files causes it to be treated as a new note

=head1 SEE ALSO

Designed for use with Simplenote for iPhone:

<http://www.simplenoteapp.com/>

SimpleSync is available on github:

<http://github.com/fletcher/SimpleSync>

=head1 AUTHOR

Fletcher T. Penney, E<lt>owner@fletcherpenney.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Fletcher T. Penney

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the
   Free Software Foundation, Inc.
   59 Temple Place, Suite 330
   Boston, MA 02111-1307 USA

=cut