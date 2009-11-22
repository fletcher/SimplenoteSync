
# Name #

SimplenoteSync.pl --- synchronize a folder of text files with
Simplenote.

Of note, this software is not created by or endorsed by Cloud Factory,
the creators of Simplenote, or anyone else for that matter.


# Configuration #

**WARNING --- I am having an intermittent problem with the Simplenote server
that causes files to be deleted intermittently. Please use with caution and
backup your data**

**BACKUP YOUR DATA BEFORE USING --- THIS PROJECT IS STILL BEING TESTED.
IF YOU AREN'T CONFIDENT IN WHAT YOU'RE DOING, DON'T USE IT!!!!**

Create file in your home directory named ".simplenotesyncrc" with the
following contents:

1. First line is your email address

2. Second line is your Simplenote password

3. Third line is the directory to be used for text files

4. Fourth (optional line) is a file extension to use (defaults to "txt"
if none specified)

Unfortunately, you have to install Crypt::SSLeay to get https to work.
You can do this by running the following command as an administrator:

	sudo perl -MCPAN -e "install Crypt::SSLeay"


# Description #

After specifying a folder to store local text files, and the email
address and password associated with your Simplenote account,
SimplenoteSync will attempt to synchronize the information in both
places.

Sync information is stored in "simplenotesync.db". If this file is lost,
SimplenoteSync will have to attempt to look for "collisions" between
local files and existing notes. When performing the first
synchronization, it's best to start with an empty local folder (or an
empty collection of notes on Simplenote), and then start adding files
(or notes) afterwards.


# Warning #

Please note that this software is still in development stages --- I
STRONGLY urge you to backup all of your data before running to ensure
nothing is lost. If you run SimplenoteSync on an empty local folder
without a "simplenotesync.db" file, the net result will be to copy the
remote notes to the local folder, effectively performing a backup.


# Installation #

Download the latest copy of SimplenoteSync.pl from github:

<http://github.com/fletcher/SimplenoteSync>


# Features #

* Bidirectional synchronization between the Simplenote web site and a
local directory of text files on your computer

* Ability to upload notes to your iPhone without typing them by hand

* Ability to backup the notes on your iPhone

* Perform synchronizations automatically by using cron

* Should handle unicode characters in title and content (works for me in
some basic tests, but let me know if you have trouble)

* The ability to manipulate your notes (via the local text files) using
other applications (e.g. [Notational Velocity](http://notational.net/)
if you use "Plain Text Files" for storage, shell scripts, AppleScript,
[TaskPaper](http://www.hogbaysoftware.com/products/taskpaper), etc.) -
you're limited only by your imagination

* COMING SOON --- The ability to attempt to merge changes if a note is
changed locally and on the server simultaneously


# Limitations #

* Certain characters are prohibited in filenames (:,\,/) - if present in
the title, they are stripped out.

* If the simplenotesync.db file is lost, SimplenoteSync.pl is currently
unable to realize that a text file and a note represent the same object
--- instead you should move your local text files, do a fresh sync to
download all notes locally, and manually replace any missing notes.

* Simplenote supports multiple notes with the same title, but two files
cannot share the same filename. If you have two notes with the same
title, only one will be downloaded. I suggest changing the title of the
other note.


# Faq #

* When I try to use SimplenoteSync, I get the following error:

		Network: get token
		Error logging into Simplenote server:
		HTTP::Response=HASH(0x1009b0110)->content

	The only time I have seen this error is when the username or
	password is entered into the configuration file incorrectly. Watch
	out for spaces at the end of lines.

* Why can I download notes from Simplenote, but local notes aren't being
uploaded?

	Do the text files end in ".txt"? For documents to be recognized as
	text files to be uploaded, they have to have that file extension.
	*Unless* you have specified an alternate file extension to use in
	".simplenotesyncrc".

	Text files can't be located in subdirectories - this script does not
	(by design) recurse folders looking for files (since they shouldn't
	be anywhere but the specified directory).

* When my note is downloaded from Simplenote and then changed locally, I
end up with two copies of the first line (one shorter than the other) -
what gives?

	If the first line of a note is too long to become the filename, it
	is trimmed to an appropriate length. To prevent losing data, the
	full line is preserved in the body. Since Simplenote doesn't have a
	concept of titles, the title becomes the first line (which is
	trimmed), and the original first line is now the third line
	(counting the blank line in between). Your only alternatives are to
	shorten the first line, split it in two, or to create a short title

* If I rename a note, what happens?

	If you rename a note on Simplenote by changing the first line, a new
	text file will be created and the old one will be deleted,
	preserving the original creation date. If you rename a text file
	locally, the old note on Simplenote will be deleted and a new one
	will be created, again preserving the original creation date. In the
	second instance, there is not actually any recognition of a "rename"
	going on - simply the recognition that an old note was deleted and a
	new one exists.


# Troubleshooting #

If SimplenoteSync isn't working, I've tried to add more (and better)
error messages. Common problems so far include:

* Not installing Crypt::SSLeay

* Errors in the "simplenotesyncrc" file

Optionally, you can enable or disable writing changes to either the
local directory or to the Simplenote web server. For example, if you
want to attempt to copy files to your computer without risking your
remote data, you can disable "$allow_server_updates". Or, you can
disable "$allow_local_updates" to protect your local data.

Additionally, there is a script "Debug.pl" that will generate a text
file with some useful information to email to me if you continue to have
trouble.


# Known Issues #

* No merging when both local and remote file are changed between syncs -
this might be enabled in the future

* the code is still somewhat ugly

* it's probably not very efficient and might really bog down with large
numbers of notes

* renaming notes or text files causes it to be treated as a new note -
probably not all bad, but not sure what else to do. For now, you'll have
to manually delete the old copy


# See Also #

Designed for use with Simplenote for iPhone:

<http://www.simplenoteapp.com/>

The SimplenoteSync homepage is:

<http://fletcherpenney.net/other_projects/simplenotesync/>

SimplenoteSync is available on github:

<http://github.com/fletcher/SimplenoteSync>

A Discussion list is also available:

<http://groups.google.com/group/simplenotesync>


# Author #

Fletcher T. Penney, <owner@fletcherpenney.net>


# Copyright And License #

Copyright (C) 2009 by Fletcher T. Penney

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 2 of the License, or (at your
option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.
59 Temple Place, Suite 330 Boston, MA 02111-1307 USA

