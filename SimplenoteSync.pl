#!/usr/bin/env perl
#
# SimplenoteSync.pl
#
# Copyright (c) 2009 Fletcher T. Penney
#	<http://fletcherpenney.net/>
#
#

# TODO: cache authentication token between runs
# TODO: How to handle simultaneous edits?
# TODO: need to compare information between local and remote files when same title in both (e.g. simplenotesync.db lost, or collision)
# TODO: Windows compatibility?? This has not been tested AT ALL yet
# TODO: Further testing on Linux - mainly file creation time

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
use Encode 'decode_utf8';
use Encode;

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
my $file_extension = <CONFIG>;
my $sync_directory;


if (! defined ($file_extension)) {
	$file_extension = "txt";
}

close CONFIG;
chomp ($email, $password, $rc_directory, $file_extension);

if ($rc_directory eq "") {
	# If a valid directory isn't specified, then don't keep going
	die "A directory was not specified.\n";
};

$rc_directory =~ s/\\ / /g;

if ($sync_directory = abs_path($rc_directory)) {
} else {
	# If a valid directory isn't specified, then don't keep going
	die "\"$rc_directory\" does not appear to be a valid directory.\n";
};

$file_extension =~ s/^\s*\.(.*?)\s*$/$1/;

if ($file_extension =~ /^\s*$/) {
	$file_extension = "txt";
}

my $url = 'https://simple-note.appspot.com/api/';
my $token;


# Options
my $debug = 1;					# enable log messages for troubleshooting
my $allow_local_updates = 1;	# Allow changes to local text files
my $allow_server_updates = 1;	# Allow changes to Simplenote server
my $store_base_text = 0;		# Trial mode to allow conflict resolution
my $flag_network_traffic = 0;	# Print a warning for each network call

# On which OS are we running?
my $os = $^O;	# Mac = darwin; Linux = linux; Windows contains MSWin

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


# Write new database for next time
writeSyncDatabase($sync_directory);


1;


sub getToken {
	# Connect to server and get a authentication token

	my $content = encode_base64("email=$email&password=$password");

	warn "Network: get token\n" if $flag_network_traffic;
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
	
	warn "Network: get note index\n" if $flag_network_traffic;
	my $response = $ua->get($url . "index?auth=$token&email=$email");
	my $index = $response->content;
	
	$index =~ s{
		\{(.*?)\}
	}{
		# iterate through notes in index and load into hash
		my $notedata = $1;
		
		$notedata =~ /"key":\s*"(.*?)"/;
		my $key = $1;
		
		while ($notedata =~ /"(.*?)":\s*"?(.*?)"?(,|\Z)/g) {
			# load note data into hash
			if ($1 ne "key") {
				$note{$key}{$1} = $2;
			}
		}
		
		# Trim fractions of seconds from modification time
		$note{$key}{modify} =~ s/\..*$//;
	}egx;
	
	return \%note;
}


sub titleToFilename {
	# Convert note's title into valid filename
	my $title = shift;
	
	# Strip prohibited characters
	$title =~ s/[:\\\/]/ /g;
	
	$title .= ".$file_extension";
	
	return $title;
}


sub filenameToTitle {
	# Convert filename into title and unescape special characters
	my $filename = shift;
	
	$filename = basename ($filename);
	$filename =~ s/\.$file_extension$//;
	
	return $filename;
}


sub uploadFileToNote {
	# Given a local file, upload it as a note at simplenote web server
	my $filepath = shift;
	my $key = shift;		# Supply key if we are updating existing note
	
	my $title = filenameToTitle($filepath);		# The title for new note

	my $content = "\n";							# The content for new note
	open (INPUT, "<$filepath");
	local $/;
	$content .= <INPUT>;
	close(INPUT);

	# Check to make sure text file is encoded as UTF-8
	if (eval { decode_utf8($content, Encode::FB_CROAK); 1 }) {
		# $content is valid utf8
	} else {
		# $content is not valid utf8 - assume it's macroman and convert
		warn "$filepath is not a UTF-8 file. Will try to convert\n" if $debug;
		$content = decode('MacRoman', $content);
		utf8::encode($content);
	}

	my @d = gmtime ((stat("$filepath"))[9]);	# get file's modification time
	my $modified = sprintf "%4d-%02d-%02d %02d:%02d:%02d", $d[5]+1900,$d[4]+1,$d[3],$d[2],$d[1],$d[0];

	if ($os =~ /darwin/i) {
		# The following works on Mac OS X - need a "birth time", not ctime
		@d = gmtime (readpipe ("stat -f \"%B\" \"$filepath\""));	# created time		
	} else {
		# TODO: Need a better way to do this on non Mac systems
		@d = gmtime ((stat("$filepath"))[9]);	# get file's modification time
	}
	
	my $created = sprintf "%4d-%02d-%02d %02d:%02d:%02d", $d[5]+1900,$d[4]+1,$d[3],$d[2],$d[1],$d[0];

	if (defined($key)) {
		# We are updating an old note
		
		my $modifyString = $modified ? "&modify=$modified" : "";

		warn "Network: update existing note \"$title\"\n" if $flag_network_traffic;
		my $response = $ua->post($url . "note?key=$key&auth=$token&email=$email$modifyString", Content => encode_base64($title ."\n" . $content)) if ($allow_server_updates);
	} else {
		# We are creating a new note
		
		my $modifyString = $modified ? "&modify=$modified" : "";
		my $createString = $created ? "&create=$created" : "";

		warn "Network: create new note \"$title\"\n" if $flag_network_traffic;
		my $response = $ua->post($url . "note?auth=$token&email=$email$modifyString$createString", Content => encode_base64($title ."\n" . $content)) if ($allow_server_updates);
		
		# Return the key of the newly created note
		if ($allow_server_updates) {
			$key = $response->content;
		} else {
			$key = 0;
		}
	}
	
	# Add this note to the sync'ed list for writing to database
	$newNotes{$key}{modify} = $modified;
	$newNotes{$key}{create} = $created;
	$newNotes{$key}{title} = $title;
	$newNotes{$key}{file} = titleToFilename($title);

	if (($store_base_text) && ($allow_local_updates)) {
		# Put a copy of note in storage
		my $copy = dirname($filepath) . "/SimplenoteSync Storage/" . basename($filepath);
		copy($filepath,$copy);		
	}
	
	return $key;
}


sub downloadNoteToFile {
	# Save local copy of note from Simplenote server
	my $key = shift;
	my $directory = shift;
	my $overwrite = shift;
	my $storage_directory = "$directory/SimplenoteSync Storage";
	
	# retrieve note

	warn "Network: retrieve existing note \"$key\"\n" if $flag_network_traffic;
	my $response = $ua->get($url . "note?key=$key&auth=$token&email=$email&encode=base64");
	my $content = decode_base64($response->content);

	if ($content eq "") {
		# No such note exists any longer
		warn "$key no longer exists on server\n";
		$deletedFromDatabase{$key} = 1;
		return;
	}

	# Parse into title and content (if present)
	$content =~ s/^(.*?)(\n{1,2}|\Z)//s;		# First line is title
	my $title = $1;
	my $divider = $2;
	
	# If first line is particularly long, it will get trimmed, so
	# leave it in body, and make a short version for the title
	if (length($title) > 240) {
		# Restore first line to content and create new title
		$content = $title . $divider . $content;
		$title = trimTitle($title);
	}
	
	my $filename = titleToFilename($title);
		
	# If note is marked for deletion on the server, don't download
	if ($response->header('note-deleted') eq "True" ) {
		if (($overwrite == 1) && ($allow_local_updates)) {
			# If we're in overwrite mode, then delete local copy
			File::Path::rmtree("$directory/$filename");
			$deletedFromDatabase{$key} = 1;
			
			if ($store_base_text) {
				# Delete storage copy
				File::Path::rmtree("$storage_directory/$filename");
			}
		} else {
			warn "note $key was flagged for deletion on server - not downloaded\n" if $debug;
			# Optionally, could add "&dead=1" to force Simplenote to remove
			#	this note from the database. Could cause problems on iPhone
			#	Just for future reference....
			$deletedFromDatabase{$key} = 1;
		}
		return "";
	}
	
	# Get time of note creation (trim fractions of seconds)
	my $create = my $createString = $response->header('note-createdate');
	$create =~ /(\d\d\d\d)-(\d\d)-(\d\d)\s*(\d\d):(\d\d):(\d\d)/;
	$create = timegm($6,$5,$4,$3,$2-1,$1);
	$createString =~ s/\..*$//;

	# Get time of note modification (trim fractions of seconds)	
	my $modify = my $modifyString = $response->header('note-modifydate');
	$modify =~ /(\d\d\d\d)-(\d\d)-(\d\d)\s*(\d\d):(\d\d):(\d\d)/;
	$modify = timegm($6,$5,$4,$3,$2-1,$1);
	$modifyString =~ s/\..*$//;
	
	# Create new file
	
	if ((-f "$directory/$filename")  && 
		($overwrite == 0)) {
		# A file already exists with that name, and we're not intentionally
		#	replacing with a new copy.
		warn "$filename already exists. Will not download.\n";
		
		return "";
	} else {
		if ($allow_local_updates) {
			open (FILE, ">$directory/$filename");
			print FILE $content;
			close FILE;

			if ($store_base_text) {
				# Put a copy in storage
				open (FILE, ">$storage_directory/$filename");
				print FILE $content;
				close FILE;
			}

			# Set created and modified time
			# Not sure why this has to be done twice, but it seems to on Mac OS X
			utime $create, $create, "$directory/$filename";
			utime $create, $modify, "$directory/$filename";

			$newNotes{$key}{modify} = $modifyString;
			$newNotes{$key}{create} = $createString;
			$newNotes{$key}{file} = $filename;
			$newNotes{$key}{title} = $title;

			# Add this note to the sync'ed list for writing to database
			return $filename;
		}
	}
	
	return "";
}


sub trimTitle {
	# If title is too long, it won't be a valid filename
	my $title = shift;
		
	$title =~ s/^(.{1,240}).*?$/$1/;
	$title =~ s/(.*)\s.*?$/$1/;			# Try to trim at a word boundary

	return $title;
}

sub deleteNoteOnline {
	# Delete specified note from Simplenote server
	my $key = shift;
	
	if ($allow_server_updates) {
		warn "Network: delete note \"$key\"\n" if $flag_network_traffic;
		my $response = $ua->get($url . "delete?key=$key&auth=$token&email=$email");
		return $response->content;
	} else {
		return "";
	}
}


sub mergeConflicts{
	# Both the local copy and server copy were changed since last sync
	# We'll merge the changes into a new master file, and flag any conflicts
	my $key = shift;
	
	
}


sub synchronizeNotesToFolder {
	# Main Synchronization routine
	my $directory = shift;
	$directory = abs_path($directory);		# Clean up path

	if (! -d $directory) {
		# Target directory doesn't exist
		die "Destination directory \"$directory\" does not exist\n";
	}
	
	my $storage_directory = "$directory/SimplenoteSync Storage";
	if ((! -e $storage_directory) && $store_base_text) {
		# This directory saves a copy of the text at each successful sync
		#	to allow three way merging
		mkdir $storage_directory;
	}
	
	# get list of existing notes from server with mod date and delete status
	my $note_ref = getNoteIndex();
	my %note = %$note_ref;
	
	# get list of existing local text files with mod/creation date
	my %file = ();
	
	my $glob_directory = $directory;
	$glob_directory =~ s/ /\\ /g;
	
	foreach my $filepath (glob("$glob_directory/*.$file_extension")) {
		$filepath = abs_path($filepath);
		my @d=gmtime ((stat("$filepath"))[9]);
		$file{$filepath}{modify} = sprintf "%4d-%02d-%02d %02d:%02d:%02d", $d[5]+1900,$d[4]+1,$d[3],$d[2],$d[1],$d[0];

		if ($os =~ /darwin/i) {
			# The following works on Mac OS X - need a "birth time", not ctime
			# created time
			@d = gmtime (readpipe ("stat -f \"%B\" \"$filepath\""));
		} else {
			# TODO: Need a better way to do this on non Mac systems
			# get file's modification time
			@d = gmtime ((stat("$filepath"))[9]);
		}

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
						print "\tremote file is changed\n" if $debug;
						
						if ($note{$key}{deleted} eq "true") {
							# Remote note was flagged for deletion
							warn "Deleting $filename as it was deleted on server\n";
							if ($allow_local_updates) {
								File::Path::rmtree("$directory/$filename");
								delete($file{"$directory/$filename"});
							}
						} else {
							# Remote note not flagged for deletion
							# update local file and overwrite if necessary
							my $newFile = downloadNoteToFile($key,$directory,1);

							if (($newFile ne $filename) && ($newFile ne "")) {
								warn "Deleting $filename as it was renamed to $newFile\n";
								# The file was renamed on server; delete old copy
								if ($allow_local_updates) {
									File::Path::rmtree("$directory/$filename");								
									delete($file{"$directory/$filename"});
								}
							}
						}
					}

					# Remove this file from other queues
					delete($note{$key});
					delete($file{"$directory/$filename"});
				} else {
					# remote file is gone, delete local
					print "\tdelete $filename\n" if $debug;
					File::Path::rmtree("$directory/$filename") if ($allow_local_updates);
					$deletedFromDatabase{$key} = 1;
					delete($note{$key});
					delete($file{"$directory/$filename"});
				}
			} else {
				# local file appears changed
				print "\tlocal file has changed\n" if $debug;

				if ($note{$key}{modify} eq $last_mod_date) {
					# but note on server is old
					print "\tbut server copy is unchanged\n" if $debug;

					# update note on server
					uploadFileToNote("$directory/$filename",$key);

					# Remove this file from other queues
					delete($note{$key});
					delete($file{"$directory/$filename"});
				} else {
					# note on server has also changed
					warn "$filename was modified locally and on server - please check file for conflicts.\n";

					# Use the stored copy from last sync to enable a three way
					#	merge, then use this as the official copy and allow
					#	user to manually edit any conflicts

					mergeConflicts($key);

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
				
				if ($note{$key}{deleted} eq "true") {
					# note on server was deleted also
					print "delete $filename\n" if $debug;
					
					# Don't do anything locally
					delete($note{$key});
					delete($file{"$directory/$filename"});
				} else {
					warn "$filename deleted locally but modified on server\n";

					# So, download from the server to resync, and
					#	user must then re-delete if desired
					downloadNoteToFile($key,$directory,0);
				
					# Remove this file from other queues
					delete($note{$key});
					delete($file{"$directory/$filename"});
				}
			}
		}
	}
	
	# Now, we need to look at new notes on server and download
	
	foreach my $key (sort keys %note) {
		# Download, but don't overwrite existing file if present
		if ($note{$key}{deleted} ne "true") {
			downloadNoteToFile($key, $directory,0);			
		}
	}
	
	# Finally, we need to look at new files locally and upload to server
	
	foreach my $new_file (sort keys %file) {
		print "new local file $new_file\n" if $debug;
		uploadFileToNote($new_file);
	}
}


sub initSyncDatabase{
	# from <http://docstore.mik.ua/orelly/perl/cookbook/ch11_11.htm>
	
	my $directory = shift;
	my %synchronizedNotes = ();
	
	if (open (DB, "<$directory/simplenotesync.db")) {
	
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
	
	return 0 if (!$allow_local_updates);
	my ($directory) = @_;

	open (DB, ">$directory/simplenotesync.db");
	
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

SimplenoteSync.pl --- synchronize a folder of text files with Simplenote.


Of note, this software is not created by or endorsed by Cloud Factory, the
creators of Simplenote, or anyone else for that matter.

=head1 CONFIGURATION

**UPDATE** --- Notational Velocity now has built in synchronizing with
Simplenote. I have not fully tested it, and can't vouch for or against it's
quality. But, for anyone who is using Simplenotesync just so that their NV
notes and Simplenotes stay in sync, it is probably a *much* easier way to
accomplish this. Most of the support questions I get are from people who are
not very experienced with the command-line --- Notational Velocity's built in
support requires nothing more than your Simplenote user name and password.
Additionally, I am now primarily using WriteRoom, and am not actively working
on SimplenoteSync anymore.  For more information, please visit:

<http://fletcherpenney.net/2010/01/status_update_on_simplenotesync>


**WARNING --- I am having an intermittent problem with the Simplenote server
that causes files to be deleted intermittently. Please use with caution and
backup your data**


**BACKUP YOUR DATA BEFORE USING --- THIS PROJECT IS STILL BEING TESTED. IF YOU
AREN'T CONFIDENT IN WHAT YOU'RE DOING, DON'T USE IT!!!!**

Create file in your home directory named ".simplenotesyncrc" with the
following contents:

1. First line is your email address

2. Second line is your Simplenote password

3. Third line is the directory to be used for text files

4. Fourth (optional line) is a file extension to use (defaults to "txt" if
none specified)

Unfortunately, you have to install Crypt::SSLeay to get https to work. You can
do this by running the following command as an administrator:

=over

sudo perl -MCPAN -e "install Crypt::SSLeay"

=back

=head1 DESCRIPTION

After specifying a folder to store local text files, and the email address and
password associated with your Simplenote account, SimplenoteSync will attempt
to synchronize the information in both places.

Sync information is stored in "simplenotesync.db". If this file is lost,
SimplenoteSync will have to attempt to look for "collisions" between local
files and existing notes. When performing the first synchronization, it's best
to start with an empty local folder (or an empty collection of notes on
Simplenote), and then start adding files (or notes) afterwards.

=head1 WARNING

Please note that this software is still in development stages --- I STRONGLY
urge you to backup all of your data before running to ensure nothing is lost.
If you run SimplenoteSync on an empty local folder without a
"simplenotesync.db" file, the net result will be to copy the remote notes to
the local folder, effectively performing a backup.


=head1 INSTALLATION

Download the latest copy of SimplenoteSync.pl from github:

<http://github.com/fletcher/SimplenoteSync>

=head1 FEATURES

* Bidirectional synchronization between the Simplenote web site and a local
  directory of text files on your computer

* Ability to upload notes to your iPhone without typing them by hand

* Ability to backup the notes on your iPhone

* Perform synchronizations automatically by using cron

* Should handle unicode characters in title and content (works for me in some
  basic tests, but let me know if you have trouble)

* The ability to manipulate your notes (via the local text files) using other
  applications (e.g. [Notational Velocity](http://notational.net/) if you use
  "Plain Text Files" for storage, shell scripts, AppleScript, 
  [TaskPaper](http://www.hogbaysoftware.com/products/taskpaper), etc.) -
  you're limited only by your imagination

* COMING SOON --- The ability to attempt to merge changes if a note is changed
  locally and on the server simultaneously

=head1 LIMITATIONS

* Certain characters are prohibited in filenames (:,\,/) - if present in the
  title, they are stripped out.

* If the simplenotesync.db file is lost, SimplenoteSync.pl is currently unable
  to realize that a text file and a note represent the same object --- instead
  you should move your local text files, do a fresh sync to download all notes
  locally, and manually replace any missing notes.

* Simplenote supports multiple notes with the same title, but two files cannot
  share the same filename. If you have two notes with the same title, only one
  will be downloaded. I suggest changing the title of the other note.


=head1 FAQ

* When I try to use SimplenoteSync, I get the following error:

=over

=over

Network: get token

Error logging into Simplenote server:

HTTP::Response=HASH(0x1009b0110)->content

=back

The only time I have seen this error is when the username or password is
entered into the configuration file incorrectly. Watch out for spaces at the
end of lines.

=back


* Why can I download notes from Simplenote, but local notes aren't being
  uploaded?

=over

Do the text files end in ".txt"? For documents to be recognized as text files
to be uploaded, they have to have that file extension. *Unless* you have
specified an alternate file extension to use in ".simplenotesyncrc".

Text files can't be located in subdirectories - this script does not (by
design) recurse folders looking for files (since they shouldn't be anywhere
but the specified directory).

=back

* When my note is downloaded from Simplenote and then changed locally, I end
  up with two copies of the first line (one shorter than the other) - what
  gives?

=over

If the first line of a note is too long to become the filename, it is trimmed
to an appropriate length. To prevent losing data, the full line is preserved
in the body. Since Simplenote doesn't have a concept of titles, the title
becomes the first line (which is trimmed), and the original first line is now
the third line (counting the blank line in between). Your only alternatives
are to shorten the first line, split it in two, or to create a short title

=back

* If I rename a note, what happens?

=over

If you rename a note on Simplenote by changing the first line, a new text file
will be created and the old one will be deleted, preserving the original
creation date. If you rename a text file locally, the old note on Simplenote
will be deleted and a new one will be created, again preserving the original
creation date. In the second instance, there is not actually any recognition
of a "rename" going on - simply the recognition that an old note was deleted
and a new one exists.

=back

=head1 TROUBLESHOOTING

If SimplenoteSync isn't working, I've tried to add more (and better) error
messages. Common problems so far include:

* Not installing Crypt::SSLeay

* Errors in the "simplenotesyncrc" file

Optionally, you can enable or disable writing changes to either the local
directory or to the Simplenote web server. For example, if you want to attempt
to copy files to your computer without risking your remote data, you can
disable "$allow_server_updates". Or, you can disable "$allow_local_updates" to
protect your local data.

Additionally, there is a script "Debug.pl" that will generate a text file with
some useful information to email to me if you continue to have trouble.

=head1 KNOWN ISSUES

* No merging when both local and remote file are changed between syncs - this
  might be enabled in the future

* the code is still somewhat ugly

* it's probably not very efficient and might really bog down with large
  numbers of notes

* renaming notes or text files causes it to be treated as a new note -
  probably not all bad, but not sure what else to do. For now, you'll have to
  manually delete the old copy


=head1 SEE ALSO

Designed for use with Simplenote for iPhone:

<http://www.simplenoteapp.com/>

The SimplenoteSync homepage is:

<http://fletcherpenney.net/other_projects/simplenotesync/>

SimplenoteSync is available on github:

<http://github.com/fletcher/SimplenoteSync>

A Discussion list is also available:

<http://groups.google.com/group/simplenotesync>

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